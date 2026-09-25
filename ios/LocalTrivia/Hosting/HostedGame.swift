import Foundation
import Observation

/// A game run on this phone: the rules of server/gameSession.js, ported line
/// for line, so a phone-hosted game plays exactly like a laptop-hosted one —
/// the same states, the same scoring and tie-breaks, the same late-joiner and
/// reconnect behaviour, the same events on the wire.
///
/// It knows nothing about sockets. Clients arrive as opaque connection ids;
/// everything the game says goes out through `deliver`, addressed to one
/// connection, to every player, or to everyone attached. That keeps it a pure
/// state machine the tests drive directly.
///
/// Two differences from the laptop, both because there's no TV: standings and
/// the live "answered" count go to every player, not just a presenter.
@Observable
final class HostedGame {
  typealias ConnectionID = HostServer.ConnectionID

  enum Audience: Equatable, Sendable {
    case connection(ConnectionID)
    /// Everyone holding a seat.
    case players
    /// Every attached connection, seated or not (the server's `io.emit`).
    case everyone
  }

  struct Pick: Equatable {
    let option: Int
    let elapsedMs: Int
  }

  struct Player: Identifiable, Equatable {
    let token: String
    let nickname: String
    var connection: ConnectionID?
    var score = 0
    /// Total time taken on correct answers: the tie-break.
    var cumulativeMs = 0
    /// The first question index this player is scored on.
    var eligibleFrom: Int
    var pick: Pick?
    var lastResult: AnswerResult?
    let joinOrder: Int

    var id: String { token }
    var isConnected: Bool { connection != nil }
  }

  enum StartProblem: Error, Equatable {
    case noQuestions
    case noPlayers
  }

  static let maxPlayers = 100
  /// Wrong PINs one phone may try before it's made to wait. A 4-digit PIN only
  /// keeps the wrong room out; this keeps it from being walked. It's counted
  /// per address, not per connection — reconnecting is free.
  static let wrongPINLimit = 5
  static let wrongPINLockout: Duration = .seconds(60)
  static let autoAdvanceDelay: Duration = .seconds(5)
  /// How long a reveal holds before the standings come up on their own —
  /// long enough to take in your result and how the room voted. Unlike the
  /// web game, which waits for the operator, a phone host is also playing,
  /// so this step never asks them for a tap.
  static let revealHold: Duration = .seconds(5)

  let pin: String
  private(set) var state: ServerState = .lobby
  /// In join order.
  private(set) var players: [Player] = []
  /// Zero-based position in the running order; -1 before the first question.
  private(set) var questionIndex = -1
  private(set) var order: [HostQuestion] = []
  private(set) var answered = AnsweredCount(answered: 0, total: 0)

  var connectedPlayers: [Player] { players.filter(\.isConnected) }
  var isLastQuestion: Bool { questionIndex + 1 >= order.count }

  @ObservationIgnored private var rules = HostRules()
  @ObservationIgnored private var questionStartedAt: Duration = .zero
  @ObservationIgnored private var questionLimit = 20
  @ObservationIgnored private var previousRanks: [String: Int]?
  @ObservationIgnored private var deltas: [String: Int] = [:]
  /// Attached connections, and the address each came from.
  @ObservationIgnored private var peers: [ConnectionID: String] = [:]
  /// By address: wrong PINs so far, and when a locked-out one may try again.
  @ObservationIgnored private var wrongPINs: [String: Int] = [:]
  @ObservationIgnored private var lockedOutUntil: [String: Duration] = [:]
  @ObservationIgnored private var joinCount = 0
  @ObservationIgnored private var questionTimer: Task<Void, Never>?
  @ObservationIgnored private var advanceTimer: Task<Void, Never>?

  @ObservationIgnored private let deliver: (ServerEvent, Audience) -> Void
  @ObservationIgnored private let uptime: () -> Duration

  init(
    pin: String = HostedGame.randomPIN(),
    deliver: @escaping (ServerEvent, Audience) -> Void,
    uptime: @escaping () -> Duration = { let origin = ContinuousClock.now; return { ContinuousClock.now - origin } }()
  ) {
    self.pin = pin
    self.deliver = deliver
    self.uptime = uptime
  }

  nonisolated static func randomPIN() -> String {
    String(Int.random(in: 1000...9999))
  }

  var current: HostQuestion? { order.indices.contains(questionIndex) ? order[questionIndex] : nil }

  // MARK: - Connections

  func attach(_ connection: ConnectionID, from peer: String) {
    peers[connection] = peer
  }

  func detach(_ connection: ConnectionID) {
    peers[connection] = nil
    guard let index = players.firstIndex(where: { $0.connection == connection }) else { return }
    players[index].connection = nil
    playersChanged()
    endIfEveryoneAnswered()
  }

