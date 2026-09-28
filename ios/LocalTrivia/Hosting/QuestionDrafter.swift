import Foundation
import FoundationModels
import OSLog

/// Drafts questions on a topic with the on-device model, for the host to
/// review — the one slow part of hosting, writing a round, done in one step.
///
/// It drafts with the phone's own model (`Engine.device`). A build carrying
/// the Private Cloud Compute entitlement (`isCloudEnabled`) drafts with
/// Apple's larger model there when it can (`Engine.cloud`), which knows far
/// more trivia: the topic and the drafts go to Apple's servers for the
/// request, and aren't kept. Offline, over the day's quota, or where Private
/// Cloud Compute isn't offered, the phone's own model takes over.
///
/// Either way, every draft is written from a fact the model states first
/// and checked on its own before it's shown, and it keeps drafting until the
/// host has as many as they asked for. Even so, nothing it writes goes into
/// a round until the host has seen each question with its answer marked.
enum QuestionDrafter {
  /// Where drafts are written and checked.
  enum Engine: Equatable, Sendable {
    /// Apple's larger model, on Private Cloud Compute.
    case cloud
    /// The model on this iPhone.
    case device

    var model: any LanguageModel {
      switch self {
      case .cloud: QuestionDrafter.cloud
      case .device: SystemLanguageModel.default
      }
    }
  }

  private static let cloud = PrivateCloudComputeLanguageModel()

  /// Whether this build drafts on Private Cloud Compute. That takes the
  /// com.apple.developer.private-cloud-compute entitlement, which Apple
  /// grants a team on request; a build signed without it can't reach the
  /// service, and iOS can't tell an app which entitlements it was signed
  /// with. So it's off unless the target sets `PRIVATE_CLOUD_COMPUTE` in
  /// its Active Compilation Conditions — alongside the entitlement in
  /// LocalTrivia.entitlements (ios/README.md, "Build and run").
  #if PRIVATE_CLOUD_COMPUTE
  static let isCloudEnabled = true
  #else
  static let isCloudEnabled = false
  #endif

  /// Whether this phone can draft: Apple Intelligence on, and a model ready.
  static var isAvailable: Bool { preferredEngine != nil }

  /// Where a drafting starts: in the cloud when this build and phone can use
  /// it, else on the phone. Its quota isn't asked for here — reading it can
  /// wait on the system, and this runs on the main thread — a request over it
  /// fails, and the phone takes over (`Failure.cloudUnreachable`).
  static var preferredEngine: Engine? {
    if isCloudEnabled, cloud.isAvailable { return .cloud }
    return SystemLanguageModel.default.isAvailable ? .device : nil
  }

  static let counts = [5, 10, 25]
  /// What the sheet offers first: a round's worth, drafted in a minute or two.
  static let defaultCount = 10

  /// Drafts the phone's model writes per request. It writes one question
  /// after another and checks nothing until it's done, so small batches get
  /// the first questions in front of the host sooner: a few seconds each.
  static let batchSize = 4
  /// The cloud writes the whole round in one request and checks it in one
  /// more — its quota counts requests — asking for this many more than it
  /// needs, for the few a check leaves out, up to `cloudBatchLimit`.
  static let cloudMargin = 3
  static let cloudBatchLimit = 12
  /// Drafts it may write per question asked for, before settling. About
  /// half pass both checks, so this is room for a topic it knows less well.
  static let draftsPerQuestion = 4
  /// How long it keeps at it: two minutes, or 12 seconds a question for a
  /// longer round — the phone's model takes 4 to 12 a question. A topic it
  /// knows well fills in well within this; one it doesn't gets what it can
  /// manage, and the host sees each draft as it comes, free to add them at
  /// any point.
  static func timeLimit(for count: Int) -> Duration {
    max(.seconds(120), .seconds(12) * count)
  }

  /// A draft, and how sure the checks are of it.
  struct Draft: Identifiable, Equatable {
    let question: HostQuestion
    /// Both checks agree its answer is the one right answer. The rest
    /// passed the options check but not the cold answer (`Verdict.likely`):
    /// kept only to make up the number asked for, and flagged for the host
    /// to look at.
    let isConfirmed: Bool
    /// Which model wrote and checked it.
    let engine: Engine

    var id: HostQuestion.ID { question.id }
  }

