import DesignSystem
import SwiftUI

// The system toolbar every in-game screen shares. Leading: who you are, or
// where the game is — replaced by "Reconnecting" while the link is down.
// Trailing: the clock or progress, then the host's menu or the player's:
// report, block, or leave.

extension View {
  func gameToolbar(_ leading: GameToolbar.Leading, status: GameToolbar.Status = .none) -> some View {
    modifier(GameToolbar(leading: leading, status: status))
  }
}

struct GameToolbar: ViewModifier {
  enum Leading {
    /// "● ROBIN".
    case player
    /// "Q 03/12".
    case question(number: Int, total: Int)
  }

  enum Status {
    case none
    /// "Q 03/12", between questions.
    case progress
    /// The question's countdown.
    case clock(ClosedRange<Date>, isRunningLow: Bool)
  }

  let leading: Leading
  let status: Status

  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host

  func body(content: Content) -> some View {
    content.toolbar {
      ToolbarItem(placement: .topBarLeading) {
        if store.connection == .online {
          leadingItem
        } else {
          Label {
            Text("Reconnecting")
          } icon: {
            StatusDot(.failed)
          }
          .labelStyle(.titleAndIcon)
          .textRole(.status)
          .fixedSize()
          .readoutTarget()
          .accessibilityAddTraits(.updatesFrequently)
          .accessibilityShowsLargeContentViewer()
        }
      }
      if case .clock(let window, let isRunningLow) = status {
        ToolbarItem(placement: .topBarTrailing) {
          QuestionClock(window: window, isRunningLow: isRunningLow)
        }
      } else if case .progress = status, let progress = store.progress {
        ToolbarItem(placement: .topBarTrailing) {
          QuestionNumber(number: progress.number, total: progress.total)
        }
      }
      // Always there: the host's controls, and a player's way to report,
      // block or leave — reporting can't wait for a pause, and Leave inside
      // a menu doesn't tempt anyone out of a working game.
      ToolbarSpacer(.fixed, placement: .topBarTrailing)
      ToolbarItem(placement: .topBarTrailing) {
        if host.isHosting { HostMenu() } else { PlayerMenu() }
      }
    }
  }

  @ViewBuilder
  private var leadingItem: some View {
    switch leading {
    case .player: PlayerLabel()
    case .question(let number, let total): QuestionNumber(number: number, total: total)
    }
  }
}

/// "● ROBIN".
private struct PlayerLabel: View {
  @Environment(GameStore.self) private var store
  @Environment(\.palette) private var palette

  var body: some View {
    Label {
      Text(verbatim: store.playerName)
    } icon: {
      StatusDot(color: palette.accent)
    }
    .labelStyle(.titleAndIcon)
    .textRole(.status)
    .fixedSize()
    .readoutTarget()
    // Outside the upper-casing, so the name is read as it's written.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Playing as \(store.playerName)"))
    .accessibilityShowsLargeContentViewer()
  }
}

/// "Q 03/12".
struct QuestionNumber: View {
  let number: Int
  let total: Int

  var body: some View {
    HStack(spacing: Space.xs) {
      Text(verbatim: "Q")
        .foregroundStyle(.secondary)
      Text(verbatim: "\(number.twoDigits)/\(total.twoDigits)")
    }
    .textRole(.status)
    .fixedSize()
    .readoutTarget()
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Question \(number) of \(total)"))
    .accessibilityShowsLargeContentViewer()
  }
}

/// The countdown, drawn by the system from the round's window: no timer, no
/// per-frame work. Red for the last ten seconds, as on the TV.
private struct QuestionClock: View {
  let window: ClosedRange<Date>
  let isRunningLow: Bool

  var body: some View {
    Label {
      Text(timerInterval: window, countsDown: true, showsHours: false)
    } icon: {
      Image(systemName: "timer")
    }
    .labelStyle(.titleAndIcon)
    .textRole(.status)
    .monospacedDigit()
    // A clock that wraps or truncates is worse than no clock.
    .fixedSize()
    .readoutTarget()
    .foregroundStyle(isRunningLow ? AnyShapeStyle(.danger) : AnyShapeStyle(.primary))
    // "Time remaining, 0:14": the label names it, the value is the time.
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("Time remaining")
    .accessibilityValue(Text(timerInterval: window, countsDown: true, showsHours: false))
    .accessibilityAddTraits(.updatesFrequently)
    .accessibilityShowsLargeContentViewer()
  }
}

extension View {
  /// A toolbar readout is read, not tapped — but it's found by touch, and
  /// held for the Large Content Viewer, so it's a full target tall. The
  /// system's glass capsule hugs a readout closer than a button's title, so
  /// it keeps `Space.m` inside that: clear of the capsule's round ends.
  fileprivate func readoutTarget() -> some View {
    padding(.horizontal, Space.m)
      .frame(minHeight: Size.target)
      .contentShape(.rect)
  }
}

extension Int {
  /// Grouped for the player's locale: 12,450 / 12 450 / 12.450.
  var grouped: String { formatted(.number) }

  /// "02" — the terminal's fixed-width counters.
  var twoDigits: String { formatted(.number.precision(.integerLength(2...)).grouping(.never)) }
}