  func receive(_ event: ClientEvent, from connection: ConnectionID) {
    switch event {
    case .join(let pin, let nickname): join(pin: pin, nickname: nickname, from: connection)
    case .resume(let token): resume(token: token, from: connection)
    case .submitAnswer(let questionId, let option): submit(questionId: questionId, option: option, from: connection)
    }
  }

  // MARK: - Players

  private func join(pin: String, nickname: String, from connection: ConnectionID) {
    let name = nickname.trimmingCharacters(in: .whitespacesAndNewlines)
    let peer = peers[connection] ?? "#\(connection)"
    // Checked before the PIN, or every lockout would still allow one guess.
    if let until = lockedOutUntil[peer], uptime() < until {
      return deliver(
        .joinError(Notice(code: "TOO_MANY_TRIES", message: "TOO MANY WRONG PINS — TRY AGAIN IN A MINUTE")), .connection(connection))
    }
    guard pin.trimmingCharacters(in: .whitespaces) == self.pin else {
      wrongPINs[peer, default: 0] += 1
      if wrongPINs[peer, default: 0] >= Self.wrongPINLimit {
        wrongPINs[peer] = nil
        lockedOutUntil[peer] = uptime() + Self.wrongPINLockout
      }
      return deliver(.joinError(Notice(code: "WRONG_PIN", message: "WRONG PIN — CHECK THE HOST'S SCREEN")), .connection(connection))
    }
    guard (1...GameStore.nicknameLimit).contains(name.utf16.count) else {
      return deliver(.joinError(Notice(code: "BAD_NICKNAME", message: "NICKNAME MUST BE 1–20 CHARS")), .connection(connection))
    }
    guard !connectedPlayers.contains(where: { $0.nickname.lowercased() == name.lowercased() }) else {
      return deliver(.joinError(Notice(code: "NICKNAME_TAKEN", message: "NICKNAME TAKEN — PICK ANOTHER")), .connection(connection))
    }
    guard !players.contains(where: { $0.connection == connection }) else {
      return deliver(.joinError(Notice(code: "ALREADY_JOINED", message: "ALREADY IN THIS GAME")), .connection(connection))
    }
    guard connectedPlayers.count < Self.maxPlayers else {
      return deliver(.joinError(Notice(code: "GAME_FULL", message: "THIS GAME IS FULL")), .connection(connection))
    }

    joinCount += 1
    let player = Player(
      token: Self.randomToken(),
      nickname: name,
      connection: connection,
      eligibleFrom: state == .lobby ? 0 : questionIndex + 1,
      joinOrder: joinCount
    )
    players.append(player)
    playersChanged()
    deliver(.joined(snapshot(for: player)), .connection(connection))
  }

  private func resume(token: String, from connection: ConnectionID) {
    guard let index = players.firstIndex(where: { $0.token == token }) else {
      return deliver(.resumeFailed, .connection(connection))
    }
    players[index].connection = connection
    playersChanged()
    deliver(.resumed(snapshot(for: players[index])), .connection(connection))
  }

  func kick(token: String) {
    guard let index = players.firstIndex(where: { $0.token == token }) else { return }
    let player = players.remove(at: index)
    if let connection = player.connection {
      deliver(.kicked(Notice(code: nil, message: "REMOVED BY THE HOST")), .connection(connection))
    }
    playersChanged()
    endIfEveryoneAnswered()
  }

  /// The host is leaving: tell everyone, so no phone waits on a game that's
  /// gone. (The host's own seat hears it too, harmlessly: by the time it's
  /// sent, the host's app has already let go of the game.)
  func close() {
    cancelTimers()
    for player in connectedPlayers {
      if let connection = player.connection {
        deliver(.kicked(Notice(code: "HOST_ENDED", message: "THE HOST ENDED THE GAME")), .connection(connection))
      }
    }
  }

  private func playersChanged() {
    deliver(.playerCount(connectedPlayers.count), .players)
    if state == .questionActive { publishAnswered() }
  }

  // MARK: - Flow (the host's controls)

  func start(questions: [HostQuestion], rules: HostRules) throws(StartProblem) {
    guard state == .lobby else { return }
    guard !questions.isEmpty else { throw .noQuestions }
    guard !connectedPlayers.isEmpty else { throw .noPlayers }
    self.rules = rules.clamped()
    order = self.rules.shuffle ? questions.shuffled() : questions
    questionIndex = -1
    previousRanks = nil
    deltas = [:]
    for index in players.indices {
      players[index].score = 0
      players[index].cumulativeMs = 0
      players[index].pick = nil
      players[index].lastResult = nil
      players[index].eligibleFrom = 0
    }
    nextQuestion()
  }

  func next() {
    guard state == .leaderboard else { return }
    nextQuestion()
  }

  /// Moves on without scoring the current question.
  func skip() {
    guard state == .questionActive else { return }
    nextQuestion()
  }

