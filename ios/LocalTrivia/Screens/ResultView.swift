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
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.hasRoomToSpread) private var spreads

  enum Verdict: CaseIterable {
    case correct, wrong, missed

    init(_ result: AnswerResult) {
      self = !result.answered ? .missed : result.correct ? .correct : .wrong
    }

    var title: LocalizedStringResource {
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
    Group {
      if spreads {
        // The verdict on one half, what it means on the other — so on a big
        // screen the answer you tapped flows across to the verdict.
        Spread {
          verdictBlock
            .scrollsWhenCrowded()
        } trail: {
          VStack(spacing: Space.m) {
            details
              .scrollsWhenCrowded()
            FooterStatus("Standings next")
          }
        }
      } else {
        VStack(spacing: Space.m) {
          VStack(spacing: Space.xl) {
            verdictBlock
            details
          }
          .scrollsWhenCrowded()

          FooterStatus("Standings next")
        }
      }
    }
    .screenPadding()
    .gameToolbar(.player, status: .progress)
    .task(id: result) {
      shownPoints = 0
      // The verdict lands first, then the points count up. Nothing flies in
      // under Reduce Motion, so there's nothing to wait for.
      if !reduceMotion { try? await Task.sleep(for: Motion.pointsDelay) }
      guard !Task.isCancelled else { return }
      appeared = true
      Motion.count.perform { shownPoints = result.points }
    }
    .onAppear {
      AccessibilityNotification.Announcement(announcement).post()
    }
  }

  /// Right or wrong, and what it was worth.
  private var verdictBlock: some View {
    let color = verdict.color(in: palette)
    return VStack(spacing: Space.l) {
      Badge(symbol: verdict.symbol, color: color, bounce: appeared)
        // Takes the chosen answer's glass identity: the button you tapped
        // flows into this badge.
        .glassEffectID(result.answered ? GlassID.answer(result.chosenIndex) : GlassID.hero, in: glass)

      VStack(spacing: Space.xs) {
        GlassText(verdict.title, role: .shout, color: color)
          .accessibilityAddTraits(.isHeader)
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
          // As wide as the figure it counts to, from the first frame, with
          // the count against "pts": digits arrive at the front, as on a
          // scoreboard, and the line doesn't shuffle to re-centre each time.
          ZStack(alignment: .trailing) {
            Text(verbatim: "+" + result.points.grouped)
              .textRole(.display(.points))
              .hidden()
            GlassCounter(shownPoints, prefix: "+", role: .display(.points), color: result.points > 0 ? .primary : .secondary)
          }
          .minimumScaleFactor(0.5)
          Text("pts")
            .textRole(.label)
            .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Plus \(result.points) points"))
      }
    }
  }

  /// What the answer was, and where that leaves the player.
  private var details: some View {
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
