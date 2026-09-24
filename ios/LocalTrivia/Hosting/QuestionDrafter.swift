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

  /// One right answer, anywhere: "Which planet has no moons? → Mercury" is
  /// marked wrong for anyone who says Venus. Asking for superlatives, firsts,
  /// names, numbers and dates steers the model toward questions that have one.
  static let instructions = """
    You write questions for a pub quiz. Every question has exactly one correct \
    answer — not just among the four options, but anywhere: if anything else \
    would also be right, write a different question. Questions about which \
    one of a group has or lacks something, or that ask for "a" or "one" of \
    something, usually have several right answers (Mercury and Venus both have \
    no moons), so ask for a superlative, a first, a name, a number or a date \
    instead. The answer is a well-established fact, not an opinion or a recent \
    event. The three wrong answers are plausible for the question but \
    certainly wrong. Keep every question to one short sentence and every \
    answer to a few words. Every question asks something different.
    """

  /// How each draft is checked, apart from writing it (`checked`).
  static let checkInstructions = """
    You check pub-quiz questions before they're played. Judge each option on \
    its own, as an expert would: is it a correct answer to the question? More \
    than one option can be correct, and so can none.
    """

  /// Drafts `count` questions about `topic`, ready to review. The right
  /// answer lands on a random key in each. Drafts that ask what the round
  /// already asks are left out (`dropRepeats`), and so are ones a second
  /// look finds another right answer in (`checked`), so there may be fewer.
  static func draft(topic: String, count: Int, avoiding round: [HostQuestion] = []) async throws(Failure) -> [HostQuestion] {
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
    let drafts = response.content.questions.prefix(count).compactMap {
      question(from: $0, category: category, correctAt: Int.random(in: 0..<4, using: &keys))
    }
    return await checked(dropRepeats(drafts, of: round))
  }

  /// The drafts that, asked again on their own, the model says have exactly
  /// one right option — the one marked. Writing a question, it rarely
  /// notices a second right answer or a wrong key; judging the options apart
  /// from writing them, it catches most. Tested on 20 known questions, this
  /// left out 8 of the 10 bad ones and none of the 10 good ones, at about
  /// 0.75 s a question. (Asking the model to also list every right answer as
  /// it drafts caught none; asking it for a fact about each option first
  /// caught 9, but cost 2.4 s a question and dropped 3 good ones.)
  static func checked(_ drafts: [HostQuestion]) async -> [HostQuestion] {
    var kept: [HostQuestion] = []
    for draft in drafts {
      guard !Task.isCancelled else { break }
      if await hasOneRightOption(draft) { kept.append(draft) }
    }
    return kept
  }

  private static func hasOneRightOption(_ question: HostQuestion) async -> Bool {
    let session = LanguageModelSession(model: .default, instructions: checkInstructions)
    let options = zip(letters, question.options).map { "\($0). \($1)" }.joined(separator: "\n")
    do {
      let said = try await session.respond(to: "Question: \(question.text)\n\(options)", generating: OptionCheck.self)
      return isOnlyRightOption(said.content.correctOptions, of: question)
    } catch {
      // A check that can't run says nothing against the question, and the
      // host reviews every one before it's played.
      log.error("checking a draft failed: \(error.localizedDescription, privacy: .public)")
      return true
    }
  }

  private static let letters = ["A", "B", "C", "D"]

  /// Whether the options a check called right, `said`, are just the marked
  /// one. It may copy an option with its letter ("C. Mercury").
  static func isOnlyRightOption(_ said: [String], of question: HostQuestion) -> Bool {
    let named = Set(said.map(Fingerprint.words))
    let right = question.options.indices.filter { index in
      let option = Fingerprint.words(in: question.options[index])
      return named.contains(option) || named.contains(Fingerprint.words(in: "\(letters[index]) \(option)"))
    }
    return right == [question.correct]
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

  /// `drafts` without the ones that ask what `round` — or an earlier draft —
  /// already asks: the same question however it's cased or punctuated, or
  /// the same answer to a question about the same things ("Which planet is
  /// the largest?" and "What's the largest planet in the solar system?").
  static func dropRepeats(_ drafts: [HostQuestion], of round: [HostQuestion]) -> [HostQuestion] {
    var asked = round.map(Fingerprint.init)
    var kept: [HostQuestion] = []
    for draft in drafts {
      let fingerprint = Fingerprint(draft)
      guard !asked.contains(where: fingerprint.repeats) else { continue }
      asked.append(fingerprint)
      kept.append(draft)
    }
    return kept
  }

  /// What a question asks, for spotting the same one twice.
  struct Fingerprint {
    /// The question's words, folded: case, accents and punctuation aside.
    let words: String
    /// What it's about: its words but for question words, articles,
    /// prepositions and auxiliaries. "Which planet is closest to the Sun?"
    /// and "Which planet is the smallest?" share only "planet".
    let subjects: Set<String>
    /// The right answer's words, or nil if it has none yet.
    let answer: String?

    init(_ question: HostQuestion) {
      words = Self.words(in: question.text)
      let all = Set(words.split(separator: " ").map(String.init))
      // Drafts are written in English. A question with none of its function
      // words is in another language, where they can't be told apart from
      // its subjects, so it repeats only word for word.
      subjects = all.isDisjoint(with: Self.functionWords) ? [] : all.subtracting(Self.functionWords)
      answer = question.options.indices.contains(question.correct) ? Self.words(in: question.options[question.correct]) : nil
    }

    /// Asks the same thing as `other`: the same words, or the same answer
    /// to a question about (nearly) all the same things.
    func repeats(_ other: Fingerprint) -> Bool {
      if !words.isEmpty, words == other.words { return true }
      guard let answer, answer == other.answer, !answer.isEmpty else { return false }
      let smaller = min(subjects.count, other.subjects.count)
      guard smaller > 0 else { return false }
      return Double(subjects.intersection(other.subjects).count) / Double(smaller) >= 0.8
    }

    static func words(in text: String) -> String {
      text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        .joined(separator: " ")
    }

    private static let functionWords: Set<String> = [
      "a", "an", "the", "and", "or", "of", "in", "on", "at", "to", "for", "from", "by", "with", "as", "into", "about",
      "which", "what", "who", "whom", "whose", "when", "where", "why", "how", "many", "much",
      "is", "are", "was", "were", "be", "been", "do", "does", "did", "has", "have", "had", "can",
      "it", "its", "this", "that", "these", "those", "there", "their", "his", "her", "s", "name", "called", "known",
    ]
  }
}

@Generable(description: "The options that correctly answer a quiz question")
nonisolated struct OptionCheck {
  @Guide(description: "Every option that is a correct answer to the question, copied exactly. More than one if several are right.")
  var correctOptions: [String]
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
