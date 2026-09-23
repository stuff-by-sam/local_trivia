import DesignSystem
import SwiftUI

/// One question: the clock, the text, and four answers in the thumb zone.
struct QuestionView: View {
  let round: GameStore.Round
  let glass: Namespace.ID

  @Environment(GameStore.self) private var store
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var isRunningLow = false
  @State private var isOver = false
  @AccessibilityFocusState private var isQuestionFocused: Bool

  /// Matches the TV, which turns its clock red for the last ten seconds.
  private static let lowTime: TimeInterval = 10

  private var question: Question { round.question }

  var body: some View {
    VStack(spacing: Space.m) {
      clockBar

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
        // iPad: there's no thumb zone to reach for, and pinning the answers to
        // the bottom of a tall screen strands the question mid-air. Keep the
        // round together and centred instead.
        ViewThatFits(in: .vertical) {
          questionBlock
            .frame(maxHeight: .infinity)
          ScrollView { questionBlock }
            .scrollBounceBehavior(.basedOnSize)
        }
      } else {
        // Centred in the space above the answers when it fits; scrollable when
        // a long question doesn't.
        ViewThatFits(in: .vertical) {
          prompt
            .frame(maxHeight: .infinity)
          ScrollView { prompt }
            .scrollBounceBehavior(.basedOnSize)
            .scrollIndicators(.hidden)
        }
        answers
        status
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

  private var questionBlock: some View {
    VStack(spacing: Space.xl) {
      prompt
      VStack(spacing: Space.m) {
        answers
        status
      }
    }
  }

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
    .padding(.vertical, Space.m)
    .frame(maxWidth: .infinity)
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

  @ViewBuilder
  private var status: some View {
    Group {
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
      } else {
        StatusLine("Faster answers score more", isWaiting: false)
      }
    }
    .frame(minHeight: Space.l + Space.xs)
    .contentTransition(.opacity)
    .motion(.settle, value: round.lockedIndex)
    .motion(.settle, value: round.acknowledged)
  }
}
