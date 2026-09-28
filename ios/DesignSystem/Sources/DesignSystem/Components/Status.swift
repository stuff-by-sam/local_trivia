import SwiftUI

/// The terminal's cursor, at the classic ~1 Hz. Holds steady under Reduce
/// Motion. A periodic timeline redraws one glyph twice a second — nothing else.
public struct BlinkingCursor: View {
  var glyph: String

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(glyph: String = "_") {
    self.glyph = glyph
  }

  public var body: some View {
    TimelineView(.periodic(from: .now, by: 0.53)) { context in
      let lit = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.53).isMultiple(of: 2)
      Text(verbatim: glyph)
        .opacity(lit ? 1 : 0)
    }
    .accessibilityHidden(true)
  }
}

/// What the game is doing right now, in its own voice: `WAITING FOR HOST_`.
/// The cursor marks it as waiting; pass `isWaiting: false` for a steady line.
public struct StatusLine: View {
  let text: Text
  let isWaiting: Bool

  public init(_ text: LocalizedStringKey, isWaiting: Bool = true) {
    self.text = Text(text)
    self.isWaiting = isWaiting
  }

  public init(verbatim text: String, isWaiting: Bool = true) {
    self.text = Text(verbatim: text)
    self.isWaiting = isWaiting
  }

  public var body: some View {
    HStack(spacing: 1) {
      text
      if isWaiting { BlinkingCursor() }
    }
    .textRole(.status)
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
  }
}

/// A lit dot: online, connecting, gone.
public struct StatusDot: View {
  public enum State: Sendable {
    case online, connecting, failed, idle
  }

  let state: State
  var color: Color?

  @Environment(\.palette) private var palette

  /// A dot for a link's state.
  public init(_ state: State) {
    self.state = state
    self.color = nil
  }

  /// A steady dot in `color` — the accent beside a name.
  public init(color: Color) {
    self.state = .online
    self.color = color
  }

  public var body: some View {
    let fill = color ?? fill(for: state)
    Image(systemName: "circle.fill")
      .font(.system(size: Size.dot))
      .foregroundStyle(fill)
      .shadow(color: palette.isHighContrast ? .clear : fill.opacity(0.9), radius: 3)
      .symbolEffect(.pulse, options: .repeating, isActive: state == .connecting || state == .failed)
      .accessibilityHidden(true)
  }

  private func fill(for state: State) -> Color {
    switch state {
    case .online: palette.success
    case .connecting: .secondary
    case .failed: palette.warning
    case .idle: .secondary
    }
  }
}

/// A message under the field it concerns: an error, a notice, or a hint.
public struct FieldMessage: View {
  public enum Kind: Sendable {
    case error, notice, hint
  }

  let text: Text
  let kind: Kind

  public init(_ text: Text, kind: Kind) {
    self.text = text
    self.kind = kind
  }

  public var body: some View {
    Group {
      switch kind {
      case .error:
        Label { text } icon: { Image(systemName: "exclamationmark.triangle.fill") }
          .foregroundStyle(.danger)
      case .notice:
        Label { text } icon: { Image(systemName: "hand.raised.fill") }
          .foregroundStyle(.warning)
      case .hint:
        // Secondary, never tertiary: a hint is something the player needs.
        text.foregroundStyle(.secondary)
      }
    }
    .textRole(.label)
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.leading, Space.xs)
  }
}
