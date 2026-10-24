import Foundation

/// A prompt the host can take to any AI chat they like, which asks for a
/// round on their topic as a CSV that imports here as it is (`CSVImport`):
/// the columns in order, a letter for the right answer, the time limits this
/// app allows. The app sends it nowhere: the host copies it.
///
/// In English whatever the phone's language: the columns are, and every
/// chat reads it. The questions come back in the topic's language.
nonisolated enum AIPrompt {
  /// How many a host can ask for at once.
  static let counts = 1...100
  static let defaultCount = 10

  /// The columns, as the header row `CSVImport` looks for.
  static let header = "question,option_a,option_b,option_c,option_d,correct,category,time_limit"

  static func text(topic: String, count: Int) -> String {
    let topic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
    let count = count.clamped(to: counts)
    let questions = count == 1 ? "1 multiple-choice trivia question" : "\(count) multiple-choice trivia questions"
    let lines = count == 1 ? "one line" : "\(count) lines"
    return """
      Write \(questions) about: \(topic)

      Reply with only a CSV file in one code block, with nothing before or after it. Its first line must be this header, exactly:
      \(header)

      Then one line per question, \(lines) in all:
      - question: the question, under 120 characters.
      - option_a, option_b, option_c, option_d: four different answers, each under 40 characters. Exactly one is right.
      - correct: the letter of the right answer: A, B, C or D. Spread the right answers evenly across the four letters.
      - category: one or two words for the question's subject, in capitals, like SCIENCE or MUSIC.
      - time_limit: the seconds to answer, from 10 to 60. Use 20 unless the question takes longer to read.

      Put any value that contains a comma in double quotes, and write a double quote inside a value as two ("").
      Every question must be accurate, have one clearly right answer, and suit all ages: nothing offensive, hateful or explicit. Don't repeat a question.

      For example:
      \(header)
      "Which planet has the most moons?",Jupiter,Saturn,Uranus,Neptune,B,SPACE,20
      """
  }
}
