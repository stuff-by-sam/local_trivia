import SwiftUI

/// An answer's key, like a keycap: its shape and letter in its colour — `▲ B`.
/// Colour, shape and letter together, so no answer depends on colour alone.
public struct AnswerKey: View {
  let style: AnswerStyle
  /// Dark on light, for sitting on a lit surface.
  let isInverted: Bool

  public init(style: AnswerStyle, isInverted: Bool = false) {
    self.style = style
    self.isInverted = isInverted
  }

  /// Sits inside an answer button, `keyInset` in from its edge.
  static let inset: CGFloat = 14
  static let radius = Radius.concentric(in: Radius.control, inset: inset)

  public var body: some View {
    let ink = isInverted ? Palette.onAccentInk : style.color
    HStack(spacing: Space.xs) {
      Image(systemName: style.symbol)
        .imageScale(.small)
      Text(verbatim: style.letter)
    }
    .font(.mono(.subheadline, weight: .bold))
    .foregroundStyle(ink)
    .padding(.horizontal, Space.s)
    .padding(.vertical, Space.xs)
    .background(ink.opacity(0.14), in: .rect(cornerRadius: Self.radius))
    .fixedSize()
    // One glyph, `▲ B`, as on the TV and the web: not mirrored.
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityHidden(true)
  }
}

/// An answer: neutral glass with its key at the leading edge. The four colours
/// mark identity rather than fill the screen — until you choose, and your
/// answer lights up in its colour.
///
/// Custom glass, not a system button style: each answer carries its own tint,
/// and the chosen one's glass flows into the verdict (`glassEffectID`, set by
/// the caller).
public struct AnswerButton: View {
  public enum State: Sendable {
    /// Waiting for a tap.
    case open
    /// The player's answer.
    case chosen
    /// Another answer was chosen, or time ran out.
    case dimmed
  }

  let style: AnswerStyle
  let text: String
  let longestOption: Int
  let state: State
  let action: () -> Void

  @Environment(\.palette) private var palette

  /// `longestOption` sizes the text, so all four answers match.
  public init(style: AnswerStyle, text: String, longestOption: Int, state: State, action: @escaping () -> Void) {
    self.style = style
    self.text = text
    self.longestOption = longestOption
    self.state = state
    self.action = action
  }

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.control)
    let button = Button(action: action) {
      HStack(spacing: Space.m) {
        AnswerKey(style: style, isInverted: state == .chosen)
        // Host-authored: verbatim, never a localization key or Markdown.
        Text(verbatim: text)
          .textRole(.answer(longestOption: longestOption, isChosen: state == .chosen))
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        if state == .chosen {
          Image(systemName: "checkmark")
            .font(.body.weight(.bold))
            .transition(.symbolEffect(.appear))
        }
      }
      // The lit colours are bright; white on them fails contrast, ink doesn't.
      .foregroundStyle(state == .chosen ? AnyShapeStyle(.onAccent) : AnyShapeStyle(.primary))
      // The chosen answer's button style pads its label itself; giving that
      // back keeps the lit answer exactly where the open one was.
      .padding(.horizontal, AnswerKey.inset - (state == .chosen ? Self.styleInsets.width : 0))
      .padding(.vertical, Space.m - (state == .chosen ? Self.styleInsets.height : 0))
      .frame(minHeight: Size.answer - (state == .chosen ? 2 * Self.styleInsets.height : 0))
      .contentShape(shape)
    }

    Group {
      if state == .chosen {
        // The system's lit glass: its label sits on the glass. Custom glass
        // draws its tint over what's inside it, which took the dark ink on a
        // lit answer to teal, at 3:1.
        button
          .buttonStyle(.glassProminent)
          .buttonBorderShape(.roundedRectangle(radius: Radius.control))
          .tint(palette.tint(for: style, isLit: true))
      } else {
        button
          .buttonStyle(.plain)
          .glassEffect(glass, in: shape)
      }
    }
    .overlay {
      // Under Increase Contrast an open answer gets an edge in its colour, so
      // four answers never read as one glass column.
      if palette.isHighContrast, state != .chosen {
        shape.strokeBorder(style.color.opacity(state == .open ? 0.7 : 0.3), lineWidth: 1.5)
      }
    }
    .opacity(state == .dimmed ? 0.35 : 1)
    // A chosen answer isn't disabled — the system would grey its lit glass —
    // it just takes no more taps.
    .disabled(state == .dimmed)
    .allowsHitTesting(state == .open)
    .motion(.snap, value: state)
    .accessibilityLabel(Text("\(style.letter), \(style.shapeName): \(text)"))
    .accessibilityAddTraits(state == .chosen ? .isSelected : [])
  }

  /// What `.glassProminent` pads a label by at the default control size.
  private static let styleInsets = CGSize(width: 12, height: 7)

  private var glass: Glass {
    switch state {
    // Just a breath of the answer's colour: enough to find "the cyan one" at a
    // glance, as on the TV, without four slabs of colour competing.
    case .open: .regular.tint(palette.tint(for: style, isLit: false)).interactive()
    // A chosen answer's glass is the button style's; this is never drawn.
    case .chosen, .dimmed: .regular
    }
  }
}
