import DesignSystem
import SwiftUI

/// The practice question's state: which question, its clock, and the answer.
/// Held by the tutorial rather than the view, because a page can be laid out
/// twice (`scrollsWhenCrowded`) and swap copies as the verdict makes it
/// taller — a copy's own state would forget the answer just given.
@Observable
final class PracticeRound {
  var index = 0
  var window: ClosedRange<Date>?
  var chosen: Int?
  var isOver = false
  var points = 0
}

/// A question to try, on the tutorial's "Answer fast" page: the game's own
/// clock and answers, scored as a game scores them, so the first tap of a real
/// game isn't the first tap. Nothing leaves the phone.
struct PracticeQuestion: View {
  let round: PracticeRound
  /// On screen: the clock starts when the page is shown, and waits until then.
  let isShowing: Bool

  @Environment(\.palette) private var palette

  /// Long enough to read and answer; short enough to feel the clock.
  static let timeLimit: TimeInterval = 20

  private var question: Practice { Practice.all[round.index % Practice.all.count] }
  private var chosen: Int? { round.chosen }
  private var isOver: Bool { round.isOver }

  var body: some View {
    VStack(spacing: Space.m) {
      VStack(spacing: Space.s) {
        Text(question.category)
          .textRole(.label)
          .foregroundStyle(.secondary)
        Text(question.text)
          .textRole(.question(length: String(localized: question.text).count))
          .multilineTextAlignment(.center)
      }
      .padding(Space.inset)
      .frame(maxWidth: .infinity)
      .panel()

      if let window = round.window {
        ProgressView(timerInterval: window, countsDown: true) {
          EmptyView()
        } currentValueLabel: {
          EmptyView()
        }
        .progressViewStyle(.linear)
        .tint(AnyShapeStyle(.themeAccent))
        // Stopped where it was once there's an answer.
        .opacity(chosen == nil && !isOver ? 1 : 0)
        .accessibilityHidden(true)
      }

      let options = question.options.map { String(localized: $0) }
      let longest = options.map(\.count).max() ?? 0
      VStack(spacing: Space.s) {
        ForEach(AnswerStyle.allCases) { style in
          AnswerButton(style: style, text: options[style.rawValue], longestOption: longest, state: state(of: style.rawValue)) {
            choose(style.rawValue)
          }
        }
      }

      outcome
        .frame(minHeight: Size.target)
    }
    .haptic(trigger: chosen) { old, new in
      guard old == nil, let new else { return nil }
      return new == question.correct ? .correct : .wrong
    }
    .task(id: TaskKey(isShowing: isShowing, index: round.index)) { await runClock() }
  }

  @ViewBuilder
  private var outcome: some View {
    if chosen != nil || isOver {
      let isRight = chosen == question.correct
      let verdict: ResultView.Verdict = chosen == nil ? .missed : isRight ? .correct : .wrong
      let answer = String(localized: question.options[question.correct])
      VStack(spacing: Space.s) {
        HStack(spacing: Space.s) {
          GlassSymbol(verdict.symbol, color: verdict.color(in: palette))
            .glassBounce(trigger: chosen)
          Group {
            if isRight {
              Text("Correct · +\(round.points.grouped) pts")
            } else if chosen == nil {
              Text("Time's up · it was \(AnswerStyle.allCases[question.correct].letter), \(answer)")
            } else {
              Text("Not quite · it was \(AnswerStyle.allCases[question.correct].letter), \(answer)")
            }
          }
          .textRole(.status)
          .foregroundStyle(verdict.color(in: palette))
        }
        QuietButton("Try Another", systemImage: "arrow.counterclockwise", action: tryAnother)
      }
      .transition(.opacity)
      .accessibilityElement(children: .contain)
    }
  }

  private func state(of option: Int) -> AnswerButton.State {
    switch chosen {
    case option: .chosen
    case .some: .dimmed
    case nil: isOver ? .dimmed : .open
    }
  }

  private func choose(_ option: Int) {
    guard round.chosen == nil, !round.isOver, let window = round.window else { return }
    let elapsed = Date.now.timeIntervalSince(window.lowerBound)
    var rules = HostRules()
    rules.timeLimit = Int(Self.timeLimit)
    let points = Scoring.points(isCorrect: option == question.correct, elapsed: elapsed, timeLimit: Self.timeLimit, rules: rules)
    Motion.settle.perform {
      round.points = points
      round.chosen = option
    }
    let answer = String(localized: question.options[question.correct])
    AccessibilityNotification.Announcement(
      option == question.correct
        ? String(localized: "Correct, plus \(points) points")
        : String(localized: "Not quite. It was \(answer).")
    ).post()
  }

  private func tryAnother() {
    Motion.settle.perform {
      round.chosen = nil
      round.isOver = false
      round.points = 0
      round.window = nil
      round.index += 1
    }
  }

  /// Starts the clock when the page comes on screen, and ends the question
  /// when it runs out. A page swiped away unanswered starts afresh; a copy of
  /// the page laid out anew carries on with the same clock.
  private func runClock() async {
    guard isShowing else {
      if round.chosen == nil {
        round.window = nil
        round.isOver = false
      }
      return
    }
    guard round.chosen == nil, !round.isOver else { return }
    let window = round.window ?? Date.now...Date.now.addingTimeInterval(Self.timeLimit)
    round.window = window
    try? await Task.sleep(for: .seconds(max(0, window.upperBound.timeIntervalSinceNow)))
    guard !Task.isCancelled, round.chosen == nil else { return }
    Motion.settle.perform { round.isOver = true }
  }

  private struct TaskKey: Equatable {
    let isShowing: Bool
    let index: Int
  }
}

/// The practice questions, taken in turn.
private struct Practice {
  let category: LocalizedStringResource
  let text: LocalizedStringResource
  let options: [LocalizedStringResource]
  let correct: Int

  static let all = [
    Practice(category: "SPACE", text: "Which planet has the most moons?", options: ["Jupiter", "Saturn", "Uranus", "Neptune"], correct: 1),
    Practice(category: "GEOGRAPHY", text: "Which is the largest ocean on Earth?", options: ["Atlantic", "Indian", "Arctic", "Pacific"], correct: 3),
    Practice(category: "SCIENCE", text: "Which gas do plants take in from the air?", options: ["Oxygen", "Nitrogen", "Carbon dioxide", "Helium"], correct: 2),
    Practice(category: "MATHS", text: "How many sides does a hexagon have?", options: ["Five", "Six", "Seven", "Eight"], correct: 1),
  ]
}
