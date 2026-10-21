import DesignSystem
import Foundation
import Testing

@testable import LocalTrivia

// What App Review's guideline 1.2 asks of a game where people see what others
// type: a filter, a way to report, a way to block — and terms agreed first.

// MARK: - Filter

@Suite struct ContentFilterTests {
  @Test(arguments: [
    "fuck", "Fuck off", "f.u.c.k", "F U C K", "fuuuuck", "sh1t", "$hit", "SHIT!", "motherfucker", "bullshit",
    "cunt", "nigger", "faggot", "porn", "dildo", "wanker",
  ])
  func keepsProfanityAndSlursOutOfNames(_ name: String) {
    #expect(!ContentFilter.allows(name, as: .name), "\(name)")
  }

  /// Words a trivia question may need, but nobody needs to be called.
  @Test(arguments: ["Big Dick", "nice ass", "sexy", "boobs", "hitler", "nazi", "kys", "b1tch"])
  func holdsNamesToMore(_ name: String) {
    #expect(!ContentFilter.allows(name, as: .name), "\(name)")
  }

  @Test(arguments: [
    "Who wrote Moby-Dick?", "Which bird is a blue tit?", "Balaam's ass spoke to him", "Who led the Nazi party?",
    "A female dog is called a bitch", "What is Homo sapiens?", "Which English town is Scunthorpe?",
  ])
  func letsTriviaAskWhatItNeeds(_ question: String) {
    #expect(ContentFilter.allows(question, as: .question), "\(question)")
  }

  /// Whole words, never parts of longer ones.
  @Test(arguments: [
    "Ada", "Robin", "Essex Quiz", "Classic", "Therapist", "Kinoshita", "Spicy", "Cockburn", "Dickens", "Sussex",
    "Grass", "Assistant", "Matsushita", "Trivia Night", "Mr. Bass", "Titan", "Wow!", "Go team!!",
  ])
  func leavesInnocentNamesAlone(_ name: String) {
    #expect(ContentFilter.allows(name, as: .name), "\(name)")
  }

  @Test func masksLetterForLetter() {
    #expect(ContentFilter.masked("What the fuck?", as: .question) == "What the ****?")
    #expect(ContentFilter.masked("Sh1t happens", as: .question) == "**** happens")
    #expect(ContentFilter.masked("Moby-Dick", as: .question) == "Moby-Dick")
    #expect(ContentFilter.masked("Moby-Dick", as: .name) == "Moby-****")
    #expect(ContentFilter.masked("f u c k", as: .name) == "* * * *")
  }

  @Test func masksWhatAHostSends() {
    let question = Question(
      questionId: 1, index: 0, qNum: 1, total: 1, text: "What the fuck?", options: ["shit", "B", "C", "D"], category: "CRAP",
      timeLimit: 20, elapsedMs: nil)
    guard case .questionStart(let masked) = ServerEvent.questionStart(question).masked() else {
      Issue.record("not a question")
      return
    }
    #expect(masked.text == "What the ****?")
    #expect(masked.options == ["****", "B", "C", "D"])

    let board = Leaderboard(
      standings: [Leaderboard.Row(rank: 1, nickname: "Ada", score: 10, delta: nil), Leaderboard.Row(rank: 2, nickname: "cunt", score: 5, delta: nil)],
      afterQuestion: 1, totalQuestions: 2, remaining: 1)
    guard case .leaderboard(let shown) = ServerEvent.leaderboard(board).masked() else {
      Issue.record("not a leaderboard")
      return
    }
    #expect(shown.standings.map(\.nickname) == ["Ada", "****"])
  }

  @Test func keepsObjectionableQuestionsOutOfPlay() {
    let clean = HostQuestion(text: "Which planet has the most moons?", options: ["Jupiter", "Saturn", "Uranus", "Neptune"], correct: 1)
    #expect(clean.isPlayable)
    var dirty = clean
    dirty.options[2] = "fuck"
    #expect(dirty.problem == .objectionable)
    #expect(!dirty.isPlayable)
  }
}

// MARK: - Another AI

