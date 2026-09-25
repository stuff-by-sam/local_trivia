import Foundation
import Testing

@testable import LocalTrivia

// MARK: - Scoring

/// Mirrors public/shared/scoring.js; the expected numbers are what it returns.
@Suite struct ScoringTests {
  let rules = HostRules(maxPoints: 1000, timeLimit: 20)

  @Test(arguments: [
    (0.0, 1000), (5.0, 750), (10.0, 500), (19.9, 5), (20.0, 0), (25.0, 0), (-1.0, 1000),
  ])
  func fallsLinearlyWithTime(elapsed: Double, expected: Int) {
    #expect(Scoring.points(isCorrect: true, elapsed: elapsed, timeLimit: 20, rules: rules) == expected)
  }

  @Test func guaranteesAFloorForCorrectAnswers() {
    var generous = rules
    generous.minCorrectFraction = 0.5
    #expect(Scoring.points(isCorrect: true, elapsed: 20, timeLimit: 20, rules: generous) == 500)
    #expect(Scoring.points(isCorrect: true, elapsed: 10, timeLimit: 20, rules: generous) == 750)
  }

  @Test func paysTheConsolationForWrongAnswers() {
    var kind = rules
    kind.wrongAnswerPoints = 50
    #expect(Scoring.points(isCorrect: false, elapsed: 1, timeLimit: 20, rules: kind) == 50)
  }

  @Test func roundsHalvesUpLikeMathRound() {
    // 1000 × (2.5 / 20) = 125; 1 × 0.5 → 1 (JS Math.round(0.5) === 1).
    let tiny = HostRules(maxPoints: 1, timeLimit: 20)
    #expect(Scoring.points(isCorrect: true, elapsed: 10, timeLimit: 20, rules: tiny) == 1)
  }

  @Test func clampsRulesToTheServersRanges() {
    let wild = HostRules(maxPoints: 5, timeLimit: 9999, minCorrectFraction: 2, wrongAnswerPoints: -3).clamped()
    #expect(wild.maxPoints == 10)
    #expect(wild.timeLimit == 600)
    #expect(wild.minCorrectFraction == 0.9)
    #expect(wild.wrongAnswerPoints == 0)
  }
}

// MARK: - CSV

/// Mirrors public/shared/csv.js.
@Suite struct CSVImportTests {
  @Test func readsTheDocumentedSample() {
    let sample = """
      question,option_a,option_b,option_c,option_d,correct,category,time_limit
      Which ocean is the deepest?,Atlantic,Indian,Pacific,Arctic,C,GEOGRAPHY,60
      "What is 7 × 8?",54,56,58,64,B,MATH,30
      Who painted the Mona Lisa?,Van Gogh,Da Vinci,Picasso,Rembrandt,B,ART,
      Which gas do plants absorb from the air?,Oxygen,Nitrogen,Carbon dioxide,Helium,C,science,
      """
    let result = CSVImport.parse(sample)
    #expect(result.errors.isEmpty)
    #expect(result.questions.count == 4)
    #expect(result.questions[0].correct == 2)
    #expect(result.questions[0].timeLimit == 60)
    #expect(result.questions[1].text == "What is 7 × 8?")
    #expect(result.questions[2].timeLimit == nil)
    #expect(result.questions[3].category == "SCIENCE")
  }

  @Test func handlesQuotesCommasAndLineEndings() {
    let text = "question,a,b,c,d,correct\r\n\"Say \"\"hi\"\", then, wave\",Yes,No,\"Maybe, later\",Never,3\r\n"
    let result = CSVImport.parse(text)
    #expect(result.questions.first?.text == #"Say "hi", then, wave"#)
    #expect(result.questions.first?.options[2] == "Maybe, later")
    #expect(result.questions.first?.correct == 2)  // 1-based "3" → C
  }

  @Test func skipsATitleLineAboveTheHeader() {
    let text = "marvel_movie_trivia\nquestion,a,b,c,d,correct,category\nWho?,Tony,Steve,Thor,Bruce,A,MARVEL\n"
    let result = CSVImport.parse(text)
    #expect(result.questions.count == 1)
    #expect(result.errors.isEmpty)
  }

  @Test func detectsZeroIndexedKeys() {
    let text = "Q1,a,b,c,d,0\nQ2,a,b,c,d,3\n"
    let result = CSVImport.parse(text)
    #expect(result.questions.map(\.correct) == [0, 3])
    #expect(!result.notes.isEmpty)
  }

