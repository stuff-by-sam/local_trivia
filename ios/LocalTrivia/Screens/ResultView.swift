import DesignSystem
import SwiftUI

/// The reveal, from this player's side: right or wrong, what it was worth,
/// and what the answer actually was.
struct ResultView: View {
  let outcome: GameStore.Outcome
  let glass: Namespace.ID

  @State private var shownPoints = 0
  @State private var appeared = false
  @Environment(\.palette) private var palette

  enum Verdict {
    case correct, wrong, missed

    init(_ result: AnswerResult) {
      self = !result.answered ? .missed : result.correct ? .correct : .wrong
    }

    var title: LocalizedStringKey {
      switch self {
      case .correct: "Correct"
      case .wrong: "Not quite"
      case .missed: "No answer"
      }
    }

    var symbol: String {
      switch self {
      case .correct: "checkmark"
      case .wrong: "xmark"
      case .missed: "hourglass.bottomhalf.filled"
      }
    }

    func color(in palette: Palette) -> Color {
      switch self {
      case .correct: palette.success
      case .wrong: palette.danger
      case .missed: palette.neutral
      }
    }
  }

  private var result: AnswerResult { outcome.result }
  private var verdict: Verdict { Verdict(result) }

  var body: some View {
    let color = verdict.color(in: palette)
    VStack(spacing: Space.m) {
      VStack(spacing: Space.xl) {
        VStack(spacing: Space.l) {
          Badge(symbol: verdict.symbol, color: color, isGlass: true)
            .symbolEffect(.bounce.up, options: .nonRepeating, value: appeared)
            // Takes the chosen answer's glass identity: the button you tapped
            // flows into this badge.
            .glassEffectID(result.answered ? GlassID.answer(result.chosenIndex) : GlassID.hero, in: glass)

          VStack(spacing: Space.xs) {
            Text(verdict.title)
              .textRole(.shout)
              .foregroundStyle(color)
              .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: Space.s) {
              Text(verbatim: "+\(shownPoints.grouped)")
                .textRole(.display(.points))
                .contentTransition(.numericText(value: Double(shownPoints)))
                .minimumScaleFactor(0.5)
              Text("pts")
                .textRole(.label)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .foregroundStyle(result.points > 0 ? .primary : .secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Plus \(result.points) points"))
          }
        }

        Readout {
          if let answer = correctAnswer {
            ReadoutRow("Answer") {
              // Keycap on the first line, like a list marker, however far
              // a long answer wraps.
              HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                AnswerKey(style: answer.style)
                Text(verbatim: answer.text)
                  .textRole(.bodyEmphasis)
              }
            }
          }
          ReadoutRow("Total") { Text(verbatim: result.totalScore.grouped) }
          ReadoutRow("Rank") { Text(verbatim: result.rank.map { "#\($0)" } ?? "—") }
        }
      }
      .scrollsWhenCrowded()

      FooterStatus("Standings next")
    }
    .screenPadding()
    .gameToolbar(.player, status: .progress)
    .task(id: result) {
      shownPoints = 0
      // The badge lands first, then the points count up.
      try? await Task.sleep(for: .milliseconds(220))
      guard !Task.isCancelled else { return }
      appeared = true
      Motion.count.perform { shownPoints = result.points }
    }
    .onAppear {
      AccessibilityNotification.Announcement(announcement).post()
    }
  }

  /// What the answer was — there's no big screen, so say it here.
  private var correctAnswer: (style: AnswerStyle, text: String)? {
    guard let question = outcome.question, let index = outcome.correctIndex,
      question.options.indices.contains(index), let style = AnswerStyle(rawValue: index)
    else { return nil }
    return (style, question.options[index])
  }

  private var announcement: String {
    switch verdict {
    case .correct: String(localized: "Correct! Plus \(result.points) points.")
    case .wrong: String(localized: "Not quite. Plus \(result.points) points.")
    case .missed: String(localized: "No answer.")
    }
  }
}

#if DEBUG
#Preview("Correct") { ScreenPreview(.resultCorrect) }
#Preview("Wrong") { ScreenPreview(.resultWrong) }
#Preview("No answer") { ScreenPreview(.resultMissed) }
#endif
