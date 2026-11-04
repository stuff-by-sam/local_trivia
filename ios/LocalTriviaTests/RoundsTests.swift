import Foundation
import Testing

@testable import LocalTrivia

/// The host's rounds: more than one kept, one played at a time, any of them
/// sent to another phone as a CSV — and the starter rounds that come with
/// the app.
struct RoundsTests {
  private func question(_ text: String, _ answer: String = "Jupiter") -> HostQuestion {
    HostQuestion(text: text, options: [answer, "Mars", "Venus", "Earth"], correct: 0, category: "SPACE")
  }

  /// A round saved before rounds could be kept is the one being played.
  @Test func readsARoundSavedBeforeRoundsWereKept() throws {
    let url = URL.temporaryDirectory.appending(path: "round-\(UUID().uuidString).json")
    let old = #"{"gameName":"Friday Quiz","questions":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","text":"Largest planet?","options":["Jupiter","Mars","Venus","Earth"],"correct":0,"category":"SPACE","isIncluded":true}],"rules":{"maxPoints":1000,"timeLimit":20,"minCorrectFraction":0,"wrongAnswerPoints":0,"shuffle":true,"autoAdvance":false}}"#
    try Data(old.utf8).write(to: url)
    let library = HostLibrary(fileURL: url) { _, _ in }
    #expect(library.gameName == "Friday Quiz")
    #expect(library.questions.map(\.text) == ["Largest planet?"])
    #expect(library.roundName == "My Round")
    #expect(library.shelf.isEmpty)
  }

  /// Rounds, and which is being played, are there at the next launch.
  @Test func keepsEveryRoundBetweenLaunches() async throws {
    let url = URL.temporaryDirectory.appending(path: "round-\(UUID().uuidString).json")
    let library = HostLibrary(fileURL: url) { data, url in try data.write(to: url) }
    library.roundName = "Space"
    library.questions = [question("Largest planet?")]
    library.startRound(named: "Movies")
    library.questions = [question("Who directed Jaws?", "Steven Spielberg")]
    library.flush(waiting: true)

    let relaunched = HostLibrary(fileURL: url) { _, _ in }
    #expect(relaunched.roundName == "Movies")
    #expect(relaunched.rounds.map(\.name) == ["Movies", "Space"])
    #expect(relaunched.shelf.first?.questions.map(\.text) == ["Largest planet?"])
  }

  /// Playing another round puts the one being played on the shelf, first.
  @Test func playingAnotherRoundKeepsTheOneItReplaces() throws {
    let library = HostLibrary(fileURL: nil)
    library.roundName = "Space"
    library.questions = [question("Largest planet?")]
    library.startRound(named: "Movies")
    library.questions = [question("Who directed Jaws?", "Steven Spielberg")]
    let space = try #require(library.shelf.first)

    library.open(space.id)
    #expect(library.roundName == "Space")
    #expect(library.questions.map(\.text) == ["Largest planet?"])
    #expect(library.shelf.map(\.name) == ["Movies"])
  }

  /// An empty round isn't worth keeping when another takes its place.
  @Test func anEmptyRoundGivesWay() {
    let library = HostLibrary(fileURL: nil)
    library.startRound(named: "Empty")
    library.receive(SavedRound(name: "Starter", questions: [question("Largest planet?")]))
    #expect(library.rounds.map(\.name) == ["Starter"])
  }

  /// Deleting a round can be taken back, the one being played too: until
  /// then, the most recent on the shelf is played.
  @Test func deletedRoundsComeBack() throws {
    let library = HostLibrary(fileURL: nil)
    library.roundName = "One"
    library.questions = [question("Q1?")]
    library.startRound(named: "Two")
    library.questions = [question("Q2?", "Saturn")]
    library.startRound(named: "Three")
    library.questions = [question("Q3?", "Uranus")]
    #expect(library.rounds.map(\.name) == ["Three", "Two", "One"])

    let oldest = try #require(library.shelf.last)
    let shelved = try #require(library.remove(oldest.id))
    #expect(library.rounds.map(\.name) == ["Three", "Two"])
    library.undo(shelved)
    #expect(library.rounds.map(\.name) == ["Three", "Two", "One"])

    let playing = try #require(library.remove(library.roundID))
    #expect(library.roundName == "Two")
    library.undo(playing)
    #expect(library.roundName == "Three")
    #expect(library.rounds.map(\.name) == ["Three", "Two", "One"])
  }