  @Test func acceptsTheAnswerTextAsTheKey() {
    #expect(CSVImport.parse("Capital of France?,Lyon,Paris,Nice,Lille,paris\n").questions.first?.correct == 1)
  }

  @Test func reportsBadRowsByLineAndKeepsGoing() {
    let text = "Too short,a,b\nNo key,a,b,c,d,Z\nFine,a,b,c,d,A,,9999\nAlso fine,a,b,c,d,B\n"
    let result = CSVImport.parse(text)
    #expect(result.questions.map(\.text) == ["Fine", "Also fine"])
    #expect(result.questions.first?.timeLimit == nil)  // out of range: ignored, row kept
    #expect(result.errors.count == 3)
    #expect(result.errors.first?.hasPrefix("Line 1") == true)
  }

  /// The web README promises all nine sample banks import cleanly (275
  /// questions). Hold the port to the same promise, on the real files.
  @Test func importsEveryBankInTheRepoCleanly() throws {
    let folder = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent().appending(path: "questions")
    let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
      .filter { $0.pathExtension == "csv" }
    try #require(files.count == 9)
    var total = 0
    for file in files {
      let result = CSVImport.parse(try String(contentsOf: file, encoding: .utf8))
      #expect(result.errors.isEmpty, "\(file.lastPathComponent): \(result.errors)")
      total += result.questions.count
    }
    #expect(total == 275)
  }
}

// MARK: - The round

@Suite struct HostLibraryTests {
  /// The advertised name is a Bonjour name — one DNS label, 63 bytes — and
  /// hosting fails outright past that. 28 emoji are 112 bytes.
  @Test func keepsTheAdvertisedNameWithinABonjourLabel() {
    let library = HostLibrary(fileURL: nil)
    library.gameName = String(repeating: "🎉", count: 28)
    #expect(library.advertisedName.utf8.count <= HostLibrary.nameByteLimit)
    #expect(library.advertisedName.allSatisfy { $0 == "🎉" })
    library.gameName = "  friday quiz "
    #expect(library.advertisedName == "FRIDAY QUIZ")
    library.gameName = "   "
    #expect(library.advertisedName == HostLibrary.defaultName)
  }
}

// MARK: - Engine

/// Drives `HostedGame` directly: connections are plain ids, and everything it
/// says is recorded with who it was addressed to.
@MainActor
@Suite struct HostedGameTests {
  final class Recorder {
    var sent: [(event: ServerEvent, audience: HostedGame.Audience)] = []
    var now: Duration = .zero

    func last(to connection: Int) -> ServerEvent? {
      sent.last { $0.audience == .connection(connection) }?.event
    }
    func all(to audience: HostedGame.Audience) -> [ServerEvent] {
      sent.filter { $0.audience == audience }.map(\.event)
    }
  }

  let recorder = Recorder()
  let game: HostedGame
  let questions = [
    HostQuestion(text: "Which planet has the most moons?", options: ["Jupiter", "Saturn", "Uranus", "Neptune"], correct: 1),
    HostQuestion(text: "What does LAN stand for?", options: ["Large", "Local Area Network", "Linked", "Long"], correct: 1, timeLimit: 10),
  ]
  var rules: HostRules {
    var rules = HostRules()
    rules.shuffle = false
    return rules
  }

  init() {
    let recorder = recorder
    game = HostedGame(
      pin: "4821",
      deliver: { recorder.sent.append(($0, $1)) },
      uptime: { recorder.now }
    )
  }

  /// Each connection comes from its own phone unless `peer` says otherwise.
  @discardableResult
  func seat(_ name: String, on connection: Int, pin: String = "4821", peer: String? = nil) -> String? {
    game.attach(connection, from: peer ?? "10.0.0.\(connection)")
    game.receive(.join(pin: pin, nickname: name), from: connection)
    if case .joined(let snapshot)? = recorder.last(to: connection) { return snapshot.token }
    return nil
  }