@Suite struct AIPromptTests {
  @Test func asksForTheTopicCountAndColumnsThisAppImports() {
    let prompt = AIPrompt.text(topic: "  Greek mythology ", count: 12)
    #expect(prompt.contains("Write 12 multiple-choice trivia questions about: Greek mythology\n"))
    #expect(prompt.contains(AIPrompt.header))
    #expect(prompt.contains("12 lines in all"))
    #expect(AIPrompt.text(topic: "x", count: 1).contains("Write 1 multiple-choice trivia question about"))
    #expect(AIPrompt.text(topic: "x", count: 5000).contains("Write 100 "))
  }

  /// The prompt's own example imports, so what it asks for is what works.
  @Test func itsExampleImports() {
    let example = AIPrompt.text(topic: "space", count: 1).components(separatedBy: "For example:\n").last ?? ""
    let result = CSVImport.parse(example)
    #expect(result.errors.isEmpty)
    #expect(result.questions.map(\.text) == ["Which planet has the most moons?"])
    #expect(result.questions.first?.correct == 1)
    #expect(result.questions.first?.timeLimit == 20)
  }

  /// A chat's whole reply, pasted: words, a fenced CSV, more words.
  @Test func importsAChatsReplyPastedWhole() {
    let reply = """
      Here are 2 questions about space!

      ```csv
      question,option_a,option_b,option_c,option_d,correct,category,time_limit
      "Which planet is closest to the Sun?",Venus,Mercury,Mars,Earth,B,SPACE,20
      "How many moons does Mars have, roughly?",None,One,Two,Twelve,C,SPACE,30
      ```

      Let me know if you'd like more!
      """
    let result = CSVImport.parse(reply)
    #expect(result.errors.isEmpty)
    #expect(result.questions.count == 2)
    #expect(result.questions[1].text == "How many moons does Mars have, roughly?")
    #expect(result.questions[1].timeLimit == 30)
  }
}

// MARK: - Blocks

@Suite struct SafetyTests {
  let suite = "SafetyTests-\(UUID().uuidString)"

  @Test func remembersAgreementAndBlocksAcrossLaunches() throws {
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let game = try #require(GameServer(address: "192.168.1.20:3000", name: "Friday Quiz"))

    let first = Safety(defaults: defaults)
    #expect(!first.hasAcceptedTerms)
    first.acceptTerms()
    first.block(host: game, hostID: "host-1")
    first.hide(name: "Mallory")
    first.block(player: "Eve", device: "device-1")

    let relaunched = Safety(defaults: defaults)
    #expect(relaunched.hasAcceptedTerms)
    #expect(relaunched.installID == first.installID)
    #expect(relaunched.isBlocked(game, hostID: "host-1"))
    #expect(relaunched.isHidden("mallory"))
    #expect(relaunched.shown("Mallory") == "Blocked player")
    #expect(relaunched.isBarred(device: "device-1"))
    #expect(!relaunched.isBarred(device: nil))
  }

  /// By id when both have one — a new name or address doesn't hide it — and
  /// otherwise by name at that address: a common name alone hides nobody else.
  @Test func knowsABlockedHostAgain() throws {
    let safety = Safety(defaults: nil)
    let game = try #require(GameServer(address: "192.168.1.20:3000", name: "Trivia Night"))
    safety.block(host: game, hostID: "host-1")

    let moved = try #require(GameServer(address: "192.168.1.44:3001", name: "Renamed"))
    #expect(safety.isBlocked(moved, hostID: "host-1"))
    #expect(!safety.isBlocked(game, hostID: "host-2"), "another host's game with the same name")
    #expect(safety.isBlocked(game, hostID: nil), "found by its address alone")
    let elsewhere = try #require(GameServer(address: "192.168.1.50:3000", name: "Trivia Night"))
    #expect(!safety.isBlocked(elsewhere, hostID: nil))

    safety.unblock(try #require(safety.blockedHosts.first))
    #expect(!safety.isBlocked(moved, hostID: "host-1"))
  }
}

@Suite struct HostBlockingTests {
  final class Recorder {
    var sent: [(event: ServerEvent, audience: HostedGame.Audience)] = []
    func last(to connection: Int) -> ServerEvent? {
      sent.last { $0.audience == .connection(connection) }?.event
    }
  }

  let recorder = Recorder()
  let game: HostedGame

  init() {
    let recorder = recorder
    game = HostedGame(pin: "4821", deliver: { recorder.sent.append(($0, $1)) })
  }

