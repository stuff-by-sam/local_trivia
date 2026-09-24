import Foundation
import FoundationModels
import OSLog

/// Drafts questions on a topic with the on-device model, for the host to
/// review — the one slow part of hosting, writing a round, done in one step.
///
/// On-device only (`SystemLanguageModel`): the topic and the drafts never
/// leave the phone, and it works with no internet. A model can state a wrong
/// answer with confidence, so nothing it writes goes into a round until the
/// host has seen each question with its answer marked.
enum QuestionDrafter {
  /// Whether this phone can draft: Apple Intelligence on, and the model ready.
  static var isAvailable: Bool { SystemLanguageModel.default.isAvailable }

  static let counts = [5, 10]

  enum Failure: Error, Equatable {
    /// Apple Intelligence is off, still downloading, or not on this phone.
    case unavailable
    /// The topic tripped the model's safety guardrails.
    case declined
    /// The phone's language isn't one the model writes.
    case unsupportedLanguage
    /// Anything else; worth another try.
    case failed

    var message: String {
      switch self {
      case .unavailable: String(localized: "Apple Intelligence isn't available on this iPhone right now.")
      case .declined: String(localized: "That topic can't be drafted. Try another.")
      case .unsupportedLanguage: String(localized: "Drafting isn't available in this language yet.")
      case .failed: String(localized: "Couldn't draft questions. Try again.")
      }
    }
  }

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "drafting")

  private static let instructions = """
    You write questions for a pub quiz. Every question has exactly one correct \
    answer, and that answer is a well-established fact, not an opinion or a \
    recent event. The three wrong answers are plausible for the question but \
    certainly wrong. Keep every question to one short sentence and every answer \
    to a few words. Don't repeat a question.
    """

  /// Drafts `count` questions about `topic`, ready to review. The right
  /// answer lands on a random key in each.
  static func draft(topic: String, count: Int) async throws(Failure) -> [HostQuestion] {
    guard isAvailable else { throw .unavailable }
    let session = LanguageModelSession(model: .default, instructions: instructions)
    let response: LanguageModelSession.Response<DraftedRound>
    do {
      response = try await session.respond(
        to: "Write \(count) trivia questions about \(topic).",
        generating: DraftedRound.self
      )
    } catch let error as LanguageModelError {
      log.error("drafting failed: \(error.localizedDescription, privacy: .public)")
      switch error {
      case .guardrailViolation, .refusal: throw .declined
      case .unsupportedLanguageOrLocale: throw .unsupportedLanguage
      default: throw .failed
      }
    } catch let error as SystemLanguageModel.Error {
      log.error("drafting failed: \(error.localizedDescription, privacy: .public)")
      throw .unavailable
    } catch {
      log.error("drafting failed: \(error.localizedDescription, privacy: .public)")
      throw .failed
    }
    let category = category(for: topic)
    var keys = SystemRandomNumberGenerator()
    return response.content.questions.prefix(count).compactMap {
      question(from: $0, category: category, correctAt: Int.random(in: 0..<4, using: &keys))
    }
  }

  /// A draft as a round's question, or nil if it isn't a usable one: no
  /// text, the wrong number of answers, or an answer given twice.
  static func question(from draft: DraftedQuestion, category: String, correctAt index: Int) -> HostQuestion? {
    let text = draft.question.trimmingCharacters(in: .whitespacesAndNewlines)
    let correct = draft.correctAnswer.trimmingCharacters(in: .whitespacesAndNewlines)
    let wrong = draft.wrongAnswers.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    let all = [correct] + wrong
    guard !text.isEmpty, wrong.count == 3, all.allSatisfy({ !$0.isEmpty }),
      Set(all.map { $0.lowercased() }).count == 4, (0..<4).contains(index)
    else { return nil }
    var options = wrong
    options.insert(correct, at: index)
    let question = HostQuestion(text: text, options: options, correct: index, category: category).normalized()
    return question.problem == nil ? question : nil
  }

  /// The topic, as a category: upper-cased and short.
  static func category(for topic: String) -> String {
    let trimmed = topic.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "GENERAL" : String(trimmed.prefix(24)).uppercased()
  }
}

@Generable(description: "A round of pub-quiz questions on one topic")
nonisolated struct DraftedRound {
  @Guide(description: "The questions, each different", .maximumCount(10))
  var questions: [DraftedQuestion]
}

@Generable(description: "One trivia question with one correct answer and three wrong ones")
nonisolated struct DraftedQuestion {
  @Guide(description: "The question: one sentence, under 120 characters")
  var question: String
  @Guide(description: "The correct answer: an established fact, one to five words")
  var correctAnswer: String
  @Guide(description: "Three plausible but certainly wrong answers, one to five words each", .count(3))
  var wrongAnswers: [String]
}