  @Test func seatsPlayersAndRefusesTheWrongOnes() {
    #expect(seat("Ada", on: 1) != nil)
    seat("Bob", on: 2, pin: "0000")
    #expect(recorder.last(to: 2) == .joinError(Notice(code: "WRONG_PIN", message: "WRONG PIN — CHECK THE HOST'S SCREEN")))
    seat("ada", on: 3)
    if case .joinError(let notice)? = recorder.last(to: 3) { #expect(notice.code == "NICKNAME_TAKEN") }
    seat(String(repeating: "x", count: 21), on: 4)
    if case .joinError(let notice)? = recorder.last(to: 4) { #expect(notice.code == "BAD_NICKNAME") }
    #expect(game.connectedPlayers.map(\.nickname) == ["Ada"])
  }

  /// Counted per phone, not per connection: reconnecting doesn't buy more guesses.
  @Test func locksOutAPhoneThatKeepsGuessingThePIN() {
    let lockedOut = ServerEvent.joinError(Notice(code: "TOO_MANY_TRIES", message: "TOO MANY WRONG PINS — TRY AGAIN IN A MINUTE"))
    for guess in 0..<HostedGame.wrongPINLimit { seat("Mallory", on: 9, pin: String(1000 + guess), peer: "10.0.0.66") }
    game.detach(9)

    #expect(seat("Mallory", on: 10, peer: "10.0.0.66") == nil, "the right PIN, but from a locked-out phone")
    #expect(recorder.last(to: 10) == lockedOut)
    #expect(seat("Ada", on: 11) != nil, "other phones are unaffected")

    recorder.now += HostedGame.wrongPINLockout
    #expect(seat("Mallory", on: 12, peer: "10.0.0.66") != nil, "and the lockout lifts")
  }

  @Test func needsQuestionsAndPlayersToStart() {
    #expect(throws: HostedGame.StartProblem.noPlayers) { try game.start(questions: questions, rules: rules) }
    seat("Ada", on: 1)
    #expect(throws: HostedGame.StartProblem.noQuestions) { try game.start(questions: [], rules: rules) }
    #expect(game.state == .lobby)
  }

  @Test func playsAQuestionAndScoresItLikeTheServer() throws {
    seat("Ada", on: 1)
    seat("Bob", on: 2)
    try game.start(questions: questions, rules: rules)
    #expect(game.state == .questionActive)
    guard case .questionStart(let question)? = recorder.all(to: .everyone).last else {
      Issue.record("no questionStart")
      return
    }
    #expect(question.qNum == 1)
    #expect(question.timeLimit == 20)

    recorder.now = .seconds(5)
    game.receive(.submitAnswer(questionId: question.questionId, optionIndex: 1), from: 1)  // right, at 5s of 20
    game.receive(.submitAnswer(questionId: question.questionId, optionIndex: 3), from: 1)  // second tap ignored
    #expect(recorder.last(to: 1) == .answerAck(questionId: question.questionId))
    #expect(game.answered == AnsweredCount(answered: 1, total: 2))
    #expect(game.state == .questionActive)

    recorder.now = .seconds(8)
    game.receive(.submitAnswer(questionId: question.questionId, optionIndex: 0), from: 2)  // wrong
    #expect(game.state == .reveal, "everyone answered, so it ends without waiting for the clock")
    #expect(recorder.all(to: .everyone).contains(.questionEnd(Reveal(correctIndex: 1, distribution: [1, 1, 0, 0]))))
    #expect(
      recorder.last(to: 1)
        == .personalResult(AnswerResult(correct: true, points: 750, totalScore: 750, rank: 1, answered: true, chosenIndex: 1)))
    #expect(
      recorder.last(to: 2)
        == .personalResult(AnswerResult(correct: false, points: 0, totalScore: 0, rank: 2, answered: true, chosenIndex: 0)))
  }

