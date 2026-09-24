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

  @Test func namesTheCategoryAfterTheTopic() {
    #expect(QuestionDrafter.category(for: "  90s films ") == "90S FILMS")
    #expect(QuestionDrafter.category(for: "") == "GENERAL")
    #expect(QuestionDrafter.category(for: String(repeating: "a", count: 40)).count == 24)
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
