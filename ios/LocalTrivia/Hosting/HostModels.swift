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
    /// A word the content filter keeps out of games (`ContentFilter`).
    case objectionable
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
    if !([text, category] + options).allSatisfy({ ContentFilter.allows($0, as: .question) }) { return .objectionable }
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

/// A round of questions kept on this phone: the one being played, or one put
/// by for another night (`HostLibrary.shelf`).
nonisolated struct SavedRound: Codable, Identifiable, Hashable, Sendable {
  var id = UUID()
  var name: String
  var questions: [HostQuestion]
}

/// The host's rounds, the game's name and how it scores, kept on this phone
/// between games. One round is being played (`questions`, `roundName`); the
/// rest are on the shelf, most recently played first, to come back to. It
/// holds answer keys, so the file is encrypted whenever the phone is locked
/// (`.completeFileProtection`).
@Observable
final class HostLibrary {
  var gameName: String { didSet { save() } }
  /// The round being played.
  var questions: [HostQuestion] {
    didSet {
      playable = questions.filter(\.isPlayable)
      save()
    }
  }
  /// What the host calls the round being played.
  var roundName: String { didSet { save() } }
  var rules: HostRules { didSet { save() } }
  /// The rounds put by, most recently played first.
  private(set) var shelf: [SavedRound] { didSet { save() } }
  private(set) var roundID: UUID { didSet { save() } }

  /// What a game started now would play, in order. Worked out when the round
  /// changes, not each time it's asked for: Host a Game asks four times
  /// every time it's drawn, and it's drawn at every keystroke of a name.
  private(set) var playable: [HostQuestion]

  static let defaultName = "Trivia Night"
  /// The default from when names were upper-cased. A round saved with it
  /// takes the new one; a name the host typed stays as it is.
  static let oldDefaultName = "TRIVIA NIGHT"
  static let nameLimit = 28
  /// A Bonjour name is one DNS label, 63 bytes. Past that, hosting fails.
  static let nameByteLimit = 63