  @discardableResult
  func seat(_ name: String, on connection: Int, device: String? = nil, peer: String? = nil) -> String? {
    game.attach(connection, from: peer ?? "10.0.0.\(connection)")
    game.receive(.join(pin: "4821", nickname: name, device: device), from: connection)
    if case .joined(let snapshot)? = recorder.last(to: connection) { return snapshot.token }
    return nil
  }

  @Test func turnsAwayAnObjectionableNickname() {
    #expect(seat("sh1thead", on: 1) == nil)
    guard case .joinError(let notice)? = recorder.last(to: 1) else {
      Issue.record("no join error")
      return
    }
    #expect(notice.code == "BAD_NICKNAME")
    #expect(GameStore.JoinError(notice).field == .nickname)
  }

  @Test func keepsABlockedPhoneOut() throws {
    var barred: Set<String> = []
    game.isBarred = { device, _ in device.map(barred.contains) ?? false }
    let token = try #require(seat("Eve", on: 1, device: "eve-phone"))
    seat("Ada", on: 2, device: "ada-phone")

    let removed = try #require(game.kick(token: token))
    #expect(removed.device == "eve-phone")
    #expect(removed.peer == "10.0.0.1")
    barred.insert("eve-phone")

    #expect(seat("Eve 2", on: 3, device: "eve-phone") == nil, "under a new name, from the same phone")
    #expect(recorder.last(to: 3) == .joinError(Notice(code: "BLOCKED", message: "THE HOST HAS BLOCKED YOU FROM THIS GAME")))
    #expect(game.connectedPlayers.map(\.nickname) == ["Ada"])
  }

  /// The name leaves every screen at once, not at the next question.
  @Test func takesABlockedNameOffTheStandingsAtOnce() throws {
    let token = try #require(seat("Eve", on: 1))
    seat("Ada", on: 2)
    try game.start(questions: [HostQuestion(text: "Q?", options: ["A", "B", "C", "D"], correct: 0)], rules: HostRules(shuffle: false))
    game.endRound()
    game.showLeaderboard()
    game.kick(token: token)
    guard case .leaderboard(let board)? = recorder.sent.last(where: { $0.audience == .everyone })?.event else {
      Issue.record("no fresh standings")
      return
    }
    #expect(board.standings.map(\.nickname) == ["Ada"])
  }

  @Test func sendsTheDeviceOnTheWire() throws {
    let join = ClientEvent.join(pin: "4821", nickname: "Robin", device: "abc123")
    let json = try JSONEncoder().encode(join)
    #expect(try JSONDecoder().decode(ClientEvent.self, from: json) == join)
    // Anything that couldn't be an id is as good as none.
    let long = Data(#"["join",{"pin":"4821","nickname":"Robin","device":"\#(String(repeating: "x", count: 200))"}]"#.utf8)
    #expect(try JSONDecoder().decode(ClientEvent.self, from: long) == .join(pin: "4821", nickname: "Robin"))
  }
}

// MARK: - Reports

@Suite struct ReportTests {
  @Test func writesAnEmailTheDeveloperCanActOn() throws {
    var report = Report(
      .question(text: "What the ****?", options: ["A1", "B1", "C1", "D1"], category: "SPACE"), gameName: "Friday Quiz", isHost: false,
      blocked: "This player blocked the host and left the game. The host's games are hidden on their phone.")
    report.reason = .sexual
    report.note = "  Third question in  "
    let body = report.mailBody(now: Date(timeIntervalSince1970: 0))
    #expect(report.mailSubject == "Local Trivia report: question")
    #expect(body.contains("Reported: a question (SPACE)"))
    #expect(body.contains("  What the ****?\n  A: A1\n  B: B1"))
    #expect(body.contains("Game: Friday Quiz"))
    #expect(body.contains("Reported by: a player"))
    #expect(body.contains("Reason: Sexual or explicit"))
    #expect(body.contains("Blocked: This player blocked the host"))
    #expect(body.contains("Details: Third question in\n"))
    #expect(body.contains("Sent: 1970-01-01T00:00:00Z"))

    let url = try #require(report.mailURL)
    #expect(url.scheme == "mailto")
    #expect(url.absoluteString.hasPrefix("mailto:report@local-trivia.com?subject=Local%20Trivia%20report"))
  }
}
