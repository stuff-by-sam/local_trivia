import Foundation
import Observation
import OSLog

/// The player's side of a game: a state machine driven by server events.
///
/// Mirrors public/play/play.js. The server is authoritative for everything —
/// scoring, timing, ranks — and this renders what it's told, with one
/// deliberate exception: an answer locks the instant it's tapped, not when the
/// server acks it, because on a busy room's Wi-Fi that round trip is felt.
@Observable
final class GameStore {
  enum Phase: Equatable {
    case join
    case lobby
    /// Joined mid-question; plays from the next one.
    case spectating
    case question(Round)
    case result(Outcome)
    case standings(Standing)
    case final(Standing)
  }

  enum Connection: Equatable {
    case idle
    /// `attempt` counts failures since the last good link — 0 is the first dial.
    case connecting(attempt: Int)
    case online

    var hasFailed: Bool {
      if case .connecting(let attempt) = self { attempt > 0 } else { false }
    }
  }

  struct Round: Equatable {
    let question: Question
    /// The question's lifetime on this phone's clock. The countdown and bar
    /// are drawn by the system from this range, so a running clock costs the
    /// app no per-frame work at all.
    let window: ClosedRange<Date>
    var lockedIndex: Int?
    var acknowledged = false
  }

  struct Outcome: Equatable {
    let result: AnswerResult
    /// Present when this phone saw the question and its reveal, so the result
    /// can say what the answer was — there's no big screen to show it.
    let question: Question?
    let correctIndex: Int?
  }

  struct Standing: Equatable {
    var rank: Int?
    var score: Int
    var podium: [Placing] = []
  }

  /// What the room should be looking at: the game's progress, not this
  /// player's. It's what a big screen shows (see BigScreen/), so it follows
  /// every question whether or not this phone can answer it.
  enum Broadcast: Equatable {
    case lobby
    case question(Question, window: ClosedRange<Date>)
    case reveal(Question, Reveal)
    case standings(Leaderboard)
    case final([Placing])
  }

  /// Why a join didn't go through, and what the player should change.
  struct JoinError: Equatable {
    enum Field { case pin, nickname }

    let message: String
    /// The field that's wrong. Nil when nothing typed was: the host didn't
    /// answer, the game is full, the phone is locked out for a minute.
    let field: Field?

    init(message: String, field: Field?) {
      self.message = message
      self.field = field
    }

    init(_ notice: Notice) {
      message = notice.message ?? String(localized: "Couldn't join that game.")
      switch notice.code {
      case "WRONG_PIN": field = .pin
      case "NICKNAME_TAKEN", "BAD_NICKNAME": field = .nickname
      default: field = nil
      }
    }
  }

  /// server/gameSession.js deals 4-digit PINs (1000–9999).
  nonisolated static let pinLength = 4
  /// The server measures nicknames in UTF-16 code units (JS `length`), 1–20.
  nonisolated static let nicknameLimit = 20

  private(set) var phase: Phase = .join
  private(set) var connection: Connection = .idle
  private(set) var server: GameServer?
  /// The name the server accepted — may differ from the draft being edited.
  private(set) var playerName = ""
  private(set) var playerCount = 0
  private(set) var score = 0
  private(set) var rank: Int?
  private(set) var isJoining = false
  private(set) var joinError: JoinError?
  /// Shown on the join screen after the host removes this player, or ends the game.
  private(set) var notice: String?
  /// Full standings — sent by phone-hosted games, which have no TV to show them.
  private(set) var leaderboard: Leaderboard?
  /// How much of the room has answered — also only from phone-hosted games.
  private(set) var answered: AnsweredCount?
  /// Nil outside a game, or on joining one mid-way until the next event says
  /// where it's got to.
  private(set) var broadcast: Broadcast?
  /// A PIN waiting to be used as soon as the link is up and there's a
  /// nickname: from a join link, or the host joining their own game.
  private(set) var pendingPIN: String?

