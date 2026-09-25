import Foundation
import Testing

@testable import LocalTrivia

/// The shortcuts in the host's flow: drafted questions, a new question's
/// answer key, and deletes that can be taken back.
struct QuestionDrafterTests {
  private let draft = DraftedQuestion(question: "Which planet is largest?", correctAnswer: "Jupiter", wrongAnswers: ["Mars", "Venus", "Earth"])

  @Test func putsTheRightAnswerOnTheKeyItWasGiven() throws {
    for key in 0..<4 {
      let question = try #require(QuestionDrafter.question(from: draft, category: "SPACE", correctAt: key))
      #expect(question.correct == key)
      #expect(question.options[key] == "Jupiter")
      #expect(Set(question.options) == ["Jupiter", "Mars", "Venus", "Earth"])
      #expect(question.problem == nil)
    }
  }

  @Test func dropsDraftsThatCantBePlayed() {
    let repeated = DraftedQuestion(question: "Largest?", correctAnswer: "Jupiter", wrongAnswers: ["Mars", "jupiter", "Earth"])
    let short = DraftedQuestion(question: "Largest?", correctAnswer: "Jupiter", wrongAnswers: ["Mars", "Earth"])
    let blank = DraftedQuestion(question: "  ", correctAnswer: "Jupiter", wrongAnswers: ["Mars", "Venus", "Earth"])
    let empty = DraftedQuestion(question: "Largest?", correctAnswer: "", wrongAnswers: ["Mars", "Venus", "Earth"])
    for unusable in [repeated, short, blank, empty] {
      #expect(QuestionDrafter.question(from: unusable, category: "SPACE", correctAt: 0) == nil)
    }
    #expect(QuestionDrafter.question(from: draft, category: "SPACE", correctAt: 4) == nil)
  }

  /// From testing: Venus has no moons either, so a player who picks it is
  /// right, and would be marked wrong.
  @Test func keepsADraftOnlyIfTheCheckFindsJustItsAnswer() {
    let moons = HostQuestion(text: "Which planet has no moons?", options: ["Venus", "Mars", "Mercury", "Saturn"], correct: 2)
    #expect(QuestionDrafter.isOnlyRightOption(["Mercury"], of: moons))
    #expect(QuestionDrafter.isOnlyRightOption(["mercury."], of: moons))
    #expect(QuestionDrafter.isOnlyRightOption(["C. Mercury"], of: moons), "copied with its letter")
    #expect(QuestionDrafter.isOnlyRightOption(["C"], of: moons), "the letter alone")
    #expect(!QuestionDrafter.isOnlyRightOption(["C", "B"], of: moons), "two letters")
    #expect(!QuestionDrafter.isOnlyRightOption(["Mercury", "Venus"], of: moons), "two right answers")
    #expect(!QuestionDrafter.isOnlyRightOption(["Venus"], of: moons), "the wrong one marked")
    #expect(!QuestionDrafter.isOnlyRightOption([], of: moons), "none right")
  }

  @Test func namesTheCategoryAfterTheTopic() {
    #expect(QuestionDrafter.category(for: "  90s films ") == "90S FILMS")
    #expect(QuestionDrafter.category(for: "") == "GENERAL")
    #expect(QuestionDrafter.category(for: String(repeating: "a", count: 40)).count == 24)
  }
}

/// Drafting the same topic twice mustn't fill the round with the same
/// questions in new words.
struct DraftRepeatTests {
  private func question(_ text: String, _ answer: String, wrong: [String] = ["W1", "W2", "W3"]) -> HostQuestion {
    HostQuestion(text: text, options: [answer] + wrong, correct: 0)
  }

  private let round = [
    HostQuestion(text: "Which planet is the largest?", options: ["Mars", "Jupiter", "Venus", "Earth"], correct: 1),
    HostQuestion(text: "In which year did the Berlin Wall fall?", options: ["1987", "1988", "1989", "1991"], correct: 2),
  ]

  @Test func dropsTheSameQuestionHoweverItsWritten() {
    let drafts = [question("which planet is the LARGEST", "Saturn"), question("In which year did the Berlin Wall fall ?!", "1990")]
    #expect(QuestionDrafter.dropRepeats(drafts, of: round).isEmpty, "same words, even with another answer")
  }

  @Test func dropsTheSameAnswerToTheSameQuestionInNewWords() {
    let drafts = [
      question("What is the largest planet in the solar system?", "Jupiter"),
      question("When did the Berlin Wall fall?", "1989"),
    ]
    #expect(QuestionDrafter.dropRepeats(drafts, of: round).isEmpty)
  }

  @Test func keepsNewQuestionsThatShareAnAnswerOrAWord() {
    let drafts = [
      // Same answer as the round's largest planet, but it asks something else.
      question("Which planet has the Great Red Spot?", "Jupiter"),
      // Same words, different answer: a different question.
      question("Which planet is the smallest?", "Mercury"),
      question("Which planet is closest to the Sun?", "Mercury"),
    ]
    #expect(QuestionDrafter.dropRepeats(drafts, of: round).map(\.text) == drafts.map(\.text))
  }

  /// Function words only tell subjects apart in English: elsewhere, only
  /// the same words repeat.
  @Test func matchesOtherLanguagesOnlyWordForWord() {
    let round = [question("Quelle planète est la plus proche du Soleil ?", "Mercure")]
    let drafts = [question("Quelle planète est la plus petite ?", "Mercure"), question("quelle planete est la plus proche du soleil", "Mercure")]
    #expect(QuestionDrafter.dropRepeats(drafts, of: round).map(\.text) == ["Quelle planète est la plus petite ?"])
  }

  @Test func dropsARepeatWithinTheDrafts() {
    let drafts = [question("Who wrote Hamlet?", "William Shakespeare"), question("Which playwright wrote Hamlet?", "william shakespeare")]
    #expect(QuestionDrafter.dropRepeats(drafts, of: []).map(\.text) == ["Who wrote Hamlet?"])
  }

  @Test func comparesAgainstUnfinishedQuestionsByTheirWordsAlone() {
    var unfinished = HostQuestion.blank()
    unfinished.text = "Who wrote Hamlet?"
    let drafts = [question("Who wrote Hamlet", "William Shakespeare"), question("Which playwright wrote Hamlet?", "William Shakespeare")]
    #expect(QuestionDrafter.dropRepeats(drafts, of: [unfinished]).map(\.text) == ["Which playwright wrote Hamlet?"])
  }
}

struct HostLibraryFlowTests {
  @Test func aNewQuestionHasNoRightAnswerUntilOneIsPicked() {
    var question = HostQuestion.blank()
    #expect(question.isUntouched)
    question.text = "Which planet is largest?"
    question.options = ["Jupiter", "Mars", "Venus", "Earth"]
    #expect(!question.isUntouched)
    #expect(question.problem == .noCorrectAnswer, "no silent default of A")
    question.correct = 0
    #expect(question.problem == nil)
  }

  @Test func deletedQuestionsGoBackWhereTheyWere() {
    let library = HostLibrary(fileURL: nil)
    library.questions = (0..<5).map { HostQuestion(text: "Q\($0)", options: ["a", "b", "c", "d"], correct: 0) }
    let removed = library.delete(at: [1, 3])
    #expect(library.questions.map(\.text) == ["Q0", "Q2", "Q4"])
    library.reinsert(removed)
    #expect(library.questions.map(\.text) == ["Q0", "Q1", "Q2", "Q3", "Q4"])
    library.reinsert(removed)
    #expect(library.questions.count == 5, "putting back twice doesn't duplicate")
  }
}
