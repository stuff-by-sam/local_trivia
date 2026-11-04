import DesignSystem
import SwiftUI

/// One question: the clock, the text, and four answers in the thumb zone.
struct QuestionView: View {
  let round: GameStore.Round
  let glass: Namespace.ID

  @Environment(GameStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.hasRoomToSpread) private var spreads
  @State private var isRunningLow = false
  @State private var isOver = false
  @AccessibilityFocusState private var isQuestionFocused: Bool

  /// Matches the TV, which turns its clock red for the last ten seconds.
  private static let lowTime: TimeInterval = 10

  private var question: Question { round.question }

  var body: some View {
    Group {
      if spreads {
        // The question on one half and the answers on the other: on iPhone
        // Duo propped up like a laptop, the question stands up to be read
        // and the answers lie under the thumbs, either side of the hinge.
        Spread {
          VStack(spacing: Space.m) {
            clockBar
            centredPrompt
          }
        } trail: {
          VStack(spacing: Space.m) {
            answers
            status
          }
          .scrollsWhenCrowded()
        }
      } else {
        VStack(spacing: Space.m) {
          clockBar
          column
        }
      }
    }
    .screenPadding()
    .gameToolbar(
      .question(number: question.qNum, total: question.total),
      status: .clock(round.window, isRunningLow: isRunningLow)
    )
    .task(id: question.questionId) { await runClock() }
    .haptic(.lock, trigger: round.lockedIndex) { old, new in old == nil && new != nil }
    .onAppear { isQuestionFocused = true }
  }

  @ViewBuilder
  private var column: some View {
    if typeSize.isAccessibilitySize {
      // At accessibility sizes a question and four answers can't share one
      // screen, and pinning the answers would cut the question off
      // mid-sentence. Scroll the round as one column instead.
      ScrollView {
        VStack(spacing: Space.l) {
          prompt
          answers
          status
        }
      }
      .scrollBounceBehavior(.basedOnSize)
    } else if sizeClass == .regular {
      // A big screen too short to spread: there's no thumb zone to reach
      // for, and pinning the answers to the bottom strands the question
      // mid-air. Keep the round together and centred instead.
      ViewThatFits(in: .vertical) {
        questionBlock
          .frame(maxHeight: .infinity)
        ScrollView { questionBlock }
          .scrollBounceBehavior(.basedOnSize)
      }
    } else {
      centredPrompt
      answers
      status
    }
  }

  private var questionBlock: some View {
    VStack(spacing: Space.xl) {
      prompt
      VStack(spacing: Space.m) {
        answers
        status
      }
    }
  }

  /// Centred in the space it has when it fits; scrollable when a long
  /// question doesn't.
  private var centredPrompt: some View {
    ViewThatFits(in: .vertical) {
      prompt
        .frame(maxHeight: .infinity)
      ScrollView { prompt }
        .scrollBounceBehavior(.basedOnSize)
        .scrollIndicators(.hidden)
    }
  }

  /// The question on its own card of tinted glass: a layer between the
  /// backdrop and the answers, dark enough that it reads at a glance.
  private var prompt: some View {
    VStack(spacing: Space.s) {
      if let category = question.category {
        Text(verbatim: category)
          .textRole(.label)
          .foregroundStyle(.secondary)
      }
      // Host-authored: verbatim, never a localization key or Markdown.
      Text(verbatim: question.text)
        .textRole(.question(length: question.text.count))
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
        .accessibilityFocused($isQuestionFocused)
    }
    .padding(Space.inset)
    .frame(maxWidth: .infinity)
    .panel()
    .questionActions(question)
  }

  // MARK: - Clock

  /// Drawn by the system from the round's window: no timer, no per-frame
  /// invalidation — the app does nothing while the clock runs.
  private var clockBar: some View {
    ProgressView(timerInterval: round.window, countsDown: true) {
      EmptyView()
    } currentValueLabel: {
      EmptyView()
    }
    .progressViewStyle(.linear)
    .tint(isRunningLow ? AnyShapeStyle(.danger) : AnyShapeStyle(.themeAccent))
    .accessibilityHidden(true)
  }

  private func runClock() async {
    let end = round.window.upperBound
    isRunningLow = end.timeIntervalSinceNow <= Self.lowTime
    isOver = end.timeIntervalSinceNow <= 0
    if !isRunningLow {
      try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow - Self.lowTime))
      guard !Task.isCancelled else { return }
      Motion.settle.perform { isRunningLow = true }
    }
    if !isOver {
      try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
      guard !Task.isCancelled else { return }
      Motion.settle.perform { isOver = true }
    }
  }

  // MARK: - Answers

  private var answers: some View {
    let options = Array(question.options.prefix(AnswerStyle.allCases.count))
    let longest = options.map(\.count).max() ?? 0
    return VStack(spacing: Space.s) {
      ForEach(Array(options.enumerated()), id: \.offset) { index, text in
        AnswerButton(style: AnswerStyle.allCases[index], text: text, longestOption: longest, state: state(of: index)) {
          store.choose(index)
        }
        // The result badge takes the chosen answer's identity, so at the
        // reveal this glass flows into it instead of vanishing.
        .glassEffectID(GlassID.answer(index), in: glass)
      }
    }
  }

  private func state(of index: Int) -> AnswerButton.State {
    switch round.lockedIndex {
    case index: .chosen
    case .some: .dimmed
    case nil: isOver ? .dimmed : .open
    }
  }

  private var status: some View {
    QuestionStatus(round: round, isOver: isOver)
  }
}

/// The line under the answers. Its own view, because it's the only part of
/// the question that reads the room's answered count — which changes with
/// every answer from every phone — so those updates redraw this line, not
/// the four answers and the question above it.
private struct QuestionStatus: View {
  let round: GameStore.Round
  let isOver: Bool

  @Environment(GameStore.self) private var store

  var body: some View {
    ZStack {
      // The line's room, held from the first frame: when it appears at the
      // tap, the four answers above it stay exactly where the thumb left them.
      StatusLine("Time's up", isWaiting: false)
        .hidden()
      if round.lockedIndex != nil {
        if round.acknowledged, let answered = store.answered {
          StatusLine("Locked in · \(answered.answered) of \(answered.total) answered")
        } else if round.acknowledged {
          StatusLine("Locked in · waiting for the room")
        } else {
          StatusLine("Locking in…", isWaiting: false)
        }
      } else if isOver {
        StatusLine("Time's up", isWaiting: false)
      }
    }
    .contentTransition(.opacity)
    .motion(.settle, value: round.lockedIndex)
    .motion(.settle, value: round.acknowledged)
  }
}

#if DEBUG
#Preview("Open") { ScreenPreview(.question) }
#Preview("Chosen") { ScreenPreview(.questionChosen) }
#Preview("Time's up") { ScreenPreview(.questionTimeUp) }
#endif