  /// The nickname draft, remembered across launches.
  var nickname: String {
    didSet {
      defaults.set(nickname, forKey: Keys.nickname)
      // A new name answers a complaint about the old one. (Only a new one: a
      // text field writes the same value back just for being focused.)
      if nickname != oldValue, joinError?.field == .nickname { joinError = nil }
    }
  }

  /// Holding a session the server hasn't confirmed yet — i.e. relaunched
  /// mid-game and waiting to resume.
  var isRejoining: Bool { token != nil && phase == .join }

  var isInGame: Bool { phase != .join }

  /// This player's seat token. Read in-process by a host to recognise its own
  /// seat; it's never displayed or logged.
  var sessionToken: String? { token }

  /// The latest question's place in the running order, for "Q 02/12".
  var progress: (number: Int, total: Int)? {
    lastQuestion.map { ($0.qNum, $0.total) }
  }

  var trimmedNickname: String { nickname.trimmingCharacters(in: .whitespacesAndNewlines) }

  var nicknameIsValid: Bool { (1...Self.nicknameLimit).contains(trimmedNickname.utf16.count) }

  var canJoin: Bool { connection == .online && !isJoining && nicknameIsValid }

  // MARK: - Private state

  /// Preferences hold only what isn't sensitive: the nickname draft and the
  /// last game's address. The resume token goes to `tokens` (the Keychain).
  private enum Keys {
    static let nickname = "nickname"
    /// Not "server": builds that could join a laptop's game kept it there,
    /// and a laptop's game is no longer one to go back to.
    static let server = "lastGame"
  }

  /// The server's resume token for this phone. Persisted so a player whose
  /// app was killed mid-game relaunches straight back into it, score intact.
  /// Observed, not ignored: `isRejoining` derives from it, and a failed resume
  /// changes nothing else a view reads.
  private var token: String? {
    // A seat in a game this phone hosts dies with the app, so it's never kept.
    didSet { tokens.save(server?.isLoopback == true ? nil : token) }
  }
  /// Set when the player chose the current game themselves; discovery then
  /// leaves it alone. A game restored from last launch isn't pinned — the
  /// network may have changed since.
  @ObservationIgnored private var isPinned = false
  /// Games that ended while we were in them. Their Bonjour adverts can linger
  /// a moment; until an advert is gone, discovery mustn't pick it back up.
  @ObservationIgnored private var endedGames: Set<URL> = []
  @ObservationIgnored private var eligibleFrom = 0
  /// Observed: the progress chip ("Q 02/12") reads it between questions.
  private var lastQuestion: Question?
  @ObservationIgnored private var lastReveal: (questionId: Int, reveal: Reveal)?
  @ObservationIgnored private var podium: [Placing] = []

