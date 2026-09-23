import SwiftUI

// Glass is for the control layer — things you touch, and the chrome that floats
// over the game. Content sits in hairline readouts. Keeping the two apart is
// what lets the glass mean something.

extension View {
  /// Margins every in-game screen shares, so the top bar never moves.
  func screenPadding() -> some View {
    padding(.horizontal, 20)
      .padding(.top, 4)
      .padding(.bottom, 12)
  }

  /// A floating status chip: mono label in a glass capsule.
  func chip(tint: Color? = nil) -> some View {
    terminalStyle(.footnote)
      .padding(.horizontal, 13)
      .frame(minHeight: 36)
      .glassEffect(.regular.tint(tint), in: .capsule)
  }
}

/// The bar every in-game screen shares. Its leading chip keeps one glass
/// identity across screens, so it morphs from "you" to "Q 01/12" and back
/// rather than being rebuilt — and it's where a dropped link shows up.
struct TopBar<Leading: View, Trailing: View>: View {
  let glass: Namespace.ID
  @ViewBuilder var leading: Leading
  @ViewBuilder var trailing: Trailing

  @Environment(GameStore.self) private var store

  var body: some View {
    HStack(spacing: 10) {
      Group {
        if store.connection == .online {
          leading
        } else {
          HStack(spacing: 8) {
            StatusDot(color: .broadcastGold, isPulsing: true)
            Text("Reconnecting")
          }
          .accessibilityAddTraits(.updatesFrequently)
        }
      }
      .chip()
      .glassEffectID(GlassID.leadingChip, in: glass)
      .animation(.smooth, value: store.connection == .online)

      Spacer(minLength: 8)
      trailing
    }
    .frame(minHeight: 44)
    .lineLimit(1)
    // Chrome, not content: it grows with Dynamic Type, but not without limit.
    .dynamicTypeSize(...DynamicTypeSize.accessibility1)
  }
}

extension TopBar where Trailing == EmptyView {
  init(glass: Namespace.ID, @ViewBuilder leading: () -> Leading) {
    self.init(glass: glass, leading: leading, trailing: { EmptyView() })
  }
}

/// "● ROBIN" — the leading chip between questions.
struct PlayerChip: View {
  @Environment(GameStore.self) private var store
  @Environment(\.accent) private var accent

  var body: some View {
    HStack(spacing: 8) {
      StatusDot(color: accent)
      Text(verbatim: store.playerName)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Playing as \(store.playerName)"))
  }
}

struct StatusDot: View {
  let color: Color
  var isPulsing = false

  var body: some View {
    Image(systemName: "circle.fill")
      .font(.system(size: 7))
      .foregroundStyle(color)
      .shadow(color: color.opacity(0.9), radius: 3)
      .symbolEffect(.pulse, options: .repeating, isActive: isPulsing)
      .accessibilityHidden(true)
  }
}

/// Leaving drops your place in the game, so it asks first.
struct LeaveButton: View {
  @Environment(GameStore.self) private var store
  @State private var isConfirming = false

  var body: some View {
    Button("Leave Game", systemImage: "xmark") { isConfirming = true }
      .labelStyle(.iconOnly)
      .font(.footnote.weight(.bold))
      .buttonStyle(.glass)
      .buttonBorderShape(.circle)
      .controlSize(.large)
      .confirmationDialog("Leave this game?", isPresented: $isConfirming, titleVisibility: .visible) {
        Button("Leave Game", role: .destructive) { store.leave() }
      } message: {
        Text("You'll need the PIN to join again.")
      }
  }
}

/// The trailing control mid-game: the host's menu, or — for a player whose
/// host has gone quiet — a way out. A host's phone can go for good (a flat
/// battery, a force-quit), and a player mustn't be stuck on a frozen screen.
struct GameControls: View {
  @Environment(HostController.self) private var host
  @Environment(GameStore.self) private var store

  var body: some View {
    if host.isHosting {
      HostMenu()
    } else if store.connection.hasFailed {
      LeaveButton()
    }
  }
}

/// A terminal readout: label–value rows in a hairline box. Content, not
/// chrome, so it's drawn rather than glassed.
struct Readout<Content: View>: View {
  @ViewBuilder var content: Content

  var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { rows in
        ForEach(rows) { row in
          row
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
          if row.id != rows.last?.id {
            Rectangle()
              .fill(.white.opacity(0.07))
              .frame(height: 1)
          }
        }
      }
    }
    .background(.white.opacity(0.035), in: .rect(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .strokeBorder(.white.opacity(0.1), lineWidth: 1)
    }
  }
}

struct ReadoutRow<Value: View>: View {
  let label: LocalizedStringKey
  @ViewBuilder var value: Value

  @Environment(\.dynamicTypeSize) private var typeSize

  init(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) {
    self.label = label
    self.value = value()
  }

  // Side by side when the value fits on the line; otherwise the label goes
  // above it, so a long value wraps instead of being cut off. Always stacked
  // at accessibility sizes, where sharing a line would squeeze both.
  var body: some View {
    Group {
      if typeSize.isAccessibilitySize {
        stacked
      } else {
        ViewThatFits(in: .horizontal) {
          inline
          stacked
        }
      }
    }
    .accessibilityElement(children: .combine)
  }

  private var inline: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      caption
      Spacer(minLength: 12)
      value
        .font(.mono(.body, weight: .semibold))
        .lineLimit(1)
    }
  }

  private var stacked: some View {
    VStack(alignment: .leading, spacing: 6) {
      caption
      value
        .font(.mono(.body, weight: .semibold))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var caption: some View {
    Text(label)
      .terminalStyle(.caption)
      .foregroundStyle(.secondary)
      .fixedSize()
  }
}

/// "Q 02/12" — where the game is, on the screens between questions. It takes
/// the question clock's glass identity, so at the reveal the clock becomes it.
struct ProgressChip: View {
  let glass: Namespace.ID

  @Environment(GameStore.self) private var store

  var body: some View {
    if let progress = store.progress {
      HStack(spacing: 7) {
        Text(verbatim: "Q")
          .foregroundStyle(.secondary)
        Text(verbatim: "\(progress.number.twoDigits)/\(progress.total.twoDigits)")
      }
      .fixedSize()
      .chip()
      .glassEffectID(GlassID.trailingChip, in: glass)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text("Question \(progress.number) of \(progress.total)"))
    }
  }
}

/// An answer's key, like a keycap: its shape and letter in its colour — `▲ B`.
/// Colour, shape and letter together, so no answer depends on colour alone.
struct AnswerKey: View {
  let style: AnswerStyle
  /// Dark on light, for sitting on an answer's lit-up glass.
  var isInverted = false

  var body: some View {
    let ink = isInverted ? Color.broadcastInk : style.color
    HStack(spacing: 5) {
      Image(systemName: style.symbol)
        .imageScale(.small)
      Text(verbatim: style.letter)
    }
    .font(.mono(.subheadline, weight: .bold))
    .foregroundStyle(ink)
    .padding(.horizontal, 8)
    .padding(.vertical, 5)
    .background(ink.opacity(0.14), in: .rect(cornerRadius: 8))
    .fixedSize()
    .accessibilityHidden(true)
  }
}

extension Int {
  /// Grouped for the player's locale: 12,450 / 12 450 / 12.450.
  var grouped: String { formatted(.number) }

  /// "02" — the terminal's fixed-width counters.
  var twoDigits: String { formatted(.number.precision(.integerLength(2...)).grouping(.never)) }
}
