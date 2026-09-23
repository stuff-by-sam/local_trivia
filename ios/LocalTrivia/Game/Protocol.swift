import Foundation

// The events a hosting phone and its players exchange. Their shapes mirror the
// payloads in server/gameSession.js, which `HostedGame` ports, so the Node test
// bots can play against a phone; field names match that JSON exactly, so
// decoding needs no key mapping.
//
// Both directions are Codable: the app encodes these when it hosts (see
// Hosting/) and decodes them as a player. One definition, so a host and its
// players can't drift apart on the wire.

nonisolated enum ServerState: String, Codable, Sendable {
  case lobby = "LOBBY"
  case questionActive = "QUESTION_ACTIVE"
  case reveal = "REVEAL"
  case leaderboard = "LEADERBOARD"
  case podium = "PODIUM"
}

/// `questionStart`, and the `question` inside a snapshot.
nonisolated struct Question: Codable, Equatable, Sendable, Identifiable {
  let questionId: Int
  /// Zero-based position in the running order — compared against a late
  /// joiner's `eligibleFrom`.
  let index: Int
  let qNum: Int
  let total: Int
  let text: String
  let options: [String]
  let category: String?
  /// Seconds.
  let timeLimit: Double
  /// How far into the question the server was when it sent this. Zero for a
  /// live `questionStart`; non-zero when resuming mid-question.
  let elapsedMs: Double?

  var id: Int { questionId }
}

/// `personalResult`, and `lastResult` inside a snapshot.
nonisolated struct AnswerResult: Codable, Equatable, Sendable {
  let correct: Bool
  let points: Int
  let totalScore: Int
  let rank: Int?
  let answered: Bool
  /// -1 when the player didn't answer.
  let chosenIndex: Int
}

/// `joined` / `resumed`: everything a (re)connecting phone needs to redraw.
nonisolated struct PlayerSnapshot: Codable, Equatable, Sendable {
  let token: String
  let nickname: String
  let state: ServerState
  let score: Int
  let rank: Int?
  let playerCount: Int?
  let eligibleFrom: Int?
  let question: Question?
  let lockedIndex: Int?
  let lastResult: AnswerResult?
  /// Only in the podium state: the final top three, for a phone that missed
  /// `gameOver` because it (re)connected afterwards.
  let podium: [Placing]?
}

nonisolated struct Reveal: Codable, Equatable, Sendable {
  let correctIndex: Int
  let distribution: [Int]
}

nonisolated struct RankUpdate: Codable, Equatable, Sendable {
  enum Phase: String, Codable, Sendable {
    case leaderboard
    case podium
  }
  let rank: Int?
  let score: Int
  let phase: Phase
}

nonisolated struct Placing: Codable, Equatable, Hashable, Sendable {
  let rank: Int
  let nickname: String
  let score: Int
}

nonisolated struct GameOver: Codable, Equatable, Sendable {
  let podium: [Placing]
  var standings: [Placing]? = nil
}

/// `leaderboard`. The laptop server sends it only to the TV; a phone-hosted
/// game has no TV, so it goes to every player.
nonisolated struct Leaderboard: Codable, Equatable, Sendable {
  nonisolated struct Row: Codable, Equatable, Hashable, Sendable {
    let rank: Int
    let nickname: String
    let score: Int
    /// Places gained since the last standings; nil on the first.
    let delta: Int?
  }
  let standings: [Row]
  let afterQuestion: Int
  let totalQuestions: Int
  let remaining: Int
}

/// `answeredCount` — how much of the room has locked in.
nonisolated struct AnsweredCount: Codable, Equatable, Sendable {
  let answered: Int
  let total: Int
}

nonisolated struct Notice: Codable, Equatable, Sendable {
  let code: String?
  let message: String?
}