  @Test func scoresNobodyWhenTheClockRunsOut() throws {
    seat("Ada", on: 1)
    try game.start(questions: questions, rules: rules)
    game.timeUp(questionIndex: 0)
    #expect(game.state == .reveal)
    #expect(
      recorder.last(to: 1)
        == .personalResult(AnswerResult(correct: false, points: 0, totalScore: 0, rank: 1, answered: false, chosenIndex: -1)))
  }

  @Test func ignoresAnswersAfterTheClock() throws {
    seat("Ada", on: 1)
    seat("Bob", on: 2)
    try game.start(questions: questions, rules: rules)
    recorder.now = .seconds(21)
    game.receive(.submitAnswer(questionId: 1, optionIndex: 1), from: 1)
    #expect(game.answered.answered == 0)
  }

  @Test func holdsLateJoinersForTheNextQuestion() throws {
    seat("Ada", on: 1)
    try game.start(questions: questions, rules: rules)
    seat("Late", on: 2)
    #expect(game.players.last?.eligibleFrom == 1)
    game.receive(.submitAnswer(questionId: 1, optionIndex: 1), from: 2)  // not eligible yet
    #expect(game.answered == AnsweredCount(answered: 0, total: 1))
  }

  @Test func runsTheWholeGameToThePodiumAndBack() throws {
    seat("Ada", on: 1)
    seat("Bob", on: 2)
    try game.start(questions: questions, rules: rules)
    game.receive(.submitAnswer(questionId: 1, optionIndex: 1), from: 1)
    game.receive(.submitAnswer(questionId: 1, optionIndex: 1), from: 2)
    game.showLeaderboard()
    #expect(game.state == .leaderboard)
    guard case .leaderboard(let board)? = recorder.all(to: .everyone).last else {
      Issue.record("standings go to everyone in a phone-hosted game")
      return
    }
    #expect(board.standings.count == 2)
    #expect(board.remaining == 1)
    #expect(!game.isLastQuestion)

    game.next()
    #expect(game.state == .questionActive)
    game.skip()  // no scoring
    #expect(game.state == .podium)
    guard case .gameOver(let result)? = recorder.all(to: .everyone).last else {
      Issue.record("no gameOver")
      return
    }
    #expect(result.podium.count == 2)

    game.newGame()
    #expect(game.state == .lobby)
    #expect(recorder.all(to: .everyone).last == .stateChange(.lobby))
  }

  @Test func sharesARankOnAnExactTie() throws {
    seat("Ada", on: 1)
    seat("Bob", on: 2)
    try game.start(questions: questions, rules: rules)
    game.endRound()  // nobody answered: 0 points, 0 time each
    let ranks = HostedGame.rank(game.connectedPlayers).ranks
    #expect(Set(ranks.values) == [1])
  }

  @Test func removesAKickedPlayer() {
    let token = seat("Ada", on: 1)
    seat("Bob", on: 2)
    game.kick(token: try! #require(token))
    #expect(recorder.last(to: 1) == .kicked(Notice(code: nil, message: "REMOVED BY THE HOST")))
    #expect(game.connectedPlayers.map(\.nickname) == ["Bob"])
  }

  @Test func givesASeatBackOnResume() throws {
    let token = try #require(seat("Ada", on: 1))
    game.detach(1)
    #expect(game.connectedPlayers.isEmpty)
    game.attach(5, from: "10.0.0.1")
    game.receive(.resume(token: token), from: 5)
    guard case .resumed(let snapshot)? = recorder.last(to: 5) else {
      Issue.record("no resume")
      return
    }
    #expect(snapshot.nickname == "Ada")
    game.receive(.resume(token: "nope"), from: 6)
    #expect(recorder.last(to: 6) == .resumeFailed)
  }

  @Test func tellsEveryoneWhenTheHostCloses() {
    seat("Host", on: 1)
    seat("Guest", on: 2)
    game.close()
    let ended = ServerEvent.kicked(Notice(code: "HOST_ENDED", message: "THE HOST ENDED THE GAME"))
    #expect(recorder.last(to: 1) == ended)
    #expect(recorder.last(to: 2) == ended)
  }
}

// MARK: - The whole stack

/// A real server, and real players — the host and a guest, each a full
/// `GameStore` with a real socket — playing over loopback in one process.
@MainActor
@Suite(.serialized) struct HostingEndToEndTests {
  nonisolated final class MemoryTokens: TokenStore, @unchecked Sendable {
    private var value: String?
    func load() -> String? { value }
    func save(_ token: String?) { value = token }
  }

  func player(_ name: String) -> GameStore {
    let store = GameStore(defaults: UserDefaults(suiteName: "HostingE2E-\(UUID().uuidString)")!, tokens: MemoryTokens())
    store.nickname = name
    return store
  }

