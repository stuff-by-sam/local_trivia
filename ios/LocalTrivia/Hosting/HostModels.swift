import Foundation
import Observation
import OSLog

/// A question the host wrote or imported. Same shape and limits as the web
/// admin console's (`validate` in server/questions.js).
nonisolated struct HostQuestion: Codable, Identifiable, Hashable, Sendable {
  var id = UUID()
  var text: String
  /// Exactly four, in A–D order.
  var options: [String]
  /// 0...3.
  var correct: Int
  var category: String = "GENERAL"
  /// Seconds; nil plays for the round's default.
  var timeLimit: Int?
  var isIncluded = true

  static let timeLimits = 5...600

  enum Problem: Equatable, Sendable {
    case missingText, missingOption, noCorrectAnswer, timeOutOfRange
  }

  /// A new question has no right answer until the host picks one: a
  /// default of A would be wrong three times in four, in front of the room.
  static func blank() -> HostQuestion {
    HostQuestion(text: "", options: ["", "", "", ""], correct: -1)
  }

  /// Nothing typed and no answer picked: a new question that was never started.
  var isUntouched: Bool {
    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      && options.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      && !(0...3).contains(correct)
  }

  var problem: Problem? {
    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return .missingText }
    if options.count != 4 || options.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
      return .missingOption
    }
    if !(0...3).contains(correct) { return .noCorrectAnswer }
    if let timeLimit, !Self.timeLimits.contains(timeLimit) { return .timeOutOfRange }
    return nil
  }

  var isPlayable: Bool { isIncluded && problem == nil }

  /// Trimmed, with the category upper-cased — as the server stores it.
  func normalized() -> HostQuestion {
    var copy = self
    copy.text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.options = options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let category = category.trimmingCharacters(in: .whitespacesAndNewlines)
    copy.category = category.isEmpty ? "GENERAL" : category.uppercased()
    return copy
  }
}

/// How a round scores and flows. Ranges mirror `saveSettings` in
/// server/questions.js, so a phone-hosted round and a laptop round agree.
nonisolated struct HostRules: Codable, Hashable, Sendable {
  /// What an instant correct answer earns.
  var maxPoints = 1000
  /// Seconds per question, unless a question sets its own.
  var timeLimit = 20
  /// The share of `maxPoints` a correct answer earns even at the buzzer.
  var minCorrectFraction = 0.0
  /// A consolation for wrong answers (and no answer).
  var wrongAnswerPoints = 0
  var shuffle = true
  /// Reveal → standings → next question, five seconds apart, hands-free.
  var autoAdvance = false

  static let maxPointsRange = 10...100_000
  static let timeLimitRange = 5...600
  static let minCorrectRange = 0.0...0.9
  static let wrongPointsRange = 0...100_000

  func clamped() -> HostRules {
    var rules = self
    rules.maxPoints = maxPoints.clamped(to: Self.maxPointsRange)
    rules.timeLimit = timeLimit.clamped(to: Self.timeLimitRange)
    rules.minCorrectFraction = (minCorrectFraction.clamped(to: Self.minCorrectRange) * 100).rounded() / 100
    rules.wrongAnswerPoints = wrongAnswerPoints.clamped(to: Self.wrongPointsRange)
    return rules
  }
}

/// The points formula — public/shared/scoring.js, line for line. A correct
/// answer earns between `minCorrectFraction` and all of `maxPoints`, falling
/// linearly with time taken; a wrong answer (or none) earns `wrongAnswerPoints`.
nonisolated enum Scoring {
  static func points(isCorrect: Bool, elapsed: Double, timeLimit: Double, rules: HostRules) -> Int {
    guard isCorrect else { return rules.wrongAnswerPoints }
    let remaining = max(0, min(timeLimit, timeLimit - elapsed))
    let fraction = rules.minCorrectFraction + (1 - rules.minCorrectFraction) * (remaining / timeLimit)
    return Int((Double(rules.maxPoints) * fraction).rounded(.toNearestOrAwayFromZero))
  }
}

extension Comparable {
  nonisolated func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

/// The host's round — name, questions and rules — kept on this phone between
/// games. It holds the answer key, so the file is encrypted whenever the phone
/// is locked (`.completeFileProtection`).
@Observable
final class HostLibrary {
  var gameName: String { didSet { save() } }
  var questions: [HostQuestion] { didSet { save() } }
  var rules: HostRules { didSet { save() } }

  /// What a game started now would play, in order.
  var playable: [HostQuestion] { questions.filter(\.isPlayable) }

  static let defaultName = "TRIVIA NIGHT"
  static let nameLimit = 28
  /// A Bonjour name is one DNS label, 63 bytes. Past that, hosting fails.
  static let nameByteLimit = 63