  @ObservationIgnored private var transport: (any GameTransport)?
  @ObservationIgnored private var outbox: AsyncStream<ClientEvent>.Continuation?
  @ObservationIgnored private var pump: Task<Void, Never>?
  @ObservationIgnored private var sender: Task<Void, Never>?
  @ObservationIgnored private var joinDeadline: Task<Void, Never>?

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let tokens: any TokenStore
  @ObservationIgnored private let makeTransport: (URL) -> (any GameTransport)?
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let decoder = JSONDecoder()

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "game")

  init(
    defaults: UserDefaults = .standard,
    tokens: any TokenStore = KeychainTokenStore(),
    makeTransport: @escaping (URL) -> (any GameTransport)? = { SocketConnection(server: $0) },
    now: @escaping () -> Date = Date.init
  ) {
    self.defaults = defaults
    self.tokens = tokens
    self.makeTransport = makeTransport
    self.now = now
    nickname = defaults.string(forKey: Keys.nickname) ?? ""
    // A game this phone hosted ended when the app did; never "rejoin" it.
    let restored = defaults.data(forKey: Keys.server)
      .flatMap { try? JSONDecoder().decode(GameServer.self, from: $0) }
      .flatMap { $0.isLoopback ? nil : $0 }
    server = restored
    // A token means nothing without the server that issued it. The Keychain
    // outlives an uninstall and preferences don't, so a token with no server
    // is a leftover from a previous install: discard it rather than "rejoin"
    // a game the app can't name.
    if restored == nil {
      tokens.save(nil)
      token = nil
    } else {
      token = tokens.load()
    }
  }

  // MARK: - Intents

  /// Dials the last server straight away: a relaunch mid-game resumes before
  /// the first frame settles, and a returning player is usually one PIN away.
  func start() {
    guard transport == nil, let server else { return }
    open(server)
  }

  /// The player picked this game — from the list, a QR code, or by address.
  func connect(to server: GameServer) {
    isPinned = true
    endedGames.remove(server.url)  // chosen on purpose: that's a new game
    select(server)
  }

  /// Bonjour results changed. Picks a game for the player when that's
  /// unambiguous, and never pulls them away from one that's working — or from
  /// one they chose themselves.
  func discovered(_ found: [GameServer]) {
    // An ended game whose advert has gone is forgotten: if it reappears, it's new.
    endedGames.formIntersection(found.map(\.url))
    let games = found.filter { !endedGames.contains($0.url) }
    // The advert names the game where a join link only gives its address (or
    // Bonjour renamed it over a clash): same server, new label. Update it in
    // place, whatever else is going on.
    if let server, let renamed = games.first(where: { $0.url == server.url && $0.name != server.name }) {
      self.server = server.renamed(renamed.name)
      remember(self.server)
    }
    guard phase == .join, connection != .online else { return }
    // Same host, new address (the network gave the host's phone a new IP).
    if let server, let moved = games.first(where: { $0.name == server.name && $0.url != server.url }) {
      select(moved)
      return
    }
    guard !isPinned, server == nil || connection.hasFailed,
      games.count == 1, let only = games.first, only != server
    else { return }
    select(only)
  }

  private func select(_ server: GameServer) {
    guard server != self.server || transport == nil else { return }
    if server.url != self.server?.url { token = nil }
    self.server = server
    remember(server)
    notice = nil
    joinError = nil
    open(server)
  }

  private func remember(_ server: GameServer?) {
    guard server?.isLoopback != true else { return }
    defaults.set(server.flatMap { try? JSONEncoder().encode($0) }, forKey: Keys.server)
  }

  func join(pin: String) {
    guard canJoin else { return }
    isJoining = true
    joinError = nil
    notice = nil
    send(.join(pin: pin, nickname: trimmedNickname))
    joinDeadline?.cancel()
    joinDeadline = Task { [weak self] in
      try? await Task.sleep(for: .seconds(5))
      guard !Task.isCancelled, let self, self.isJoining else { return }
      self.isJoining = false
      self.joinError = JoinError(message: String(localized: "The game didn't answer. Try again."), field: nil)
    }
  }

  func choose(_ option: Int) {
    guard case .question(var round) = phase, round.lockedIndex == nil,
      round.question.options.indices.contains(option), now() < round.window.upperBound
    else { return }
    round.lockedIndex = option
    phase = .question(round)
    send(.submitAnswer(questionId: round.question.questionId, optionIndex: option))
  }

  /// Joins `server` with `pin` — straight away if the link is up and there's a
  /// nickname, otherwise the moment both are. (Join links; the host's own seat.)
  func join(_ server: GameServer, pin: String?) {
    connect(to: server)
    guard let pin else { return }
    pendingPIN = pin
    joinPending()
  }

  private func joinPending() {
    guard let pin = pendingPIN, token == nil, canJoin else { return }
    join(pin: pin)
  }

  /// Drops the game entirely — the host closed it — so discovery starts over.
  /// `endedAt` is the address other phones knew it by, if it differs from ours.
  func forgetGame(endedAt address: URL? = nil) {
    if let url = server?.url { endedGames.insert(url) }
    if let address { endedGames.insert(address) }
    close()
    token = nil
    phase = .join
    score = 0
    rank = nil
    lastQuestion = nil
    leaderboard = nil
    answered = nil
    broadcast = nil
    pendingPIN = nil
    isPinned = false
    server = nil
    remember(nil)
  }

  /// The server has no "leave" event — a player leaves by disconnecting. So
  /// drop the session and re-dial fresh, which stops this phone counting as a
  /// connected player without costing the next join a handshake.
  func leave() {
    token = nil
    // Or the re-dial below would join straight back in.
    pendingPIN = nil
    phase = .join
    score = 0
    rank = nil
    lastQuestion = nil
    leaderboard = nil
    answered = nil
    broadcast = nil
    if let server { open(server) }
  }

  /// Back in the foreground: iOS may have frozen the socket while we were away.
  func sceneDidBecomeActive() {
    guard let transport else { return }
    Task { await transport.refresh() }
  }

  // MARK: - Transport

  private func open(_ server: GameServer) {
    close()
    guard let transport = makeTransport(server.url) else {
      connection = .connecting(attempt: 1)
      return
    }
    self.transport = transport
    connection = .connecting(attempt: 0)

    // One serial outbox, drained by one task: events reach the wire in the
    // order they were sent — `resume` before a re-submitted answer.
    let (outgoing, outbox) = AsyncStream.makeStream(of: ClientEvent.self)
    self.outbox = outbox
    sender = Task {
      for await event in outgoing { await transport.send(event) }
    }
    let events = transport.events
    pump = Task { [weak self] in
      for await event in events {
        guard let self, self.transport === transport else { return }
        self.handle(event)
      }
    }
    Task { await transport.start() }
  }

  private func close() {
    pump?.cancel()
    sender?.cancel()
    outbox?.finish()
    joinDeadline?.cancel()
    if let transport { Task { await transport.stop() } }
    transport = nil
    isJoining = false
    connection = .idle
  }

  private func send(_ event: ClientEvent) {
    outbox?.yield(event)
  }

  func handle(_ event: TransportEvent) {
    switch event {
    case .connecting(let attempt):
      connection = .connecting(attempt: attempt)
    case .connected:
      connection = .online
      if let token { send(.resume(token: token)) } else { joinPending() }
    case .disconnected:
      isJoining = false
    case .message(let json):
      do {
        apply(try decoder.decode(ServerEvent.self, from: json))
      } catch {
        // Private: snapshots carry the resume token, so nothing derived from a
        // payload goes to the persistent log in the clear.
        Self.log.error("undecodable event: \(error, privacy: .private)")
      }
    }
  }

  // MARK: - Server events

  func apply(_ event: ServerEvent) {
    switch event {
    case .joined(let snapshot):
      joinDeadline?.cancel()
      isJoining = false
      pendingPIN = nil
      token = snapshot.token
      restore(snapshot)

    case .joinError(let notice):
      joinDeadline?.cancel()
      isJoining = false
      pendingPIN = nil
      joinError = JoinError(notice)

    case .resumed(let snapshot):
      restore(snapshot)

    case .resumeFailed:
      // The server restarted, or ended the game and forgot us.
      token = nil
      lastQuestion = nil
      broadcast = nil
      phase = .join

    case .kicked(let message):
      if message.code == "HOST_ENDED" {
        // The game is gone, not just our seat: let go of it entirely.
        forgetGame()
      } else {
        token = nil
        pendingPIN = nil
        lastQuestion = nil
        broadcast = nil
        phase = .join
      }
      notice = message.message ?? String(localized: "Removed by the host.")

    case .playerCount(let count):
      playerCount = count

    case .stateChange(let state):
      guard state == .lobby, let token else { return }
      phase = .lobby
      broadcast = .lobby
      send(.resume(token: token))  // refreshes the player count, as play.js does

    case .questionStart(let question):
      guard token != nil else { return }
      lastQuestion = question
      // Its reveal hasn't happened. The last one may carry the same id — ids
      // repeat from game to game — and must never be shown as this answer.
      lastReveal = nil
      answered = nil
      let window = self.window(for: question)
      broadcast = .question(question, window: window)
      phase = question.index < eligibleFrom ? .spectating : .question(Round(question: question, window: window))

    case .answerAck(let questionId):
      guard case .question(var round) = phase, round.question.questionId == questionId else { return }
      round.acknowledged = true
      phase = .question(round)

    case .questionEnd(let reveal):
      // `personalResult` follows at once for anyone who could answer.
      if let lastQuestion {
        lastReveal = (lastQuestion.questionId, reveal)
        broadcast = .reveal(lastQuestion, reveal)
      }

    case .personalResult(let result):
      score = result.totalScore
      rank = result.rank
      phase = .result(outcome(for: result))

    case .personalRank(let update):
      score = update.score
      rank = update.rank
      let standing = Standing(rank: rank, score: score, podium: podium)
      phase = update.phase == .podium ? .final(standing) : .standings(standing)

    case .gameOver(let result):
      podium = result.podium
      guard token != nil else { return }
      broadcast = .final(podium)
      phase = .final(Standing(rank: rank, score: score, podium: podium))

    case .leaderboard(let board):
      leaderboard = board
      if token != nil { broadcast = .standings(board) }

    case .answeredCount(let count):
      answered = count

    case .ignored:
      break
    }
  }

  private func restore(_ snapshot: PlayerSnapshot) {
    playerName = snapshot.nickname
    score = snapshot.score
    rank = snapshot.rank
    eligibleFrom = snapshot.eligibleFrom ?? 0
    if let count = snapshot.playerCount { playerCount = count }

    switch snapshot.state {
    case .lobby:
      podium = []
      lastQuestion = nil
      leaderboard = nil
      answered = nil
      broadcast = .lobby
      phase = .lobby

    case .questionActive:
      guard let question = snapshot.question else {
        // Not eligible for this one: no question, so no stale "Q 01" either.
        lastQuestion = nil
        phase = .spectating
        return
      }
      var round = Round(question: question, window: window(for: question))
      round.lockedIndex = snapshot.lockedIndex
      round.acknowledged = snapshot.lockedIndex != nil
      // An answer tapped while the link was down never reached the server,
      // but the player saw it lock. Honour it now rather than lose it quietly.
      if snapshot.lockedIndex == nil, case .question(let shown) = phase,
        shown.question.questionId == question.questionId, let pending = shown.lockedIndex
      {
        round.lockedIndex = pending
        send(.submitAnswer(questionId: question.questionId, optionIndex: pending))
      }
      lastQuestion = question
      lastReveal = nil
      broadcast = .question(question, window: round.window)
      phase = .question(round)

    case .reveal:
      if let lastQuestion, let lastReveal, lastReveal.questionId == lastQuestion.questionId {
        broadcast = .reveal(lastQuestion, lastReveal.reveal)
      }
      phase = snapshot.lastResult.map { .result(outcome(for: $0)) } ?? .spectating

    case .leaderboard:
      if let leaderboard { broadcast = .standings(leaderboard) }
      phase = .standings(Standing(rank: rank, score: score))

    case .podium:
      if let final = snapshot.podium { podium = final }
      broadcast = .final(podium)
      phase = .final(Standing(rank: rank, score: score, podium: podium))
    }
  }

  /// `elapsedMs` is how far in the host already was, so a phone resuming
  /// mid-question shows the same remaining time as everyone else.
  private func window(for question: Question) -> ClosedRange<Date> {
    let start = now().addingTimeInterval(-(question.elapsedMs ?? 0) / 1000)
    return start...start.addingTimeInterval(question.timeLimit)
  }

  private func outcome(for result: AnswerResult) -> Outcome {
    guard let lastQuestion, let lastReveal, lastReveal.questionId == lastQuestion.questionId else {
      return Outcome(result: result, question: nil, correctIndex: nil)
    }
    return Outcome(result: result, question: lastQuestion, correctIndex: lastReveal.reveal.correctIndex)
  }
}
