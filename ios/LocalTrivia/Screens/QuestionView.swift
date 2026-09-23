import SwiftUI

/// One question: the clock, the text, and four answers in the thumb zone.
struct QuestionView: View {
  let round: GameStore.Round
  let glass: Namespace.ID

  @Environment(GameStore.self) private var store
  @Environment(\.accent) private var accent
  @Environment(\.dynamicTypeSize) private var typeSize
  @Environment(\.horizontalSizeClass) private var sizeClass
  @State private var isRunningLow = false
  @State private var isOver = false
  @AccessibilityFocusState private var isQuestionFocused: Bool

  /// Matches the TV, which turns its clock red for the last ten seconds.
  private static let lowTime: TimeInterval = 10

  private var question: Question { round.question }

  var body: some View {
    VStack(spacing: 14) {
      TopBar(glass: glass) {
        // The category is the first thing to go when there isn't room.
        ViewThatFits(in: .horizontal) {
          progress(showingCategory: true)
          progress(showingCategory: false)
        }
      } trailing: {
        HStack(spacing: 8) {
          clock
          GameControls()
        }
      }
      clockBar

      if typeSize.isAccessibilitySize {
        // At accessibility sizes a question and four answers can't share one
        // screen, and pinning the answers would cut the question off
        // mid-sentence. Scroll the round as one column instead.
        ScrollView {
          VStack(spacing: 18) {
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
    .task(id: question.questionId) { await runClock() }
    .sensoryFeedback(.impact(weight: .medium, intensity: 0.9), trigger: round.lockedIndex) { old, new in
      old == nil && new != nil
    }
    .onAppear { isQuestionFocused = true }
  }

  private var questionBlock: some View {
    VStack(spacing: 28) {
      prompt
      VStack(spacing: 14) {
        answers
        status
      }
    }
  }

  private var prompt: some View {
    // Host-authored: verbatim, never a localization key or Markdown.
    Text(verbatim: question.text)
      .font(questionFont)
      .multilineTextAlignment(.center)
      .accessibilityAddTraits(.isHeader)
      .accessibilityFocused($isQuestionFocused)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity)
  }

  // MARK: - Clock

  private func progress(showingCategory: Bool) -> some View {
    HStack(spacing: 7) {
      Text(verbatim: "Q")
        .foregroundStyle(.secondary)
      Text(verbatim: "\(question.qNum.twoDigits)/\(question.total.twoDigits)")
      if showingCategory, let category = question.category {
        Text(verbatim: "·")
          .foregroundStyle(.tertiary)
        Text(verbatim: category)
          .foregroundStyle(.secondary)
      }
    }
    .fixedSize()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Question \(question.qNum) of \(question.total)"))
  }

  private var clock: some View {
    HStack(spacing: 6) {
      Image(systemName: "timer")
      Text(timerInterval: round.window, countsDown: true, showsHours: false)
    }
    .monospacedDigit()
    // A clock that wraps or truncates is worse than no clock.
    .fixedSize()
    .foregroundStyle(isRunningLow ? Color.broadcastRed : .primary)
    .chip(tint: isRunningLow ? Color.broadcastRed.opacity(0.22) : nil)
    .glassEffectID(GlassID.trailingChip, in: glass)
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Time remaining")
  }

  /// Drawn by the system from the round's window: no timer, no per-frame
  /// invalidation — the app does nothing while the clock runs.
  private var clockBar: some View {
    ProgressView(timerInterval: round.window, countsDown: true) {
      EmptyView()
    } currentValueLabel: {
      EmptyView()
    }
    .progressViewStyle(.linear)
    .tint(isRunningLow ? Color.broadcastRed : accent)
    .accessibilityHidden(true)
  }

  private func runClock() async {
    let end = round.window.upperBound
    isRunningLow = end.timeIntervalSinceNow <= Self.lowTime
    isOver = end.timeIntervalSinceNow <= 0
    if !isRunningLow {
      try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow - Self.lowTime))
      guard !Task.isCancelled else { return }
      withAnimation(.smooth) { isRunningLow = true }
    }
    if !isOver {
      try? await Task.sleep(for: .seconds(max(0, end.timeIntervalSinceNow)))
      guard !Task.isCancelled else { return }
      withAnimation(.smooth) { isOver = true }
    }
  }

  // MARK: - Answers

  private var answers: some View {
    VStack(spacing: 10) {
      ForEach(Array(question.options.prefix(AnswerStyle.allCases.count).enumerated()), id: \.offset) { index, text in
        let style = AnswerStyle.allCases[index]
        AnswerButton(style: style, text: text, font: answerFont, state: state(of: index)) {
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
          Text("Locking in…")
            .terminalStyle(.footnote)
        }
      } else if isOver {
        Text("Time's up")
          .terminalStyle(.footnote)
      } else {
        Text("Faster answers score more")
          .terminalStyle(.footnote)
      }
    }
    .foregroundStyle(.secondary)
    .frame(minHeight: 20)
    .contentTransition(.opacity)
    .animation(.smooth, value: round.lockedIndex)
    .animation(.smooth, value: round.acknowledged)
  }

  /// All four answers share one size, stepped down by the longest of them —
  /// never one answer shrunk on its own, which reads as a mistake.
  private var answerFont: Font {
    switch question.options.map(\.count).max() ?? 0 {
    case ...24: .title3
    case ...56: .body
    default: .callout
    }
  }

  /// Short questions render large; long ones step down so the answers never
  /// leave the screen (the web client's `SIZE_STEPS`, in Dynamic Type styles).
  private var questionFont: Font {
    switch question.text.count {
    case ...45: .system(.largeTitle, weight: .bold)
    case ...100: .system(.title, weight: .bold)
    case ...180: .system(.title2, weight: .semibold)
    default: .system(.title3, weight: .semibold)
    }
  }
}

/// An answer: neutral glass with its key at the leading edge. The four colours
/// mark identity rather than fill the screen — until you choose, and your
/// answer lights up in its colour.
struct AnswerButton: View {
  enum State { case open, chosen, dimmed }

  let style: AnswerStyle
  let text: String
  let font: Font
  let state: State
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        AnswerKey(style: style, isInverted: state == .chosen)
        Text(verbatim: text)
          .font(font.weight(state == .chosen ? .bold : .semibold))
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        if state == .chosen {
          Image(systemName: "checkmark")
            .font(.body.weight(.bold))
            .transition(.symbolEffect(.appear))
        }
      }
      // The lit colours are bright; white on them fails contrast, ink doesn't.
      .foregroundStyle(state == .chosen ? Color.broadcastInk : .primary)
      .padding(.horizontal, 14)
      .padding(.vertical, 12)
      .frame(minHeight: 62)
      .contentShape(.rect(cornerRadius: 18))
    }
    .buttonStyle(.plain)
    .glassEffect(glass, in: .rect(cornerRadius: 18))
    .opacity(state == .dimmed ? 0.35 : 1)
    .disabled(state != .open)
    .animation(.snappy(duration: 0.25), value: state)
    .accessibilityLabel(Text("\(style.letter), \(style.shapeName): \(text)"))
    .accessibilityAddTraits(state == .chosen ? .isSelected : [])
  }

  private var glass: Glass {
    switch state {
    // Just a breath of the answer's colour: enough to find "the cyan one" at a
    // glance, as on the TV, without four slabs of colour competing.
    case .open: .regular.tint(style.color.opacity(0.09)).interactive()
    case .chosen: .regular.tint(style.color.opacity(0.8))
    case .dimmed: .regular
    }
  }
}
