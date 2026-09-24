import DesignSystem
import SwiftUI

// The system toolbar every in-game screen shares. Leading: who you are, or
// where the game is — replaced by "Reconnecting" while the link is down.
// Trailing: the clock or progress, then the host's menu or a way out.

extension View {
  func gameToolbar(_ leading: GameToolbar.Leading, status: GameToolbar.Status = .none, controls: GameToolbar.Controls = .whenNeeded) -> some View {
    modifier(GameToolbar(leading: leading, status: status, controls: controls))
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

  enum Controls {
    /// The host's menu, or Leave: in the lobby and after the game.
    case always
    /// The host's menu, or Leave only once the host has gone quiet — a
    /// player mustn't be stuck on a frozen screen, nor tempted out of a
    /// working game.
    case whenNeeded
  }

  let leading: Leading
  let status: Status
  let controls: Controls

  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host

  func body(content: Content) -> some View {
    content.toolbar {
      ToolbarItem(placement: .topBarLeading) {
        Group {
          if store.connection == .online {
            leadingItem
          } else {
            Label {
              Text("Reconnecting")
            } icon: {
              StatusDot(.failed)
            }
            .labelStyle(.titleAndIcon)
            .accessibilityAddTraits(.updatesFrequently)
          }
        }
        .textRole(.status)
        .fixedSize()
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
      if showsControls {
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
          if host.isHosting { HostMenu() } else { LeaveButton() }
        }
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

  private var showsControls: Bool {
    switch controls {
    case .always: true
    case .whenNeeded: host.isHosting || store.connection.hasFailed
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Playing as \(store.playerName)"))
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
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Question \(number) of \(total)"))
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
    .foregroundStyle(isRunningLow ? AnyShapeStyle(.danger) : AnyShapeStyle(.primary))
    .accessibilityElement(children: .combine)
    .accessibilityLabel("Time remaining")
  }
}

/// Leaves at once. The join screen offers Undo for a few seconds, which takes
/// the seat back, score and all — so there's nothing to ask first.
struct LeaveButton: View {
  @Environment(GameStore.self) private var store

  var body: some View {
    Button("Leave Game", systemImage: "xmark") { store.leave() }
  }
}

extension Int {
  /// Grouped for the player's locale: 12,450 / 12 450 / 12.450.
  var grouped: String { formatted(.number) }

  /// "02" — the terminal's fixed-width counters.
  var twoDigits: String { formatted(.number.precision(.integerLength(2...)).grouping(.never)) }
}
