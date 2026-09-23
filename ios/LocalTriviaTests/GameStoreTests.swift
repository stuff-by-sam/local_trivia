import Foundation
import Synchronization
import Testing

@testable import LocalTrivia

/// Plays whole games through the store with a scripted transport: events go in
/// through `handle(_:)`, exactly as the socket delivers them, and every frame the
/// store sends is recorded for inspection.
@Suite struct GameStoreTests {
  // MARK: - Harness

  nonisolated final class FakeTransport: GameTransport {
    let url: URL
    let events: AsyncStream<TransportEvent>
    private let log = Mutex<[ClientEvent]>([])
    private let attemptCount = Mutex(0)
    /// While true, sends fail the way the real socket's do when detached.
    let isDetached = Mutex(false)

    init(url: URL) {
      self.url = url
      events = AsyncStream { _ in }
    }

    var sent: [ClientEvent] { log.withLock { $0 } }
    /// Every send, whether or not it went out.
    var attempts: Int { attemptCount.withLock { $0 } }

    func start() {}
    func stop() {}
    func refresh() {}
    func send(_ event: ClientEvent) -> Bool {
      attemptCount.withLock { $0 += 1 }
      guard !isDetached.withLock({ $0 }) else { return false }
      log.withLock { $0.append(event) }
      return true
    }
  }

  nonisolated final class MemoryTokenStore: TokenStore {
    private let value = Mutex<String?>(nil)
    func load() -> String? { value.withLock { $0 } }
    func save(_ token: String?) { value.withLock { $0 = token } }
  }

  final class Clock {
    var now = Date(timeIntervalSince1970: 1_790_000_000)
  }

  let suiteName = "GameStoreTests-\(UUID().uuidString)"
  let defaults: UserDefaults
  /// Shared by every store a test makes, so a second store is a relaunch.
  let tokens = MemoryTokenStore()
  let clock = Clock()
  let lan = GameServer(address: "192.168.1.20")!

  init() {
    defaults = UserDefaults(suiteName: suiteName)!
  }

  func makeStore() -> (GameStore, () -> FakeTransport?) {
    final class Dialed { var transports: [FakeTransport] = [] }
    let dialed = Dialed()
    let clock = clock
    let store = GameStore(
      defaults: defaults,
      tokens: tokens,
      makeTransport: { url in
        let transport = FakeTransport(url: url)
        dialed.transports.append(transport)
        return transport
      },
      now: { clock.now }
    )
    return (store, { dialed.transports.last })
  }