  enum Failure: Error, Equatable {
    /// Apple Intelligence is off, still downloading, or not on this phone.
    case unavailable
    /// The topic tripped the model's safety guardrails.
    case declined
    /// The phone's language isn't one the model writes.
    case unsupportedLanguage
    /// Anything else; worth another try.
    case failed
    /// Private Cloud Compute couldn't take the request — no internet, the
    /// quota's reached, or the service is down. Drafting carries on on the
    /// phone, so the host never sees this.
    case cloudUnreachable

    var message: String {
      switch self {
      case .unavailable: String(localized: "Apple Intelligence isn't available on this iPhone right now.")
      case .declined: String(localized: "That topic can't be drafted. Try another.")
      case .unsupportedLanguage: String(localized: "Drafting isn't available in this language yet.")
      case .failed, .cloudUnreachable: String(localized: "Couldn't draft questions. Try again.")
      }
    }
  }

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "drafting")

  /// Fact first: a model this size writes a question it can't answer as
  /// readily as one it can, but it's far more often right about a fact it
  /// has to state before asking about it. Tested on 120 drafts over 12
  /// topics, 73% were right with the fact first and 45% without. Keeping to
  /// textbook facts steers it off records that change (the most populous
  /// country) and trivia it half-knows.
  ///
  /// One right answer, anywhere: "Which planet has no moons? → Mercury" is
  /// marked wrong for anyone who says Venus. Asking for superlatives, firsts,
  /// names, numbers and dates steers the model toward questions that have one.
  static let instructions = """
    You write questions for a pub quiz, each from a fact you are certain of. \
    First state the fact: a well-known, long-established fact about the topic, \
    the kind a school textbook or an encyclopedia's first paragraph states. \
    Not a record or ranking that changes over time, a recent event, a disputed \
    claim, or an opinion. Then ask a question that fact answers. \
    The question has exactly one correct answer — not just among the four \
    options, but anywhere — so ask for a name, a number, a date, a place, a \
    first or a superlative, never for "a" or "one" of several things. \
    The three wrong answers are plausible for the question but certainly wrong. \
    Keep every question to one short sentence and every answer to a few words. \
    Every question is about the topic, and asks something different.
    """

  /// How each draft is checked, apart from writing it (`hasOneRightOption`).
  static let checkInstructions = """
    You check pub-quiz questions before they're played. Judge each option on \
    its own, as an expert would: is it a correct answer to the question? More \
    than one option can be correct, and so can none.
    """

  /// How each draft is answered cold, with no options to lean on (`answersAlike`).
  static let answerInstructions = "You answer quiz questions. Give only the answer, in a few words."

  /// Checks give the model's own best answer, not a sample of its maybes.
  private static let checking = GenerationOptions(samplingMode: .greedy)

  /// Drafts `count` questions about `topic`, handing each to `onDraft` as it
  /// passes its checks, and returns them all. The right answer lands on a
  /// random key in each. Drafts that ask what `avoiding` (or an earlier
  /// draft) asks are left out (`dropRepeats`, `sharesAnAnswer`), and so are
  /// any a check doubts (`verdicts(onRound:)` in the cloud, `verdict(on:)`
  /// on the phone). It keeps writing until there are `count`, up to
  /// `draftsPerQuestion` drafts each and `timeLimit(for:)`; if the phone's
  /// model is still short then, it makes up the number with drafts only the
  /// cold answer doubted, unconfirmed. There are fewer than `count` only on a
  /// topic it can't write that many good drafts about.
  static func draft(
    topic: String, count: Int, avoiding round: [HostQuestion] = [], onDraft: (Draft) -> Void = { _ in }
  ) async throws(Failure) -> [Draft] {
    guard var engine = preferredEngine else { throw .unavailable }
    let category = category(for: topic)
    var confirmed: [Draft] = []
    var likely: [Draft] = []
    var asked = round
    var written: [String] = []
    var session: LanguageModelSession?
    var budget = count * draftsPerQuestion
    let deadline = ContinuousClock.now + timeLimit(for: count)
    func keep(_ question: HostQuestion, _ verdict: Verdict, by engine: Engine) {
      guard confirmed.count < count, !Task.isCancelled else { return }
      switch verdict {
      case .confirmed:
        confirmed.append(Draft(question: question, isConfirmed: true, engine: engine))
        onDraft(confirmed[confirmed.count - 1])
      case .likely:
        likely.append(Draft(question: question, isConfirmed: false, engine: engine))
      case .doubtful:
        break
      }
    }
    while confirmed.count < count, budget > 0, ContinuousClock.now < deadline, !Task.isCancelled {
      let size = engine == .cloud ? min(cloudBatchLimit, count - confirmed.count + cloudMargin) : batchSize
      let batch: [DraftedQuestion]
      do {
        batch = try await write(min(size, budget), about: topic, on: engine, in: &session, avoiding: written)
      } catch .cloudUnreachable {
        // The phone's model takes over, told what's been asked.
        guard SystemLanguageModel.default.isAvailable else {
          if written.isEmpty { throw .unavailable }
          break
        }
        engine = .device
        session = nil
        continue
      } catch {
        // The first failure is the host's to hear; a later one ends drafting
        // with what's in hand.
        if written.isEmpty { throw error }
        break
      }
      // Nothing new: the model has run out of things to say.
      guard !batch.isEmpty else { break }
      budget -= batch.count
      written += batch.map(\.question)
      var fresh: [HostQuestion] = []
      for draft in batch {
        guard let question = question(from: draft, category: category, correctAt: Int.random(in: 0..<4)),
          let new = dropRepeats([question], of: asked).first,
          !sharesAnAnswer(new, with: (confirmed + likely).map(\.question) + fresh)
        else { continue }
        asked.append(new)
        fresh.append(new)
      }
      if engine == .cloud {
        do {
          let verdicts = try await verdicts(onRound: fresh)
          for (question, verdict) in zip(fresh, verdicts) { keep(question, verdict, by: .cloud) }
          continue
        } catch {
          // The cloud wrote them but can't check them: the phone checks
          // these, and writes the rest.
          guard SystemLanguageModel.default.isAvailable else { break }
          engine = .device
          session = nil
        }
      }
      for question in fresh {
        guard confirmed.count < count, !Task.isCancelled else { break }
        keep(question, await verdict(on: question), by: .device)
      }
    }
    guard !Task.isCancelled else { return [] }
    let fillers = Array(likely.prefix(count - confirmed.count))
    fillers.forEach(onDraft)
    return confirmed + fillers
  }

  /// Writes up to `count` more drafts about `topic`. One session carries a
  /// whole drafting, so the model sees what it's already written and asks
  /// something new — told only "not these" in a new session, it asks the
  /// same few facts over in new words. When the session's full, a new one
  /// is told `written`.
  static func write(
    _ count: Int, about topic: String, on engine: Engine, in session: inout LanguageModelSession?, avoiding written: [String]
  ) async throws(Failure) -> [DraftedQuestion] {
    let prompt: String
    let isNew = session == nil
    if isNew {
      session = LanguageModelSession(model: engine.model, instructions: instructions)
      var first = "Write \(count) trivia questions about \(topic)."
      if !written.isEmpty {
        // The most recent only: the list costs context, and the oldest are
        // the least likely to come up again.
        first += " Don't ask any of these again:\n" + written.suffix(30).map { "- \($0)" }.joined(separator: "\n")
      }
      prompt = first
    } else {
      prompt = "Write \(count) more trivia questions about \(topic), each from a different fact than any above."
    }
    guard let active = session else { throw .failed }
    do {
      return Array(try await active.respond(to: prompt, generating: DraftedRound.self).content.questions.prefix(count))
    } catch LanguageModelError.contextSizeExceeded where !isNew {
      session = nil
      return try await write(count, about: topic, on: engine, in: &session, avoiding: written)
    } catch let error as LanguageModelError {
      log.error("drafting failed: \(error.localizedDescription, privacy: .public)")
      switch error {
      case .guardrailViolation, .refusal: throw .declined
      case .unsupportedLanguageOrLocale: throw .unsupportedLanguage
      default: throw engine == .cloud ? .cloudUnreachable : .failed
      }
    } catch let error as PrivateCloudComputeLanguageModel.Error {
      log.error("drafting in the cloud failed: \(error.localizedDescription, privacy: .public)")
      throw .cloudUnreachable
    } catch let error as SystemLanguageModel.Error {
      log.error("drafting failed: \(error.localizedDescription, privacy: .public)")
      throw .unavailable
    } catch {
      log.error("drafting failed: \(error.localizedDescription, privacy: .public)")
      throw engine == .cloud ? .cloudUnreachable : .failed
    }
  }

  enum Verdict: Equatable {
    /// Both checks agree.
    case confirmed
    /// Its options judged right, but asked cold, the model answered
    /// something else. From testing, about three in four of these are right.
    case likely
    /// The options judged wrong — about one in three of those are right.
    case doubtful
  }

  /// The phone's check of one draft, apart from writing it: judging the
  /// options, does the model call only the marked one right
  /// (`hasOneRightOption`), and asked
  /// the question cold, does it name the marked one (`answersAlike`)? Tested
  /// on 119 fact-first drafts — 87 right, 32 not — the two together kept 63
  /// right ones and 5 wrong (93% right, from 73%); the first alone kept 76
  /// and 10 (88%).
  static func verdict(on question: HostQuestion) async -> Verdict {
    async let judged = hasOneRightOption(question)
    async let answered = answersAlike(question)
    switch await (judged, answered) {
    case (true, true): return .confirmed
    case (true, false): return .likely
    case (false, _): return .doubtful
    }
  }

  /// The cloud's check, of a whole round in one request: which of each
  /// question's options are right, judged apart from writing them. A draft
  /// is confirmed when only its key is. (Its model rarely misses a fact; what
  /// this catches is a question with two right answers — "the main villain
  /// of the original trilogy", with Palpatine among the options. Answering
  /// cold, as the phone also checks, only flagged right ones.)
  static func verdicts(onRound questions: [HostQuestion], by engine: Engine = .cloud) async throws -> [Verdict] {
    guard !questions.isEmpty else { return [] }
    let session = LanguageModelSession(model: engine.model, instructions: checkInstructions)
    let listed = questions.enumerated().map { number, question in
      "\(number + 1). \(question.text)\n" + zip(letters, question.options).map { "   \($0). \($1)" }.joined(separator: "\n")
    }
    let said = try await session.respond(to: listed.joined(separator: "\n"), generating: RoundCheck.self, options: checking)
    return verdicts(for: questions, judged: said.content.questions)
  }

  /// Each question's verdict from a round's check, matched by number. One
  /// the check skipped is doubtful; one it numbered twice takes the first.
  static func verdicts(for questions: [HostQuestion], judged: [QuestionCheck]) -> [Verdict] {
    let right = Dictionary(judged.map { ($0.number, $0.correctOptions) }) { first, _ in first }
    return questions.indices.map { index in
      guard let options = right[index + 1] else { return .doubtful }
      return isOnlyRightOption(options, of: questions[index]) ? .confirmed : .doubtful
    }
  }

  private static func hasOneRightOption(_ question: HostQuestion) async -> Bool {
    let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: checkInstructions)
    let options = zip(letters, question.options).map { "\($0). \($1)" }.joined(separator: "\n")
    do {
      let said = try await session.respond(to: "Question: \(question.text)\n\(options)", generating: OptionCheck.self, options: checking)
      return isOnlyRightOption(said.content.correctOptions, of: question)
    } catch {
      // Unchecked isn't checked: there are more drafts where this came from.
      log.error("checking a draft failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  private static func answersAlike(_ question: HostQuestion) async -> Bool {
    let session = LanguageModelSession(model: SystemLanguageModel.default, instructions: answerInstructions)
    do {
      let said = try await session.respond(to: question.text, generating: ColdAnswer.self, options: checking)
      return option(named: said.content.answer, in: question.options) == question.correct
    } catch {
      log.error("answering a draft failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  private static let letters = ["A", "B", "C", "D"]

  /// Which option a free answer names: the one sharing the most of its words
  /// — at least half of the shorter's — if no other shares as many. "1776"
  /// names "July 4, 1776", unless "July 2, 1776" is an option too.
  static func option(named answer: String, in options: [String]) -> Int? {
    let said = Fingerprint.terms(in: answer)
    guard !said.isEmpty else { return nil }
    let shares = options.map { option -> Double in
      let terms = Fingerprint.terms(in: option)
      guard !terms.isEmpty else { return 0 }
      return Double(said.intersection(terms).count) / Double(min(said.count, terms.count))
    }
    guard let best = shares.max(), best >= 0.5, shares.count(where: { $0 == best }) == 1 else { return nil }
    return shares.firstIndex(of: best)
  }

  /// Whether the options a check called right, `said`, are just the marked
  /// one. It may copy an option with its letter ("C. Mercury"), or give the
  /// letter alone ("C").
  static func isOnlyRightOption(_ said: [String], of question: HostQuestion) -> Bool {
    let named = Set(said.map(Fingerprint.words))
    let right = question.options.indices.filter { index in
      let option = Fingerprint.words(in: question.options[index])
      let letter = Fingerprint.words(in: letters[index])
      return named.contains(option) || named.contains(letter) || named.contains("\(letter) \(option)")
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

  /// Whether `draft` has the answer of one of `earlier`, the drafts kept so
  /// far. Among the host's own questions that's allowed — the largest planet
  /// and the one with the Great Red Spot are both Jupiter — but in one round
  /// of drafts it's nearly always the same fact asked twice ("Which ocean is
  /// the largest?", "…the biggest?"), and never the variety asked for. One
  /// answer inside the other counts: "Armor" is "Heavy armor".
  static func sharesAnAnswer(_ draft: HostQuestion, with earlier: [HostQuestion]) -> Bool {
    guard draft.options.indices.contains(draft.correct) else { return false }
    let answer = Fingerprint.terms(in: draft.options[draft.correct])
    guard !answer.isEmpty else { return false }
    return earlier.contains { other in
      guard other.options.indices.contains(other.correct) else { return false }
      let theirs = Fingerprint.terms(in: other.options[other.correct])
      return !theirs.isEmpty && (answer.isSubset(of: theirs) || theirs.isSubset(of: answer))
    }
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
      let all = Set(words.split(separator: " ").map { Self.sameAs[String($0)] ?? String($0) })
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

    /// An answer's words for matching another's: folded as `words`, with
    /// thousands run together ("1,064" is "1064") and articles aside.
    static func terms(in text: String) -> Set<String> {
      let joined = text.replacing(/(\d),(?=\d{3})/) { "\($0.1)" }
      return Set(words(in: joined).split(separator: " ").map(String.init)).subtracting(["a", "an", "the", "of"])
    }

    /// Words that ask the same thing, folded to one: a "debut album" is a
    /// "first album", and a film that "came out" was "released".
    private static let sameAs: [String: String] = [
      "debut": "first", "debuted": "first",
      "came": "released", "come": "released", "out": "released", "release": "released",
      "premiered": "released", "premiere": "released", "published": "released",
    ]

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

@Generable(description: "Which options correctly answer each of a round of quiz questions")
nonisolated struct RoundCheck {
  @Guide(description: "One entry for every question, in order")
  var questions: [QuestionCheck]
}

@Generable(description: "Which options correctly answer one quiz question")
nonisolated struct QuestionCheck {
  @Guide(description: "The question's number")
  var number: Int
  @Guide(description: "Every option that is a correct answer to it, copied exactly. More than one if several are right; none if none are.")
  var correctOptions: [String]
}

@Generable(description: "A quiz question's answer, given without seeing any options")
nonisolated struct ColdAnswer {
  @Guide(description: "The answer, in as few words as possible")
  var answer: String
}

@Generable(description: "A round of pub-quiz questions on one topic")
nonisolated struct DraftedRound {
  // `QuestionDrafter.cloudBatchLimit`: a guide takes only a literal.
  @Guide(description: "The questions, each about a different fact", .maximumCount(12))
  var questions: [DraftedQuestion]
}

/// Properties generate in the order they're declared, so the fact comes first
/// and the question is written from it.
@Generable(description: "One trivia question, from a well-known fact, with one correct answer and three wrong ones")
nonisolated struct DraftedQuestion {
  @Guide(description: "A well-known, long-established fact about the topic, in one sentence")
  var fact: String
  @Guide(description: "A question the fact answers: one sentence, under 120 characters")
  var question: String
  @Guide(description: "The correct answer, as the fact states it: one to five words")
  var correctAnswer: String
  @Guide(description: "Three plausible but certainly wrong answers, one to five words each", .count(3))
  var wrongAnswers: [String]
}
