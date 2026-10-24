import Foundation

/// A report to the developer: what was objectionable, where, and why. It goes
/// as an email the person sends from their own Mail (`ReportSheet`), so the
/// app itself sends nothing anywhere.
nonisolated struct Report: Identifiable, Equatable, Sendable {
  enum Subject: Equatable, Sendable {
    case question(text: String, options: [String], category: String?)
    case player(nickname: String)
    /// A game's host, by the game's name.
    case host(gameName: String)
    /// Anything else, from the Safety screen.
    case problem
  }

  enum Reason: String, CaseIterable, Identifiable, Sendable {
    case hateful, sexual, violent, harassment, spam, other

    var id: String { rawValue }

    var title: LocalizedStringResource {
      switch self {
      case .hateful: "Hateful or discriminatory"
      case .sexual: "Sexual or explicit"
      case .violent: "Violent or threatening"
      case .harassment: "Harassment or bullying"
      case .spam: "Spam or misleading"
      case .other: "Something else"
      }
    }
  }

  let id = UUID()
  let subject: Subject
  /// The game it happened in, by its name.
  let gameName: String?
  /// Whether the person reporting was hosting.
  let isHost: Bool
  /// What a block did, when the report comes with one.
  let blocked: LocalizedStringResource?
  var reason: Reason = .hateful
  var note = ""

  init(_ subject: Subject, gameName: String?, isHost: Bool, blocked: LocalizedStringResource? = nil) {
    self.subject = subject
    self.gameName = gameName
    self.isHost = isHost
    self.blocked = blocked
  }

  static func == (lhs: Report, rhs: Report) -> Bool {
    lhs.id == rhs.id && lhs.reason == rhs.reason && lhs.note == rhs.note
  }

  /// "a question", "a player's name": what's reported, for the sheet's title.
  var kind: LocalizedStringResource {
    switch subject {
    case .question: "Question"
    case .player: "Player"
    case .host: "Game"
    case .problem: "Problem"
    }
  }

  /// What's reported, as it was on screen.
  var content: String {
    switch subject {
    case .question(let text, let options, _):
      let answers = zip(["A", "B", "C", "D"], options).map { "\($0): \($1)" }
      return ([text] + answers).joined(separator: "\n")
    case .player(let nickname): return nickname
    case .host(let gameName): return gameName
    case .problem: return ""
    }
  }

  // MARK: - The email

  /// In English whatever the phone's language: it's read by the developer.
  var mailSubject: String {
    switch subject {
    case .question: "Local Trivia report: question"
    case .player: "Local Trivia report: player"
    case .host: "Local Trivia report: game host"
    case .problem: "Local Trivia report"
    }
  }

  func mailBody(now: Date = .now) -> String {
    var lines = ["Local Trivia report", ""]
    switch subject {
    case .question(_, _, let category):
      lines.append("Reported: a question\(category.map { " (\($0))" } ?? "")")
    case .player: lines.append("Reported: a player's name")
    case .host: lines.append("Reported: a game and its host")
    case .problem: lines.append("Reported: a problem")
    }
    if !content.isEmpty {
      lines.append("Content:")
      lines.append(contentsOf: content.split(separator: "\n").map { "  \($0)" })
    }
    if let gameName { lines.append("Game: \(gameName)") }
    lines.append("Reported by: \(isHost ? "the host" : "a player")")
    lines.append("Reason: \(Self.english(reason.title))")
    if let blocked { lines.append("Blocked: \(Self.english(blocked))") }
    let note = note.trimmingCharacters(in: .whitespacesAndNewlines)
    if !note.isEmpty { lines.append("Details: \(note)") }
    lines.append("")
    lines.append("Sent: \(now.formatted(.iso8601))")
    lines.append("App: \(Self.appVersion), \(ProcessInfo.processInfo.operatingSystemVersionString)")
    return lines.joined(separator: "\n")
  }

  /// The same email, for a mail app other than Apple's: `mailto:`.
  var mailURL: URL? {
    var parts = URLComponents()
    parts.scheme = "mailto"
    parts.path = Safety.reportAddress
    parts.queryItems = [URLQueryItem(name: "subject", value: mailSubject), URLQueryItem(name: "body", value: mailBody())]
    return parts.url
  }

  private static func english(_ text: LocalizedStringResource) -> String {
    var text = text
    text.locale = Locale(identifier: "en")
    return String(localized: text)
  }

  private static var appVersion: String {
    let info = Bundle.main.infoDictionary
    let version = info?["CFBundleShortVersionString"] as? String ?? "?"
    let build = info?["CFBundleVersion"] as? String ?? "?"
    return "\(version) (\(build))"
  }
}