  @ObservationIgnored private let fileURL: URL?
  @ObservationIgnored private var isLoading = false
  /// Edits since the last write.
  @ObservationIgnored private var isDirty = false
  @ObservationIgnored private var pendingSave: Task<Void, Never>?
  @ObservationIgnored private let write: @Sendable (Data, URL) throws -> Void
  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "hosting")

  /// How long edits settle before they're written: typing a name or
  /// dragging a slider is one write, not one per keystroke or step.
  static let saveDelay: Duration = .milliseconds(500)

  /// Writes happen off the main thread, one at a time, in order.
  private static let writes = DispatchQueue(label: "com.stuffbysam.localtrivia.round", qos: .utility)

  private struct Stored: Codable {
    var gameName: String
    var questions: [HostQuestion]
    var rules: HostRules
  }

  /// `fileURL: nil` keeps everything in memory (tests, previews).
  init(fileURL: URL? = HostLibrary.defaultFileURL, write: @escaping @Sendable (Data, URL) throws -> Void = HostLibrary.writeFile) {
    self.fileURL = fileURL
    self.write = write
    let stored = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
    isLoading = true
    gameName = stored?.gameName ?? Self.defaultName
    questions = stored?.questions ?? []
    rules = stored?.rules.clamped() ?? HostRules()
    isLoading = false
  }

  static var defaultFileURL: URL? {
    URL.applicationSupportDirectory.appending(path: "Hosting", directoryHint: .isDirectory).appending(path: "round.json")
  }

  /// What the game is advertised as: the name players see in their list.
  var advertisedName: String {
    let trimmed = gameName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return Self.defaultName }
    // 28 emoji are well past 63 bytes; drop whole characters until it fits.
    var name = String(trimmed.prefix(Self.nameLimit)).uppercased()
    while name.utf8.count > Self.nameByteLimit { name.removeLast() }
    return name
  }

  func upsert(_ question: HostQuestion) {
    let clean = question.normalized()
    if let index = questions.firstIndex(where: { $0.id == clean.id }) {
      questions[index] = clean
    } else {
      questions.append(clean)
    }
  }

  /// Removes the questions at `offsets` and returns them with where they were,
  /// so they can be put back (`reinsert`).
  @discardableResult
  func delete(at offsets: IndexSet) -> [(offset: Int, element: HostQuestion)] {
    let removed = questions.enumerated().filter { offsets.contains($0.offset) }.map { (offset: $0.offset, element: $0.element) }
    questions = questions.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
    return removed
  }

  /// Puts deleted questions back where they were, as near as the list now allows.
  func reinsert(_ removed: [(offset: Int, element: HostQuestion)]) {
    var restored = questions
    for (offset, question) in removed.sorted(by: { $0.offset < $1.offset }) where !restored.contains(where: { $0.id == question.id }) {
      restored.insert(question, at: min(offset, restored.count))
    }
    questions = restored
  }

  /// List reordering semantics: `destination` is an index in the list as it
  /// was before the move.
  func move(from source: IndexSet, to destination: Int) {
    let moving = source.map { questions[$0] }
    var remaining = questions.enumerated().filter { !source.contains($0.offset) }.map(\.element)
    remaining.insert(contentsOf: moving, at: destination - source.count { $0 < destination })
    questions = remaining
  }

  /// Appends what parses; reports what didn't.
  @discardableResult
  func importCSV(_ text: String) -> CSVImport.Result {
    let result = CSVImport.parse(text)
    questions.append(contentsOf: result.questions)
    return result
  }

  /// Schedules a write once the edits settle.
  private func save() {
    guard !isLoading, fileURL != nil else { return }
    isDirty = true
    pendingSave?.cancel()
    pendingSave = Task { [weak self] in
      try? await Task.sleep(for: Self.saveDelay)
      guard !Task.isCancelled else { return }
      self?.flush()
    }
  }

  /// Writes pending edits now — when the setup screen closes, or the app
  /// goes to the background, where a delayed write might never run.
  func flush() {
    pendingSave?.cancel()
    pendingSave = nil
    guard isDirty, let fileURL else { return }
    isDirty = false
    let data: Data
    do {
      data = try JSONEncoder().encode(Stored(gameName: gameName, questions: questions, rules: rules))
    } catch {
      Self.log.error("couldn't encode the round: \(error.localizedDescription, privacy: .public)")
      return
    }
    let write = write
    Self.writes.async {
      do {
        try write(data, fileURL)
      } catch {
        Self.log.error("couldn't save the round: \(error.localizedDescription, privacy: .public)")
      }
    }
  }

  /// The round holds the answer key, so it's encrypted whenever the phone is locked.
  nonisolated static let writeFile: @Sendable (Data, URL) throws -> Void = { data, url in
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic, .completeFileProtection])
  }
}
