import SwiftUI

// Two voices, never more. SF Pro carries content — questions, answers, names —
// because it's the most legible face on the platform. SF Mono is the game's own
// voice: labels, figures, the clock, anything the game reports back. That split
// is what reads as "terminal" without making anyone read a paragraph in mono.

extension Font {
  static func mono(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
    .system(style, design: .monospaced, weight: weight)
  }

  /// For the few oversized figures (rank, points). They scale down to fit
  /// rather than up with Dynamic Type — they're already display-sized.
  static func mono(size: CGFloat, weight: Font.Weight = .bold) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}

extension View {
  /// Small uppercase mono — how the game labels things.
  func terminalStyle(_ style: Font.TextStyle = .caption, weight: Font.Weight = .semibold) -> some View {
    font(.mono(style, weight: weight))
      .textCase(.uppercase)
      .tracking(1.4)
  }
}

/// The terminal's cursor, at the classic ~1 Hz. Holds steady under Reduce
/// Motion. A periodic timeline redraws one glyph twice a second — nothing else.
struct BlinkingCursor: View {
  var glyph = "_"

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.periodic(from: .now, by: 0.53)) { context in
      let lit = reduceMotion || Int(context.date.timeIntervalSinceReferenceDate / 0.53).isMultiple(of: 2)
      Text(verbatim: glyph)
        .opacity(lit ? 1 : 0)
    }
    .accessibilityHidden(true)
  }
}

/// What the game is doing right now, in its own voice: `WAITING FOR HOST_`.
struct StatusLine: View {
  let text: LocalizedStringKey

  init(_ text: LocalizedStringKey) { self.text = text }

  var body: some View {
    HStack(spacing: 1) {
      Text(text)
      BlinkingCursor()
    }
    .terminalStyle(.footnote)
    .foregroundStyle(.secondary)
    .accessibilityElement(children: .combine)
  }
}