  func eventually(_ what: String, within limit: Duration = .seconds(5), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + limit
    while !condition() {
      guard ContinuousClock.now < deadline else {
        Issue.record("timed out waiting for \(what)")
        return
      }
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  @Test func hostsAndPlaysAGame() async throws {
    let library = HostLibrary(fileURL: nil)
    library.questions = [
      HostQuestion(text: "Which planet has the most moons?", options: ["Jupiter", "Saturn", "Uranus", "Neptune"], correct: 1),
      HostQuestion(text: "What does LAN stand for?", options: ["Large", "Local Area Network", "Linked", "Long"], correct: 1),
    ]
    library.rules.shuffle = false
    let host = HostController(library: library, advertises: false)
    let hostPlayer = player("Host")

    await host.start(joining: hostPlayer)
    guard case .live(let port) = host.status else {
      Issue.record("didn't start: \(host.status)")
      return
    }
    try await eventually("the host to take a seat") { hostPlayer.phase == .lobby }

    let guest = player("Guest")
    guest.join(try #require(GameServer(address: "127.0.0.1:\(port)")), pin: try #require(host.game?.pin))
    try await eventually("the guest to join") { guest.phase == .lobby }
    #expect(host.game?.connectedPlayers.map(\.nickname) == ["Host", "Guest"])
    // Both seats are loopback here — one process — and the host's is still
    // told apart: by its token, not its address.
    #expect(host.game?.connectedPlayers.map { host.isHost($0) } == [true, false])

    host.perform(.start)
    try await eventually("the first question") { guest.phase.screen == .question(1) && hostPlayer.phase.screen == .question(1) }
    guest.choose(1)
    hostPlayer.choose(0)
    try await eventually("the reveal") { guest.phase.screen == .result && hostPlayer.phase.screen == .result }
    if case .result(let outcome) = guest.phase { #expect(outcome.result.correct) }
    if case .result(let outcome) = hostPlayer.phase { #expect(!outcome.result.correct) }
    try await eventually("the room's answered count") { guest.answered?.answered == 2 || guest.answered == nil }

    // No tap: the reveal moves to the standings by itself.
    try await eventually("standings for everyone", within: HostedGame.revealHold + .seconds(3)) {
      guest.leaderboard?.standings.count == 2
    }
    #expect(guest.leaderboard?.standings.first?.nickname == "Guest")

    await host.stop(leaving: hostPlayer)
    try await eventually("the guest to hear the game ended") { guest.phase == .join }
    #expect(guest.notice == "THE HOST ENDED THE GAME")
    #expect(hostPlayer.server == nil)
    #expect(!host.isHosting)
  }

  /// Leaving asks nothing first, because it can be undone: the host keeps a
  /// dropped player's seat, and the guest's phone keeps its token long
  /// enough to take it back — points and all.
  @Test func aGuestWhoLeavesCanUndoItAndKeepTheirScore() async throws {
    let library = HostLibrary(fileURL: nil)
    library.questions = [
      HostQuestion(text: "Which planet has the most moons?", options: ["Jupiter", "Saturn", "Uranus", "Neptune"], correct: 1),
      HostQuestion(text: "What does LAN stand for?", options: ["Large", "Local Area Network", "Linked", "Long"], correct: 1),
    ]
    library.rules.shuffle = false
    let host = HostController(library: library, advertises: false)
    let hostPlayer = player("Host")
    await host.start(joining: hostPlayer)
    guard case .live(let port) = host.status else {
      Issue.record("didn't start: \(host.status)")
      return
    }
    try await eventually("the host to take a seat") { hostPlayer.phase == .lobby }
    let guest = player("Guest")
    guest.join(try #require(GameServer(address: "127.0.0.1:\(port)")), pin: try #require(host.game?.pin))
    try await eventually("the guest to join") { guest.phase == .lobby }

    host.perform(.start)
    try await eventually("the first question") { guest.phase.screen == .question(1) && hostPlayer.phase.screen == .question(1) }
    guest.choose(1)
    hostPlayer.choose(0)
    try await eventually("the reveal") { guest.phase.screen == .result }
    let earned = guest.score
    #expect(earned > 0, "the guest answered right")

    guest.leave()
    #expect(guest.phase == .join)
    #expect(guest.leftGame != nil, "offers to undo")
    try await eventually("the host to see the guest go") { host.game?.connectedPlayers.map(\.nickname) == ["Host"] }

    guest.undoLeave()
    try await eventually("the guest to be back in the game") { guest.isInGame }
    #expect(guest.playerName == "Guest")
    #expect(guest.score == earned)
    #expect(host.game?.connectedPlayers.map(\.nickname) == ["Host", "Guest"])
    #expect(host.game?.players.count == 2, "the same seat, not a new one")

    // And the room's standings still count what the guest earned.
    try await eventually("standings for everyone", within: HostedGame.revealHold + .seconds(3)) {
      guest.leaderboard?.standings.contains { $0.nickname == "Guest" && $0.score == earned } == true
    }

    await host.stop(leaving: hostPlayer)
  }
}