  /// Scores the answers received so far and reveals.
  func endRound() {
    endQuestion()
  }

  func endGame() {
    guard state != .podium, state != .lobby else { return }
    podium()
  }

  func newGame() {
    guard state == .podium else { return }
    state = .lobby
    order = []
    questionIndex = -1
    deliver(.stateChange(.lobby), .everyone)
    playersChanged()
  }

  private func nextQuestion() {
    cancelTimers()
    questionIndex += 1
    guard let question = current else { return podium() }
    questionLimit = question.timeLimit ?? rules.timeLimit
    questionStartedAt = uptime()
    state = .questionActive
    for index in players.indices { players[index].pick = nil }
    deliver(.questionStart(payload(for: question, elapsedMs: 0)), .everyone)
    publishAnswered()

    let index = questionIndex
    questionTimer = Task { [weak self, limit = questionLimit] in
      try? await Task.sleep(for: .seconds(limit))
      guard !Task.isCancelled else { return }
      self?.timeUp(questionIndex: index)
    }
  }

  /// The question's clock ran out. (Internal so tests needn't wait for it.)
  func timeUp(questionIndex index: Int) {
    guard state == .questionActive, index == questionIndex else { return }
    endQuestion()
  }

  private func submit(questionId: Int, option: Int, from connection: ConnectionID) {
    guard state == .questionActive, let question = current, questionId == Self.questionID(for: questionIndex),
      let index = players.firstIndex(where: { $0.connection == connection }),
      players[index].pick == nil, players[index].eligibleFrom <= questionIndex,
      question.options.indices.contains(option)
    else { return }
    let elapsed = uptime() - questionStartedAt
    let elapsedMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    guard elapsedMs <= questionLimit * 1000 else { return }  // late: ignored, as on the server

    players[index].pick = Pick(option: option, elapsedMs: elapsedMs)
    deliver(.answerAck(questionId: questionId), .connection(connection))
    publishAnswered()
    endIfEveryoneAnswered()
  }

  private func publishAnswered() {
    let eligible = connectedPlayers.filter { $0.eligibleFrom <= questionIndex }
    answered = AnsweredCount(answered: eligible.filter { $0.pick != nil }.count, total: eligible.count)
    deliver(.answeredCount(answered), .players)
  }

  private func endIfEveryoneAnswered() {
    guard state == .questionActive else { return }
    let eligible = connectedPlayers.filter { $0.eligibleFrom <= questionIndex }
    if !eligible.isEmpty, eligible.allSatisfy({ $0.pick != nil }) { endQuestion() }
  }

  private func endQuestion() {
    guard state == .questionActive, let question = current else { return }
    cancelTimers()
    state = .reveal

    // Everyone who could answer — including anyone who answered and then
    // dropped: their answer stands.
    let pool = players.indices.filter { players[$0].eligibleFrom <= questionIndex }
    var distribution = [0, 0, 0, 0]
    for index in pool {
      if let pick = players[index].pick { distribution[pick.option] += 1 }
    }
    for index in pool {
      let pick = players[index].pick
      let correct = pick?.option == question.correct
      let points = Scoring.points(
        isCorrect: correct,
        elapsed: pick.map { Double($0.elapsedMs) / 1000 } ?? Double(questionLimit),
        timeLimit: Double(questionLimit),
        rules: rules
      )
      if correct, let pick { players[index].cumulativeMs += pick.elapsedMs }
      players[index].score += points
      players[index].lastResult = AnswerResult(
        correct: correct, points: points, totalScore: players[index].score, rank: nil,
        answered: pick != nil, chosenIndex: pick?.option ?? -1)
    }
    let ranks = Self.rank(connectedPlayers).ranks
    for index in pool {
      guard let result = players[index].lastResult else { continue }
      players[index].lastResult = AnswerResult(
        correct: result.correct, points: result.points, totalScore: result.totalScore,
        rank: ranks[players[index].token] ?? 0, answered: result.answered, chosenIndex: result.chosenIndex)
    }

    deliver(.questionEnd(Reveal(correctIndex: question.correct, distribution: distribution)), .everyone)
    for player in connectedPlayers where player.eligibleFrom <= questionIndex {
      if let connection = player.connection, let result = player.lastResult {
        deliver(.personalResult(result), .connection(connection))
      }
    }
    scheduleAdvance(always: true, after: Self.revealHold) { $0.showLeaderboard() }
  }

  func showLeaderboard() {
    guard state == .reveal else { return }
    cancelTimers()
    let ranks = Self.rank(connectedPlayers).ranks
    deltas = [:]
    for player in connectedPlayers {
      if let previous = previousRanks?[player.token], let now = ranks[player.token] {
        deltas[player.token] = previous - now
      }
    }
    previousRanks = ranks
    state = .leaderboard
    deliver(.leaderboard(leaderboard()), .everyone)
    for player in connectedPlayers {
      if let connection = player.connection {
        deliver(.personalRank(RankUpdate(rank: ranks[player.token], score: player.score, phase: .leaderboard)), .connection(connection))
      }
    }
    scheduleAdvance { $0.next() }
  }