  @Test func renamesAndDuplicatesRounds() throws {
    let library = HostLibrary(fileURL: nil)
    library.roundName = "Space"
    library.questions = [question("Largest planet?")]
    library.rename(library.roundID, to: "  Outer Space ")
    #expect(library.roundName == "Outer Space")
    library.rename(library.roundID, to: "   ")
    #expect(library.roundName == "Outer Space", "a blank name isn't a name")

    let copy = try #require(library.duplicate(library.roundID))
    #expect(copy.name == "Outer Space Copy")
    #expect(copy.questions.map(\.text) == library.questions.map(\.text))
    #expect(Set(copy.questions.map(\.id)).isDisjoint(with: library.questions.map(\.id)), "a copy's questions are its own")
  }

  // MARK: - Sharing

  /// A round sent as a CSV comes back as it was: text, answers, key,
  /// category and time — commas, quotes and all.
  @Test func aSharedRoundReadsBackAsItWas() {
    var timed = HostQuestion(text: "Who said \"Hello, world\"?", options: ["A, B", "C", " D", "E\nF"], correct: 2, category: "TECH")
    timed.timeLimit = 45
    let round = [question("Largest planet?"), timed]
    let read = CSVImport.parse(CSVExport.text(for: round))
    #expect(read.errors.isEmpty)
    #expect(read.questions.map(\.text) == round.map(\.text))
    #expect(read.questions.map(\.correct) == [0, 2])
    #expect(read.questions.map(\.category) == ["SPACE", "TECH"])
    #expect(read.questions.map(\.timeLimit) == [nil, 45])
    #expect(read.questions[1].options == ["A, B", "C", "D", "E\nF"])
  }

  /// A round arrives named after its file, and iOS's copy in the inbox goes.
  @Test func receivesARoundFromAFile() throws {
    let url = URL.temporaryDirectory.appending(path: "Movie_Night.csv")
    try Data(CSVExport.text(for: [question("Largest planet?")]).utf8).write(to: url)
    let round = try #require(SavedRound.received(from: url))
    #expect(round.name == "Movie Night")
    #expect(round.questions.count == 1)

    let empty = URL.temporaryDirectory.appending(path: "Empty.csv")
    try Data("question,option_a\n".utf8).write(to: empty)
    #expect(SavedRound.received(from: empty) == nil)
  }

  @Test func namesTheFileAfterTheRound() {
    #expect(RoundFile(round: SavedRound(name: "Movies: 90s/00s", questions: [])).fileName == "Movies 90s 00s.csv")
    #expect(RoundFile(round: SavedRound(name: "  ", questions: [])).fileName == "Trivia Round.csv")
  }

  // MARK: - Starter rounds

  /// Every starter round is in the app, reads without a problem, and can be
  /// played as it is: four answers, one marked, nothing the filter keeps out.
  @Test func everyStarterRoundIsReadyToPlay() throws {
    var texts: [String] = []
    for starter in StarterRound.allCases {
      let questions = try #require(starter.questions, "\(starter.rawValue) isn't in the app")
      #expect(questions.count >= 25, "\(starter.rawValue) has \(questions.count)")
      for question in questions {
        #expect(question.problem == nil, "\(starter.rawValue): \(question.text) — \(String(describing: question.problem))")
        #expect(question.text.count <= 120, "\(starter.rawValue): \(question.text)")
      }
      // No letter is the answer much more than its share.
      let keys = Dictionary(grouping: questions, by: \.correct).mapValues(\.count)
      #expect(keys.values.allSatisfy { Double($0) <= Double(questions.count) * 0.4 }, "\(starter.rawValue): \(keys)")
      texts += questions.map(\.text)
    }
    #expect(Set(texts).count == texts.count, "a question appears twice across the starter rounds")
  }
}