  /// Sends drain through the store's outbox task, so give it a moment — a
  /// generous one: suites run in parallel and share the main actor.
  func sent(by transport: FakeTransport?, count: Int) async throws -> [ClientEvent] {
    let transport = try #require(transport)
    let deadline = ContinuousClock.now + .seconds(10)
    while transport.sent.count < count, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(5))
    }
    return transport.sent
  }

  func deliver(_ store: GameStore, _ json: String) {
    store.handle(.message(Data(json.utf8)))
  }

  func joinedLobby(_ store: GameStore, token: String = "tok-1") {
    deliver(
      store,
      #"["joined",{"state":"LOBBY","token":"\#(token)","nickname":"Robin","score":0,"playerCount":2,"eligibleFrom":0,"rank":null}]"#
    )
  }

  func questionPayload(id: Int, index: Int, elapsedMs: Int = 0, limit: Int = 20) -> String {
    #"""
    {"index":\#(index),"qNum":\#(index + 1),"total":12,"questionId":\#(id),"text":"Which planet has the most confirmed moons?",
     "options":["Jupiter","Saturn","Uranus","Neptune"],"category":"SCIENCE","timeLimit":\#(limit),"elapsedMs":\#(elapsedMs)}
    """#
  }

  func question(id: Int, index: Int, elapsedMs: Int = 0, limit: Int = 20) -> String {
    #"["questionStart",\#(questionPayload(id: id, index: index, elapsedMs: elapsedMs, limit: limit))]"#
  }

  // MARK: - Joining

  @Test func joinsAndRemembersTheSession() async throws {
    let (store, transport) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    #expect(store.connection == .online)

    store.nickname = "Robin"
    store.join(pin: "4821")
    #expect(store.isJoining)
    #expect(try await sent(by: transport(), count: 1) == [.join(pin: "4821", nickname: "Robin")])

    joinedLobby(store)
    #expect(store.phase == .lobby)
    #expect(store.playerName == "Robin")
    #expect(store.playerCount == 2)
    #expect(!store.isJoining)
    #expect(tokens.load() == "tok-1")
  }

  /// The token is a credential for this player's seat: it belongs in the
  /// Keychain, never in preferences, which end up in backups.
  @Test func keepsTheTokenOutOfPreferences() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store, token: "tok-secret")
    let stored = defaults.persistentDomain(forName: suiteName) ?? [:]
    #expect(!stored.values.contains { ($0 as? String) == "tok-secret" })
    #expect(!stored.values.contains { ($0 as? Data).map { String(decoding: $0, as: UTF8.self).contains("tok-secret") } ?? false })
  }

  @Test func showsTheHostsReasonForARejectedPIN() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    store.nickname = "Robin"
    store.join(pin: "0000")
    deliver(store, #"["joinError",{"code":"WRONG_PIN","message":"WRONG PIN — CHECK THE HOST'S SCREEN"}]"#)
    #expect(store.joinError == GameStore.JoinError(message: "WRONG PIN — CHECK THE HOST'S SCREEN", field: .pin))
    #expect(store.phase == .join)
    #expect(!store.isJoining)
  }

  /// A taken name is the name's fault, not the PIN's: the join screen keeps
  /// the PIN and sends the player to the nickname, and a new name clears it.
  @Test func pinsANameClashOnTheNickname() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    store.nickname = "Robin"
    store.join(pin: "4821")
    deliver(store, #"["joinError",{"code":"NICKNAME_TAKEN","message":"NICKNAME TAKEN — PICK ANOTHER"}]"#)
    #expect(store.joinError?.field == .nickname)
    store.nickname = "Robin"  // what a text field does just for being focused
    #expect(store.joinError?.field == .nickname, "the same name answers nothing")
    store.nickname = "Robin 2"
    #expect(store.joinError == nil)
  }

  /// Nothing typed was wrong, so there's nothing to clear — just try again.
  @Test(arguments: ["TOO_MANY_TRIES", "GAME_FULL", "ALREADY_JOINED", "SOMETHING_NEW"])
  func pointsAtNoFieldWhenNothingTypedWasWrong(code: String) {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    store.nickname = "Robin"
    store.join(pin: "4821")
    deliver(store, #"["joinError",{"code":"\#(code)","message":"NOT NOW"}]"#)
    #expect(store.joinError == GameStore.JoinError(message: "NOT NOW", field: nil))
    store.nickname = "Robin 2"
    #expect(store.joinError != nil, "a new name doesn't answer it")
  }

  @Test func measuresNicknamesTheWayTheServerDoes() {
    let (store, _) = makeStore()
    store.nickname = String(repeating: "🎉", count: 10)  // 20 UTF-16 units
    #expect(store.nicknameIsValid)
    store.nickname += "!"
    #expect(!store.nicknameIsValid)
    store.nickname = "   "
    #expect(!store.nicknameIsValid)
  }

  @Test func resumesAfterTheLinkDrops() async throws {
    let (store, transport) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)

    store.handle(.disconnected)
    store.handle(.connecting(attempt: 0))
    #expect(store.connection == .connecting(attempt: 0))
    store.handle(.connected)
    #expect(try await sent(by: transport(), count: 1) == [.resume(token: "tok-1")])
  }

  @Test func relaunchesStraightBackIntoTheGame() async throws {
    do {
      let (first, _) = makeStore()
      first.connect(to: lan)
      first.handle(.connected)
      joinedLobby(first, token: "tok-9")
    }
    let (store, transport) = makeStore()
    #expect(store.server == lan)
    #expect(store.isRejoining)
    store.start()
    store.handle(.connected)
    #expect(try await sent(by: transport(), count: 1) == [.resume(token: "tok-9")])
    deliver(store, #"["resumed",{"state":"LEADERBOARD","token":"tok-9","nickname":"Robin","score":1650,"rank":2}]"#)
    #expect(store.phase == .standings(GameStore.Standing(rank: 2, score: 1650)))
    #expect(!store.isRejoining)
  }

  /// The Keychain survives an uninstall; preferences don't. A token without
  /// the server that issued it is a leftover, not a game to rejoin.
  @Test func dropsATokenLeftBehindByAReinstall() {
    tokens.save("tok-orphan")
    let (store, _) = makeStore()
    #expect(store.server == nil)
    #expect(!store.isRejoining)
    #expect(tokens.load() == nil)
  }

  /// Hosting seats the host over loopback; that game ends with the app, so a
  /// relaunch must not try to rejoin it.
  @Test func neverRemembersAGameThisPhoneHosted() {
    do {
      let (host, _) = makeStore()
      host.join(GameServer(address: "127.0.0.1:3000", name: "FRIDAY QUIZ")!, pin: "4821")
      host.nickname = "Robin"
      host.handle(.connected)
      joinedLobby(host, token: "tok-hosted")
      #expect(host.phase == .lobby)
    }
    #expect(tokens.load() == nil)
    let (relaunched, _) = makeStore()
    #expect(relaunched.server == nil)
    #expect(!relaunched.isRejoining)
  }

  /// Builds that could join a laptop's game remembered it under "server".
  /// Games are only hosted from phones now; that one isn't to go back to.
  @Test func forgetsALaptopGameAnEarlierBuildRemembered() throws {
    defaults.set(try JSONEncoder().encode(lan), forKey: "server")
    tokens.save("tok-laptop")
    let (store, _) = makeStore()
    #expect(store.server == nil)
    #expect(!store.isRejoining)
  }

  /// A join link opened again mid-game leaves its PIN pending. Leaving must
  /// let go of it, or the re-dial joins straight back in.
  @Test func staysOutAfterLeaving() async throws {
    let (store, transport) = makeStore()
    store.nickname = "Robin"
    store.join(lan, pin: "4821")
    store.handle(.connected)
    #expect(try await sent(by: transport(), count: 1) == [.join(pin: "4821", nickname: "Robin")])
    joinedLobby(store)

    store.join(lan, pin: "4821")  // the same link, opened again
    store.leave()
    store.handle(.connected)
    try await Task.sleep(for: .milliseconds(50))
    #expect(try #require(transport()).sent.isEmpty)
    #expect(store.phase == .join)
  }

  // MARK: - Playing

  @Test func playsAQuestionThroughToTheStandings() async throws {
    let (store, transport) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)

    deliver(store, question(id: 44, index: 0))
    guard case .question(let round) = store.phase else {
      Issue.record("expected a question, got \(store.phase)")
      return
    }
    #expect(round.window == clock.now...clock.now.addingTimeInterval(20))

    store.choose(1)
    store.choose(2)  // a second tap never changes a locked answer
    guard case .question(let locked) = store.phase else { return }
    #expect(locked.lockedIndex == 1)
    #expect(!locked.acknowledged)
    #expect(try await sent(by: transport(), count: 1) == [.submitAnswer(questionId: 44, optionIndex: 1)])

    deliver(store, #"["answerAck",{"questionId":44,"locked":true}]"#)
    guard case .question(let acked) = store.phase else { return }
    #expect(acked.acknowledged)

    deliver(store, #"["questionEnd",{"correctIndex":1,"distribution":[0,2,0,0]}]"#)
    deliver(
      store,
      #"["personalResult",{"correct":true,"points":874,"totalScore":874,"rank":1,"answered":true,"chosenIndex":1}]"#)
    guard case .result(let outcome) = store.phase else {
      Issue.record("expected a result, got \(store.phase)")
      return
    }
    #expect(outcome.result.points == 874)
    #expect(outcome.correctIndex == 1)
    #expect(outcome.question?.options[1] == "Saturn")
    #expect(store.score == 874)

    deliver(store, #"["personalRank",{"rank":1,"score":874,"phase":"leaderboard"}]"#)
    #expect(store.phase == .standings(GameStore.Standing(rank: 1, score: 874)))
  }

  @Test func refusesAnswersAfterTheClockRunsOut() async throws {
    let (store, transport) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)
    deliver(store, question(id: 44, index: 0, limit: 20))

    clock.now += 20.5
    store.choose(0)
    guard case .question(let round) = store.phase else { return }
    #expect(round.lockedIndex == nil)
    try await Task.sleep(for: .milliseconds(50))
    #expect(try #require(transport()).sent.isEmpty)
  }

  @Test func matchesTheServersClockWhenResumingMidQuestion() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)
    deliver(store, question(id: 44, index: 0, elapsedMs: 7_500, limit: 20))
    guard case .question(let round) = store.phase else { return }
    #expect(round.window.upperBound == clock.now.addingTimeInterval(12.5))
  }

  @Test func resubmitsAnAnswerTheServerNeverReceived() async throws {
    let (store, transport) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)
    deliver(store, question(id: 44, index: 0))

    // The link drops: the tap still locks on screen, but the send goes nowhere.
    let fake = try #require(transport())
    fake.isDetached.withLock { $0 = true }
    store.handle(.disconnected)
    store.choose(3)
    // Sends drain on their own task: wait for this one to fail before the
    // link comes back, or it goes out late and the order below is a race.
    let deadline = ContinuousClock.now + .seconds(10)
    while fake.attempts < 1, ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(5)) }
    #expect(fake.sent.isEmpty)

    fake.isDetached.withLock { $0 = false }
    store.handle(.connected)
    deliver(
      store,
      #"""
      ["resumed",{"state":"QUESTION_ACTIVE","token":"tok-1","nickname":"Robin","score":0,"eligibleFrom":0,
       "question":\#(questionPayload(id: 44, index: 0, elapsedMs: 4_000)),"lockedIndex":null}]
      """#)

    guard case .question(let round) = store.phase else {
      Issue.record("expected a question, got \(store.phase)")
      return
    }
    #expect(round.lockedIndex == 3)
    #expect(
      try await sent(by: fake, count: 2) == [.resume(token: "tok-1"), .submitAnswer(questionId: 44, optionIndex: 3)])
  }

  /// Question ids start over every game, so the last reveal can share this
  /// question's id. Resuming into this question's reveal must not show it.
  @Test func neverShowsAnEarlierRevealAsThisAnswer() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)
    deliver(store, question(id: 1, index: 0))
    deliver(store, #"["questionEnd",{"correctIndex":3,"distribution":[0,0,0,1]}]"#)

    // The next game's first question; the link drops before its reveal.
    deliver(store, question(id: 1, index: 0))
    store.handle(.disconnected)
    store.handle(.connected)
    deliver(
      store,
      #"""
      ["resumed",{"state":"REVEAL","token":"tok-1","nickname":"Robin","score":0,"eligibleFrom":0,
       "lastResult":{"correct":false,"points":0,"totalScore":0,"rank":1,"answered":false,"chosenIndex":-1}}]
      """#)
    guard case .result(let outcome) = store.phase else {
      Issue.record("expected a result, got \(store.phase)")
      return
    }
    #expect(outcome.correctIndex == nil)
    #expect(outcome.question == nil)
  }

  @Test func holdsLateJoinersUntilTheNextQuestion() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    deliver(
      store,
      #"["joined",{"state":"QUESTION_ACTIVE","token":"tok-2","nickname":"Late","score":0,"eligibleFrom":3,"rank":null}]"#)
    #expect(store.phase == .spectating)

    deliver(store, question(id: 50, index: 2))
    #expect(store.phase == .spectating)
    deliver(store, question(id: 51, index: 3))
    #expect(store.phase.screen == .question(51))
  }

  @Test func tracksProgressAndForgetsItWithTheSession() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)
    #expect(store.progress == nil)
    deliver(store, question(id: 44, index: 1))
    #expect(store.progress?.number == 2)
    #expect(store.progress?.total == 12)

    // Removed, then back in mid-question: the old question number must not linger.
    deliver(store, #"["kicked",{"message":"REMOVED BY THE HOST"}]"#)
    #expect(store.progress == nil)
    deliver(
      store,
      #"["joined",{"state":"QUESTION_ACTIVE","token":"tok-3","nickname":"Robin","score":0,"eligibleFrom":3,"rank":null}]"#)
    #expect(store.phase == .spectating)
    #expect(store.progress == nil)
  }

  @Test func finishesOnThePodium() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)
    deliver(store, #"["gameOver",{"podium":[{"rank":1,"nickname":"Ada","score":3100}],"standings":[]}]"#)
    deliver(store, #"["personalRank",{"rank":4,"score":1200,"phase":"podium"}]"#)
    #expect(
      store.phase
        == .final(GameStore.Standing(rank: 4, score: 1200, podium: [Placing(rank: 1, nickname: "Ada", score: 3100)])))

    deliver(store, #"["stateChange",{"state":"LOBBY"}]"#)
    #expect(store.phase == .lobby)
  }

  /// The server restarted, so it doesn't know our token. Nothing but the token
  /// changes — the phase was already `.join` — and the rejoin screen must
  /// still hear about it, or it spins forever on a game that's gone.
  @Test func leavesTheRejoinScreenWhenTheServerForgetsUs() {
    do {
      let (first, _) = makeStore()
      first.connect(to: lan)
      first.handle(.connected)
      joinedLobby(first, token: "tok-stale")
    }
    let (store, _) = makeStore()
    store.start()
    store.handle(.connected)
    #expect(store.isRejoining)

    nonisolated final class Flag: @unchecked Sendable { var raised = false }
    let redraw = Flag()
    withObservationTracking {
      _ = store.isRejoining
    } onChange: {
      redraw.raised = true
    }
    deliver(store, #"["resumeFailed",{}]"#)
    #expect(redraw.raised, "views reading isRejoining were never told it changed")
    #expect(!store.isRejoining)
  }

  @Test func restoresThePodiumOnRelaunch() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    deliver(
      store,
      #"""
      ["resumed",{"state":"PODIUM","token":"tok-1","nickname":"Robin","score":2900,"rank":2,
       "podium":[{"rank":1,"nickname":"Ada","score":3100},{"rank":2,"nickname":"Robin","score":2900}]}]
      """#)
    #expect(
      store.phase
        == .final(
          GameStore.Standing(
            rank: 2, score: 2900,
            podium: [Placing(rank: 1, nickname: "Ada", score: 3100), Placing(rank: 2, nickname: "Robin", score: 2900)])))
  }

  @Test func returnsToJoinWhenRemoved() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)
    deliver(store, #"["kicked",{"message":"REMOVED BY THE HOST"}]"#)
    #expect(store.phase == .join)
    #expect(store.notice == "REMOVED BY THE HOST")
    #expect(tokens.load() == nil)
  }

  @Test func forgetsASessionTheServerNoLongerKnows() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    joinedLobby(store)
    deliver(store, #"["resumeFailed",{}]"#)
    #expect(store.phase == .join)
    #expect(!store.isRejoining)
  }

  // MARK: - Discovery

  @Test func picksTheOnlyGameOnTheNetwork() throws {
    let (store, transport) = makeStore()
    let found = try #require(GameServer(address: "http://10.0.0.8:3000", name: "FRIDAY QUIZ"))
    store.discovered([found])
    #expect(store.server == found)
    #expect(transport()?.url == found.url)
  }

  @Test func letsThePlayerChooseBetweenGames() throws {
    let (store, _) = makeStore()
    store.discovered([
      try #require(GameServer(address: "192.168.1.10", name: "Den")),
      try #require(GameServer(address: "192.168.1.11", name: "Kitchen")),
    ])
    #expect(store.server == nil)
  }

  @Test func followsAHostToItsNewAddress() throws {
    let (store, transport) = makeStore()
    let before = try #require(GameServer(address: "192.168.1.10", name: "FRIDAY QUIZ"))
    store.connect(to: before)
    let after = try #require(GameServer(address: "192.168.1.77", name: "FRIDAY QUIZ"))
    store.discovered([after])
    #expect(store.server == after)
    #expect(transport()?.url == after.url)
  }

  @Test func respectsAGameThePlayerChose() throws {
    let (store, _) = makeStore()
    let scanned = try #require(GameServer(address: "192.168.1.50:3000"))
    store.connect(to: scanned)
    store.handle(.connecting(attempt: 2))  // failing — but it was their choice
    store.discovered([try #require(GameServer(address: "192.168.1.99", name: "Elsewhere"))])
    #expect(store.server == scanned)
  }

  @Test func movesOffARestoredGameThatsGone() throws {
    do {
      let (first, _) = makeStore()
      first.connect(to: lan)
    }
    let (store, transport) = makeStore()
    store.start()
    store.handle(.connecting(attempt: 1))
    let tonight = try #require(GameServer(address: "http://10.0.0.8:3000", name: "Den"))
    store.discovered([tonight])
    #expect(store.server == tonight)
    #expect(transport()?.url == tonight.url)
  }

  @Test func picksUpTheAdvertisedName() throws {
    let (store, _) = makeStore()
    store.connect(to: lan)  // from a join link: an address, not a name
    store.handle(.connected)
    joinedLobby(store)
    store.discovered([lan.renamed("FRIDAY QUIZ")])
    #expect(store.server?.name == "FRIDAY QUIZ")
    #expect(store.server?.url == lan.url)
    #expect(store.phase == .lobby)
  }

  /// When the host ends the game, let go of it — and don't auto-rejoin its
  /// lingering advert. Once the advert's gone, a new game there is fair game.
  @Test func letsGoOfAGameTheHostEnded() throws {
    let (store, _) = makeStore()
    let party = try #require(GameServer(address: "10.0.0.8:3000", name: "FRIDAY QUIZ"))
    store.discovered([party])
    store.handle(.connected)
    joinedLobby(store)
    deliver(store, #"["kicked",{"code":"HOST_ENDED","message":"THE HOST ENDED THE GAME"}]"#)
    #expect(store.phase == .join)
    #expect(store.server == nil)
    #expect(store.notice == "THE HOST ENDED THE GAME")

    store.discovered([party])  // advert still lingering
    #expect(store.server == nil)
    store.discovered([])  // gone
    store.discovered([party])  // hosting again: a new game
    #expect(store.server == party)
  }

  @Test func neverPullsAPlayerOffAWorkingGame() throws {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    store.discovered([try #require(GameServer(address: "192.168.1.99", name: "Elsewhere"))])
    #expect(store.server == lan)
  }

  // MARK: - The big screen

  /// What a TV shows follows the game through every stage, and lets go of it
  /// with the player.
  @Test func broadcastsEachStageOfTheGame() throws {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    #expect(store.broadcast == nil)
    joinedLobby(store)
    #expect(store.broadcast == .lobby)

    deliver(store, question(id: 44, index: 0))
    guard case .question(let shown, let window)? = store.broadcast else {
      Issue.record("expected the question, got \(String(describing: store.broadcast))")
      return
    }
    #expect(shown.questionId == 44)
    #expect(window == clock.now...clock.now.addingTimeInterval(20))

    deliver(store, #"["questionEnd",{"correctIndex":1,"distribution":[0,2,1,0]}]"#)
    #expect(store.broadcast == .reveal(shown, Reveal(correctIndex: 1, distribution: [0, 2, 1, 0])))

    let standings = #"{"standings":[{"rank":1,"nickname":"Ada","score":900,"delta":null}],"afterQuestion":1,"totalQuestions":2,"remaining":1}"#
    deliver(store, #"["leaderboard",\#(standings)]"#)
    guard case .standings(let board)? = store.broadcast else {
      Issue.record("expected standings, got \(String(describing: store.broadcast))")
      return
    }
    #expect(board.standings.map(\.nickname) == ["Ada"])

    deliver(store, #"["gameOver",{"podium":[{"rank":1,"nickname":"Ada","score":900}],"standings":[]}]"#)
    #expect(store.broadcast == .final([Placing(rank: 1, nickname: "Ada", score: 900)]))

    deliver(store, #"["stateChange",{"state":"LOBBY"}]"#)
    #expect(store.broadcast == .lobby)

    store.leave()
    #expect(store.broadcast == nil)
  }

  /// A phone that joined mid-question can't answer it, but its TV still shows it.
  @Test func broadcastsQuestionsThisPlayerCantAnswerYet() {
    let (store, _) = makeStore()
    store.connect(to: lan)
    store.handle(.connected)
    deliver(
      store,
      #"["joined",{"state":"QUESTION_ACTIVE","token":"tok-2","nickname":"Late","score":0,"eligibleFrom":3,"rank":null}]"#)
    deliver(store, question(id: 50, index: 2))
    #expect(store.phase == .spectating)
    guard case .question(let shown, _)? = store.broadcast else {
      Issue.record("expected the question, got \(String(describing: store.broadcast))")
      return
    }
    #expect(shown.questionId == 50)
  }
}
