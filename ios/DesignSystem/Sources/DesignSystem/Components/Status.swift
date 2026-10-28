import SwiftUI

/// The terminal's cursor, at the classic ~1 Hz. Holds steady under Reduce
/// Motion. A periodic timeline redraws one glyph twice a second — nothing else.
public struct BlinkingCursor: View {
  var glyph: String

  public init(glyph: String = "_") {
    self.glyph = glyph
  }

  public var body: some View {
    Blinking {
      Text(verbatim: glyph)
    }
  }
}

/// Anything, lit and dark at the cursor's ~1 Hz; steady under Reduce Motion.
/// Only `content` redraws.
///
/// Every cursor keeps the same beat: the timeline counts half-periods from
/// a fixed moment, not from whenever the view was last drawn — so a screen
/// redrawing around it (a keystroke, a player arriving) never restarts or
/// stretches a blink, and two cursors on screen blink together.
struct Blinking<Content: View>: View {
  @ViewBuilder var content: Content

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// Half a blink: lit this long, then dark this long.
  static var period: TimeInterval { 0.53 }
  /// When the beat started: the same for every cursor, every time.
  private static var epoch: Date { Date(timeIntervalSinceReferenceDate: 0) }

  var body: some View {
    TimelineView(.periodic(from: Self.epoch, by: Self.period)) { context in
      content
        .opacity(reduceMotion || Self.isLit(at: context.date) ? 1 : 0)
    }
    .accessibilityHidden(true)
  }

  /// Lit on even half-periods. The timeline wakes on their boundaries, so it
  /// rounds to the nearest rather than flooring a time that may land a hair
  /// before one.
  static func isLit(at date: Date) -> Bool {
    Int((date.timeIntervalSince(epoch) / period).rounded()).isMultiple(of: 2)
  }
}

/// What the game is doing right now, in its own voice: `WAITING FOR HOST_`.
/// The cursor marks it as waiting; pass `isWaiting: false` for a steady line.
///
/// On a capsule of glass, like the toolbar's readouts: a layer of its own
/// over the backdrop. At accessibility sizes, where the line wraps, the
/// capsule's ends would crowd it, so it's a rounded rectangle.
public struct StatusLine: View {
  let text: Text
  let isWaiting: Bool

  @Environment(\.dynamicTypeSize) private var typeSize

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
    .multilineTextAlignment(.center)
    .padding(.horizontal, Space.m)
    .padding(.vertical, Space.s)
    .frame(minHeight: Size.statusPill)
    .glassCard(in: typeSize.isAccessibilitySize ? AnyShape(.rect(cornerRadius: Radius.control)) : AnyShape(.capsule))
    .accessibilityElement(children: .combine)
  }
}

/// A lit dot: online, connecting, gone. A bead of glass in its colour over
/// its own glow; it breathes while connecting or failing.
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
    Group {
      if palette.isHighContrast {
        Circle().fill(fill)
      } else {
        GlassCharacter(shape: Circle(), color: fill, depth: .dot)
      }
    }
    .frame(width: Size.dot, height: Size.dot)
    .glassPulse(isActive: state == .connecting || state == .failed)
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