/// Every event a host sends a player, decoded straight from the Socket.IO
/// array `["name", payload]` in one pass — no intermediate dictionary.
nonisolated enum ServerEvent: Codable, Equatable, Sendable {
  case joined(PlayerSnapshot)
  case joinError(Notice)
  case resumed(PlayerSnapshot)
  case resumeFailed
  case kicked(Notice)
  case playerCount(Int)
  case stateChange(ServerState)
  case questionStart(Question)
  case answerAck(questionId: Int)
  case questionEnd(Reveal)
  case personalResult(AnswerResult)
  case personalRank(RankUpdate)
  case gameOver(GameOver)
  case leaderboard(Leaderboard)
  case answeredCount(AnsweredCount)
  /// An event this app doesn't know — from a newer host, say. Dropped, not fatal.
  case ignored(String)

  private struct Count: Codable { let count: Int }
  private struct State: Codable { let state: ServerState }
  private struct Ack: Codable {
    let questionId: Int
    var locked: Bool? = true
  }
  private struct Empty: Codable {}

  init(from decoder: any Decoder) throws {
    var body = try decoder.unkeyedContainer()
    let name = try body.decode(String.self)
    switch name {
    case "joined": self = .joined(try body.decode(PlayerSnapshot.self))
    case "joinError": self = .joinError(try body.decode(Notice.self))
    case "resumed": self = .resumed(try body.decode(PlayerSnapshot.self))
    case "resumeFailed": self = .resumeFailed
    case "kicked": self = .kicked(try body.decode(Notice.self))
    case "playerCount": self = .playerCount(try body.decode(Count.self).count)
    case "stateChange": self = .stateChange(try body.decode(State.self).state)
    case "questionStart": self = .questionStart(try body.decode(Question.self))
    case "answerAck": self = .answerAck(questionId: try body.decode(Ack.self).questionId)
    case "questionEnd": self = .questionEnd(try body.decode(Reveal.self))
    case "personalResult": self = .personalResult(try body.decode(AnswerResult.self))
    case "personalRank": self = .personalRank(try body.decode(RankUpdate.self))
    case "gameOver": self = .gameOver(try body.decode(GameOver.self))
    case "leaderboard": self = .leaderboard(try body.decode(Leaderboard.self))
    case "answeredCount": self = .answeredCount(try body.decode(AnsweredCount.self))
    default: self = .ignored(name)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var body = encoder.unkeyedContainer()
    switch self {
    case .joined(let snapshot): try body.encode("joined"); try body.encode(snapshot)
    case .joinError(let notice): try body.encode("joinError"); try body.encode(notice)
    case .resumed(let snapshot): try body.encode("resumed"); try body.encode(snapshot)
    case .resumeFailed: try body.encode("resumeFailed"); try body.encode(Empty())
    case .kicked(let notice): try body.encode("kicked"); try body.encode(notice)
    case .playerCount(let count): try body.encode("playerCount"); try body.encode(Count(count: count))
    case .stateChange(let state): try body.encode("stateChange"); try body.encode(State(state: state))
    case .questionStart(let question): try body.encode("questionStart"); try body.encode(question)
    case .answerAck(let questionId): try body.encode("answerAck"); try body.encode(Ack(questionId: questionId))
    case .questionEnd(let reveal): try body.encode("questionEnd"); try body.encode(reveal)
    case .personalResult(let result): try body.encode("personalResult"); try body.encode(result)
    case .personalRank(let update): try body.encode("personalRank"); try body.encode(update)
    case .gameOver(let result): try body.encode("gameOver"); try body.encode(result)
    case .leaderboard(let board): try body.encode("leaderboard"); try body.encode(board)
    case .answeredCount(let count): try body.encode("answeredCount"); try body.encode(count)
    case .ignored(let name): try body.encode(name); try body.encode(Empty())
    }
  }
}

/// Everything a player can send. Encodes as the Socket.IO array `["name", payload]`.
nonisolated enum ClientEvent: Codable, Equatable, Sendable {
  case join(pin: String, nickname: String)
  case resume(token: String)
  case submitAnswer(questionId: Int, optionIndex: Int)

  private struct Join: Codable { let pin: LenientString; let nickname: String }
  private struct Resume: Codable { let token: String }
  private struct Answer: Codable { let questionId: Int; let optionIndex: Int }

  /// Hosting decodes these from whoever connects, so anything malformed is
  /// an error to drop — never a crash, never a guess. (The Node server
  /// coerces the PIN with `String(pin)`; a number is accepted here too.)
  init(from decoder: any Decoder) throws {
    var body = try decoder.unkeyedContainer()
    let name = try body.decode(String.self)
    switch name {
    case "join":
      let join = try body.decode(Join.self)
      self = .join(pin: join.pin.value, nickname: join.nickname)
    case "resume":
      self = .resume(token: try body.decode(Resume.self).token)
    case "submitAnswer":
      let answer = try body.decode(Answer.self)
      self = .submitAnswer(questionId: answer.questionId, optionIndex: answer.optionIndex)
    default:
      throw DecodingError.dataCorruptedError(in: body, debugDescription: "Unknown client event")
    }
  }

  func encode(to encoder: any Encoder) throws {
    var body = encoder.unkeyedContainer()
    switch self {
    case .join(let pin, let nickname):
      try body.encode("join")
      try body.encode(Join(pin: LenientString(pin), nickname: nickname))
    case .resume(let token):
      try body.encode("resume")
      try body.encode(Resume(token: token))
    case .submitAnswer(let questionId, let optionIndex):
      try body.encode("submitAnswer")
      try body.encode(Answer(questionId: questionId, optionIndex: optionIndex))
    }
  }
}

/// A string on the way out; a string or an integer on the way in.
nonisolated struct LenientString: Codable, Equatable, Sendable {
  let value: String

  init(_ value: String) { self.value = value }

  init(from decoder: any Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let number = try? container.decode(Int.self) {
      value = String(number)
    } else {
      value = try container.decode(String.self)
    }
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(value)
  }
}
