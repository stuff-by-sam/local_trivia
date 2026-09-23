import SwiftUI

/// The reveal, from this player's side: right or wrong, what it was worth,
/// and what the answer actually was.
struct ResultView: View {
  let outcome: GameStore.Outcome
  let glass: Namespace.ID

  @State private var shownPoints = 0
  @State private var appeared = false

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

    var color: Color {
      switch self {
      case .correct: .broadcastGreen
      case .wrong: .broadcastRed
      case .missed: Color(hex: 0x9AA8BA)
      }
    }
  }

  private var result: AnswerResult { outcome.result }
  private var verdict: Verdict { Verdict(result) }

  var body: some View {
    VStack(spacing: 0) {
      TopBar(glass: glass) {
        PlayerChip()
      } trailing: {
        HStack(spacing: 8) {
          ProgressChip(glass: glass)
          GameControls()
        }
      }

      Spacer()

      VStack(spacing: 28) {
        VStack(spacing: 18) {
          Image(systemName: verdict.symbol)
            .font(.system(size: 40, weight: .bold))
            .foregroundStyle(verdict.color)
            .symbolEffect(.bounce.up, options: .nonRepeating, value: appeared)
            .frame(width: 92, height: 92)
            .glassEffect(.regular.tint(verdict.color.opacity(0.2)), in: .circle)
            // Takes the chosen answer's glass identity: the button you tapped
            // flows into this badge.
            .glassEffectID(result.answered ? GlassID.answer(result.chosenIndex) : GlassID.hero, in: glass)
            .accessibilityHidden(true)

          VStack(spacing: 4) {
            Text(verdict.title)
              .font(.mono(.title3, weight: .heavy))
              .textCase(.uppercase)
              .tracking(4)
              .foregroundStyle(verdict.color)
              .accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
              Text(verbatim: "+\(shownPoints.grouped)")
                .font(.mono(size: 58, weight: .bold))
                .contentTransition(.numericText(value: Double(shownPoints)))
                .minimumScaleFactor(0.5)
              Text("pts")
                .terminalStyle(.subheadline)
                .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .foregroundStyle(result.points > 0 ? .primary : .secondary)
          }
        }

        Readout {
          if let answer = correctAnswer {
            ReadoutRow("Answer") {
              // Keycap on the first line, like a list marker, however far
              // a long answer wraps.
              HStack(alignment: .firstTextBaseline, spacing: 10) {
                AnswerKey(style: answer.style)
                Text(verbatim: answer.text)
                  .font(.body.weight(.semibold))
              }
            }
          }
          ReadoutRow("Total") { Text(verbatim: result.totalScore.grouped) }
          ReadoutRow("Rank") { Text(verbatim: result.rank.map { "#\($0)" } ?? "—") }
        }
      }

      Spacer()

      FooterStatus("Standings next")
    }
    .screenPadding()
    .task(id: result) {
      shownPoints = 0
      try? await Task.sleep(for: .milliseconds(220))
      guard !Task.isCancelled else { return }
      appeared = true
      withAnimation(.snappy(duration: 0.6)) { shownPoints = result.points }
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