  private func podium() {
    cancelTimers()
    state = .podium
    let result = finalResult()
    deliver(.gameOver(result), .everyone)
    let ranks = Self.rank(connectedPlayers).ranks
    for player in connectedPlayers {
      if let connection = player.connection {
        deliver(.personalRank(RankUpdate(rank: ranks[player.token], score: player.score, phase: .podium)), .connection(connection))
      }
    }
  }

  /// Moves on after `delay` — only with auto-advance on, unless `always`.
  private func scheduleAdvance(always: Bool = false, after delay: Duration = autoAdvanceDelay, _ step: @escaping (HostedGame) -> Void) {
    guard always || rules.autoAdvance else { return }
    advanceTimer = Task { [weak self] in
      try? await Task.sleep(for: delay)
      guard !Task.isCancelled, let self else { return }
      step(self)
    }
  }

  private func cancelTimers() {
    questionTimer?.cancel()
    questionTimer = nil
    advanceTimer?.cancel()
    advanceTimer = nil
  }

  // MARK: - Payloads

  /// Question ids only need to be unique within a game; its position does.
  static func questionID(for index: Int) -> Int { index + 1 }

  private func payload(for question: HostQuestion, elapsedMs: Int) -> Question {
    Question(
      questionId: Self.questionID(for: questionIndex),
      index: questionIndex,
      qNum: questionIndex + 1,
      total: order.count,
      text: question.text,
      options: question.options,
      category: question.category,
      timeLimit: Double(questionLimit),
      elapsedMs: Double(elapsedMs)
    )
  }

  func leaderboard() -> Leaderboard {
    let (list, ranks) = Self.rank(connectedPlayers)
    return Leaderboard(
      standings: list.map { Leaderboard.Row(rank: ranks[$0.token] ?? 0, nickname: $0.nickname, score: $0.score, delta: deltas[$0.token]) },
      afterQuestion: questionIndex + 1,
      totalQuestions: order.count,
      remaining: max(0, order.count - questionIndex - 1)
    )
  }

  private func finalResult() -> GameOver {
    let (list, ranks) = Self.rank(connectedPlayers)
    let standings = list.map { Placing(rank: ranks[$0.token] ?? 0, nickname: $0.nickname, score: $0.score) }
    return GameOver(podium: Array(standings.prefix(3)), standings: standings)
  }

  private func snapshot(for player: Player) -> PlayerSnapshot {
    let isEligibleNow = player.eligibleFrom <= questionIndex
    let elapsed = uptime() - questionStartedAt
    let elapsedMs = Int(elapsed.components.seconds * 1000 + elapsed.components.attoseconds / 1_000_000_000_000_000)
    return PlayerSnapshot(
      token: player.token,
      nickname: player.nickname,
      state: state,
      score: player.score,
      rank: Self.rank(connectedPlayers).ranks[player.token],
      playerCount: connectedPlayers.count,
      eligibleFrom: player.eligibleFrom,
      question: state == .questionActive && isEligibleNow ? current.map { payload(for: $0, elapsedMs: elapsedMs) } : nil,
      lockedIndex: state == .questionActive ? player.pick?.option : nil,
      lastResult: state == .reveal && isEligibleNow ? player.lastResult : nil,
      podium: state == .podium ? finalResult().podium : nil
    )
  }

  // MARK: - Ranking

  /// Points, then less total time on correct answers, then name; equal on
  /// points and time shares a rank. (`rankPlayers` in server/scoring.js.)
  static func rank(_ players: [Player]) -> (list: [Player], ranks: [String: Int]) {
    let list = players.sorted { a, b in
      if a.score != b.score { return a.score > b.score }
      if a.cumulativeMs != b.cumulativeMs { return a.cumulativeMs < b.cumulativeMs }
      return a.nickname.localizedCompare(b.nickname) == .orderedAscending
    }
    var ranks: [String: Int] = [:]
    var previous: Player?
    var previousRank = 0
    for (offset, player) in list.enumerated() {
      let shares = previous.map { $0.score == player.score && $0.cumulativeMs == player.cumulativeMs } ?? false
      let rank = shares ? previousRank : offset + 1
      ranks[player.token] = rank
      previous = player
      previousRank = rank
    }
    return (list, ranks)
  }

  /// 72 bits from the system CSPRNG, as hex — the seat's bearer credential.
  nonisolated static func randomToken() -> String {
    var generator = SystemRandomNumberGenerator()
    return (0..<9).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max, using: &generator)) }.joined()
  }
}
