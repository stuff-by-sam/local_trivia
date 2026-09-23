import Foundation
import Testing

@testable import LocalTrivia

/// Payload shapes are what `HostedGame` sends, which mirror server/gameSession.js —
/// `playerSnapshot()`, `questionStartPayload()`, `endQuestion()` and friends.
@Suite struct ProtocolTests {
  private func decode(_ json: String) throws -> ServerEvent {
    try JSONDecoder().decode(ServerEvent.self, from: Data(json.utf8))
  }

  @Test func decodesAJoinSnapshot() throws {
    let event = try decode(
      #"""
      ["joined",{"state":"LOBBY","token":"9f2c1a","nickname":"Robin","score":0,"playerCount":3,
       "eligibleFrom":0,"rank":null}]
      """#)
    guard case .joined(let snapshot) = event else {
      Issue.record("expected joined, got \(event)")
      return
    }
    #expect(snapshot.token == "9f2c1a")
    #expect(snapshot.state == .lobby)
    #expect(snapshot.playerCount == 3)
    #expect(snapshot.rank == nil)
    #expect(snapshot.question == nil)
  }

  @Test func decodesAQuestion() throws {
    let event = try decode(
      #"""
      ["questionStart",{"index":1,"qNum":2,"total":12,"questionId":44,"text":"In what year did the Berlin Wall fall?",
       "options":["1987","1989","1991","1993"],"category":"HISTORY","timeLimit":100,"elapsedMs":0}]
      """#)
    guard case .questionStart(let question) = event else {
      Issue.record("expected questionStart, got \(event)")
      return
    }
    #expect(question.questionId == 44)
    #expect(question.options.count == 4)
    #expect(question.timeLimit == 100)
  }

  @Test func decodesTheRestOfAGame() throws {
    #expect(try decode(#"["answerAck",{"questionId":44,"locked":true}]"#) == .answerAck(questionId: 44))
    #expect(
      try decode(#"["questionEnd",{"correctIndex":1,"distribution":[0,3,1,0]}]"#)
        == .questionEnd(Reveal(correctIndex: 1, distribution: [0, 3, 1, 0])))
    #expect(
      try decode(
        #"["personalResult",{"correct":true,"points":874,"totalScore":1650,"rank":2,"answered":true,"chosenIndex":1}]"#)
        == .personalResult(
          AnswerResult(correct: true, points: 874, totalScore: 1650, rank: 2, answered: true, chosenIndex: 1)))
    #expect(
      try decode(#"["personalRank",{"rank":2,"score":1650,"phase":"leaderboard"}]"#)
        == .personalRank(RankUpdate(rank: 2, score: 1650, phase: .leaderboard)))
    #expect(try decode(#"["playerCount",{"count":9}]"#) == .playerCount(9))
    #expect(try decode(#"["stateChange",{"state":"LOBBY"}]"#) == .stateChange(.lobby))
    #expect(try decode(#"["resumeFailed",{}]"#) == .resumeFailed)
  }

  @Test func decodesTheEndOfAGame() throws {
    let event = try decode(
      #"""
      ["gameOver",{"podium":[{"rank":1,"nickname":"Ada","score":3100},{"rank":2,"nickname":"Robin","score":2900}],
       "standings":[{"rank":1,"nickname":"Ada","score":3100},{"rank":2,"nickname":"Robin","score":2900}]}]
      """#)
    let placings = [Placing(rank: 1, nickname: "Ada", score: 3100), Placing(rank: 2, nickname: "Robin", score: 2900)]
    #expect(event == .gameOver(GameOver(podium: placings, standings: placings)))
  }

  @Test func decodesTheHostsNotices() throws {
    #expect(
      try decode(#"["joinError",{"code":"WRONG_PIN","message":"WRONG PIN — CHECK THE HOST'S SCREEN"}]"#)
        == .joinError(Notice(code: "WRONG_PIN", message: "WRONG PIN — CHECK THE HOST'S SCREEN")))
    #expect(
      try decode(#"["kicked",{"message":"REMOVED BY THE HOST"}]"#)
        == .kicked(Notice(code: nil, message: "REMOVED BY THE HOST")))
  }

  /// A newer host may send events this build doesn't know. They're dropped,
  /// never an error.
  @Test func ignoresEventsItDoesntKnow() throws {
    #expect(try decode(#"["playerList",[{"nickname":"Ada"}]]"#) == .ignored("playerList"))
  }

  /// Hosting encodes what playing decodes: every event must survive the trip.
  @Test func roundTripsEveryEventAHostSends() throws {
    let question = Question(
      questionId: 1, index: 0, qNum: 1, total: 3, text: "Q?", options: ["a", "b", "c", "d"],
      category: "SCIENCE", timeLimit: 20, elapsedMs: 0)
    let result = AnswerResult(correct: true, points: 750, totalScore: 750, rank: 1, answered: true, chosenIndex: 1)
    let snapshot = PlayerSnapshot(
      token: "t", nickname: "Robin", state: .questionActive, score: 0, rank: 1, playerCount: 2, eligibleFrom: 0,
      question: question, lockedIndex: nil, lastResult: nil, podium: nil)
    let events: [ServerEvent] = [
      .joined(snapshot), .resumed(snapshot), .resumeFailed, .playerCount(3), .stateChange(.lobby),
      .joinError(Notice(code: "WRONG_PIN", message: "nope")), .kicked(Notice(code: nil, message: "bye")),
      .questionStart(question), .answerAck(questionId: 1), .questionEnd(Reveal(correctIndex: 1, distribution: [0, 2, 0, 0])),
      .personalResult(result), .personalRank(RankUpdate(rank: 1, score: 750, phase: .leaderboard)),
      .leaderboard(Leaderboard(standings: [.init(rank: 1, nickname: "Robin", score: 750, delta: nil)], afterQuestion: 1, totalQuestions: 3, remaining: 2)),
      .answeredCount(AnsweredCount(answered: 1, total: 2)),
      .gameOver(GameOver(podium: [Placing(rank: 1, nickname: "Robin", score: 750)], standings: [])),
    ]
    for event in events {
      #expect(try JSONDecoder().decode(ServerEvent.self, from: JSONEncoder().encode(event)) == event)
    }
  }

  /// What a host accepts from the network — including the Node client's shapes.
  @Test func decodesWhatPlayersSend() throws {
    let decode = { (json: String) in try JSONDecoder().decode(ClientEvent.self, from: Data(json.utf8)) }
    #expect(try decode(#"["join",{"pin":"4821","nickname":"Robin"}]"#) == .join(pin: "4821", nickname: "Robin"))
    #expect(try decode(#"["join",{"pin":4821,"nickname":"Robin"}]"#) == .join(pin: "4821", nickname: "Robin"))
    #expect(try decode(#"["submitAnswer",{"questionId":2,"optionIndex":3}]"#) == .submitAnswer(questionId: 2, optionIndex: 3))
    #expect(throws: DecodingError.self) { try decode(#"["host:start"]"#) }
    #expect(throws: DecodingError.self) { try decode(#"["submitAnswer",{"questionId":"x","optionIndex":null}]"#) }
    #expect(throws: DecodingError.self) { try decode(#"["join",null]"#) }
  }

  @Test(arguments: [
    (ClientEvent.join(pin: "4821", nickname: "Robin"), #"["join",{"nickname":"Robin","pin":"4821"}]"#),
    (.resume(token: "9f2c1a"), #"["resume",{"token":"9f2c1a"}]"#),
    (.submitAnswer(questionId: 44, optionIndex: 1), #"["submitAnswer",{"optionIndex":1,"questionId":44}]"#),
  ])
  func encodesWhatTheServerExpects(event: ClientEvent, json: String) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    #expect(String(decoding: try encoder.encode(event), as: UTF8.self) == json)
  }
}

@Suite struct GameServerTests {
  @Test(arguments: [
    ("192.168.1.20", "http://192.168.1.20:3000", "192.168.1.20:3000"),
    ("  10.0.0.8:4000 ", "http://10.0.0.8:4000", "10.0.0.8:4000"),
    ("http://172.16.4.2:3000", "http://172.16.4.2:3000", "172.16.4.2:3000"),
    ("http://Den-Mac.local:3000/play?pin=1", "http://den-mac.local:3000", "den-mac.local:3000"),
    ("https://trivia.home.arpa", "https://trivia.home.arpa", "trivia.home.arpa"),
    ("den-mac", "http://den-mac:3000", "den-mac:3000"),
    ("localhost:3000", "http://localhost:3000", "localhost:3000"),
  ])
  func parsesLocalAddresses(input: String, url: String, name: String) throws {
    let server = try #require(GameServer(address: input))
    #expect(server.url.absoluteString == url)
    #expect(server.name == name)
  }

  @Test(arguments: ["[fd12:3456::1]:3000", "[fe80::1]:3000", "[::1]:3000"])
  func acceptsLocalIPv6(input: String) {
    #expect(GameServer(address: input) != nil)
  }

  @Test(arguments: ["", "   ", "ftp://files.local", "http://", "http://:3000"])
  func rejectsWhatIsntAServer(input: String) {
    #expect(GameServer(address: input) == nil)
  }

  /// A join link on a wall shouldn't be able to send phones to the internet.
  @Test(arguments: [
    "8.8.8.8", "http://203.0.113.5:3000", "172.32.0.1", "11.0.0.1",
    "https://example.com", "http://trivia.example.com:3000", "[2001:db8::1]:3000",
  ])
  func rejectsServersBeyondTheLocalNetwork(input: String) {
    #expect(GameServer(address: input) == nil)
  }

  @Test func roundTripsThroughSettings() throws {
    let server = try #require(GameServer(address: "192.168.1.20", name: "FRIDAY QUIZ"))
    let decoded = try JSONDecoder().decode(GameServer.self, from: JSONEncoder().encode(server))
    #expect(decoded == server)
  }

  @Test func refusesAStoredServerThatIsntLocal() {
    let json = #"{"name":"Elsewhere","url":"https:\/\/example.com"}"#
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(GameServer.self, from: Data(json.utf8)) }
  }
}