  @ObservationIgnored private let fileURL: URL?
  @ObservationIgnored private var isLoading = false
  /// Edits since the last write.
  @ObservationIgnored private var isDirty = false
  @ObservationIgnored private var pendingSave: Task<Void, Never>?
  @ObservationIgnored private let write: @Sendable (Data, URL) throws -> Void
  /// Nonisolated: the write queue logs its failures.
  nonisolated private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "hosting")

  /// How long edits settle before they're written: typing a name or
  /// dragging a slider is one write, not one per keystroke or step.
  static let saveDelay: Duration = .milliseconds(500)

  /// Writes happen off the main thread, one at a time, in order.
  private static let writes = DispatchQueue(label: "com.stuffbysam.localtrivia.round", qos: .utility)

  private struct Stored: Codable {
    var gameName: String
    var questions: [HostQuestion]
    var rules: HostRules
    // Since build 9, which keeps more than one round. Optional, so a file
    // from before reads as its one round; a build from before reads this
    // one's round being played and leaves the shelf be.
    var roundName: String?
    var roundID: UUID?
    var shelf: [SavedRound]?
  }

  /// `fileURL: nil` keeps everything in memory (tests, previews).
  init(fileURL: URL? = HostLibrary.defaultFileURL, write: @escaping @Sendable (Data, URL) throws -> Void = HostLibrary.writeFile) {
    self.fileURL = fileURL
    self.write = write
    let stored = fileURL.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONDecoder().decode(Stored.self, from: $0) }
    isLoading = true
    if let name = stored?.gameName, name != Self.oldDefaultName {
      gameName = name
    } else {
      gameName = Self.defaultName
    }
    let round = stored?.questions ?? []
    questions = round
    playable = round.filter(\.isPlayable)
    rules = stored?.rules.clamped() ?? HostRules()
    roundName = stored?.roundName ?? String(localized: "My Round")
    roundID = stored?.roundID ?? UUID()
    shelf = stored?.shelf ?? []
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
    var name = String(trimmed.prefix(Self.nameLimit))
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

  // MARK: - Rounds

  /// The round being played, as one for the shelf.
  var current: SavedRound {
    SavedRound(id: roundID, name: roundName, questions: questions)
  }

  /// Every round, the one being played first.
  var rounds: [SavedRound] { [current] + shelf }

  /// Plays the round on the shelf called `id`, putting the one being played
  /// by in its place at the front.
  func open(_ id: SavedRound.ID) {
    guard id != roundID, let index = shelf.firstIndex(where: { $0.id == id }) else { return }
    var shelf = shelf
    let next = shelf.remove(at: index)
    if !questions.isEmpty { shelf.insert(current, at: 0) }
    self.shelf = shelf
    play(next)
  }

  /// Plays `round` — a new one, a starter, one sent from another phone —
  /// putting the one being played by. An empty round isn't worth a place on
  /// the shelf, so it gives way.
  func receive(_ round: SavedRound) {
    if !questions.isEmpty { shelf.insert(current, at: 0) }
    play(round)
  }

  /// Puts `round` on the shelf without playing it: one that arrives while a
  /// game is under way.
  func shelve(_ round: SavedRound) {
    shelf.insert(round, at: 0)
  }

  /// Starts an empty round called `name`.
  func startRound(named name: String) {
    receive(SavedRound(name: name, questions: []))
  }

  func rename(_ id: SavedRound.ID, to name: String) {
    let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !name.isEmpty else { return }
    if id == roundID {
      roundName = name
    } else if let index = shelf.firstIndex(where: { $0.id == id }) {
      shelf[index].name = name
    }
  }

  /// A copy of the round called `id`, on the shelf beside it.
  @discardableResult
  func duplicate(_ id: SavedRound.ID) -> SavedRound? {
    guard let original = rounds.first(where: { $0.id == id }) else { return nil }
    let copy = SavedRound(
      name: String(localized: "\(original.name) Copy"),
      questions: original.questions.map { question in
        var copy = question
        copy.id = UUID()
        return copy
      })
    let index = shelf.firstIndex(where: { $0.id == id }).map { $0 + 1 } ?? 0
    shelf.insert(copy, at: index)
    return copy
  }

  /// What deleting a round took away, to put it back (`undo`).
  struct Removal {
    let round: SavedRound
    /// Where it was on the shelf; nil if it was being played.
    let index: Int?
  }

  /// Deletes the round called `id`. The round being played gives way to the
  /// most recent on the shelf, or to an empty one.
  func remove(_ id: SavedRound.ID) -> Removal? {
    if id == roundID {
      let removed = current
      if shelf.isEmpty {
        play(SavedRound(name: String(localized: "My Round"), questions: []))
      } else {
        var shelf = shelf
        let next = shelf.removeFirst()
        self.shelf = shelf
        play(next)
      }
      return Removal(round: removed, index: nil)
    }
    guard let index = shelf.firstIndex(where: { $0.id == id }) else { return nil }
    return Removal(round: shelf.remove(at: index), index: index)
  }

  /// Puts back a round just deleted, where it was.
  func undo(_ removal: Removal) {
    if let index = removal.index {
      shelf.insert(removal.round, at: min(index, shelf.count))
    } else {
      receive(removal.round)
    }
  }

  private func play(_ round: SavedRound) {
    roundID = round.id
    roundName = round.name
    questions = round.questions
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
  /// goes to the background, where a delayed write might never run. Going
  /// to the background, `waiting` holds on until the write is done: the app
  /// can be suspended the moment this returns.
  func flush(waiting: Bool = false) {
    defer { if waiting { Self.writes.sync {} } }
    pendingSave?.cancel()
    pendingSave = nil
    guard isDirty, let fileURL else { return }
    isDirty = false
    let data: Data
    do {
      data = try JSONEncoder().encode(
        Stored(gameName: gameName, questions: questions, rules: rules, roundName: roundName, roundID: roundID, shelf: shelf))
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
