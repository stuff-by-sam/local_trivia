import SwiftUI

/// Four cells, one digit each, with the cursor in the next empty one.
///
/// Only draws. The caller lays a real text field over it — invisible, but it
/// owns focus, the number pad, paste and what VoiceOver reads — so the custom
/// look costs nothing in behaviour or accessibility.
public struct PINCells: View {
  let digits: [Character]
  let length: Int
  let isFocused: Bool

  public init(pin: String, length: Int, isFocused: Bool) {
    self.digits = Array(pin)
    self.length = length
    self.isFocused = isFocused
  }

  public var body: some View {
    HStack(spacing: Space.s) {
      ForEach(0..<length, id: \.self) { index in
        let isNext = isFocused && index == digits.count
        let shape = RoundedRectangle(cornerRadius: Radius.control)
        ZStack {
          if index < digits.count {
            Text(String(digits[index]))
              .transition(.scale(scale: 0.6).combined(with: .opacity))
          } else if isNext {
            BlinkingCursor()
              .foregroundStyle(.themeAccent)
          } else {
            // A faint slot, so empty cells read as digits to fill.
            Text(verbatim: "_")
              .foregroundStyle(.slot)
          }
        }
        .textRole(.display(.cell))
        .frame(maxWidth: .infinity, minHeight: Size.pinCell)
        .glassEffect(in: shape)
        .overlay {
          // The cell the next digit lands in: a lit edge, not a filled one.
          shape
            .strokeBorder(.themeAccent, lineWidth: 1.5)
            .glow(.edge)
            .opacity(isNext ? 1 : 0)
        }
      }
    }
    .motion(.snap, value: digits)
    .accessibilityHidden(true)
  }
}

/// A terminal prompt around a text field: `> robin`.
public struct PromptField<Field: View>: View {
  @ViewBuilder var field: Field

  public init(@ViewBuilder field: () -> Field) {
    self.field = field()
  }

  public var body: some View {
    HStack(spacing: Space.m) {
      Text(verbatim: ">")
        .font(.mono(.title3, weight: .bold))
        .foregroundStyle(.themeAccent)
        .accessibilityHidden(true)
      field
        .font(.mono(.title3, weight: .semibold))
    }
    .padding(.horizontal, Space.inset)
    .frame(minHeight: Size.field)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.control))
  }
}

/// One line saying which game the PIN goes to: a status mark, the game, and
/// how its link is — `● FRIDAY QUIZ · ONLINE` — with the up–down chevron
/// when it's a menu of others to pick from.
///
/// The mark sits outside the line's label, and the line stays the label of a
/// menu: glass inside a menu's label doesn't draw.
public struct GameLine<Mark: View, Label: View>: View {
  @ViewBuilder var mark: Mark
  @ViewBuilder var label: Label

  public init(@ViewBuilder mark: () -> Mark, @ViewBuilder label: () -> Label) {
    self.mark = mark()
    self.label = label()
  }

  public var body: some View {
    HStack(spacing: Space.s) {
      mark
        .frame(width: Space.l)
        .accessibilityHidden(true)
      label
    }
    .padding(.leading, Space.xs)
    .frame(minHeight: Size.target, alignment: .leading)
  }
}

/// A game line's words: the game, its state, and the chevron that says
/// there's a choice. Wraps rather than cuts off: which game, and whether it
/// answers, is what the player looks here to read.
public struct GameLineLabel: View {
  let title: Text
  let detail: Text?
  let isMenu: Bool

  public init(_ title: Text, detail: Text? = nil, isMenu: Bool = true) {
    self.title = title
    self.detail = detail
    self.isMenu = isMenu
  }

  public var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
      title
        .foregroundStyle(.primary)
      if let detail {
        Text(verbatim: "·")
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
        detail
          .foregroundStyle(.secondary)
      }
      if isMenu {
        Image(systemName: "chevron.up.chevron.down")
          .imageScale(.small)
          .foregroundStyle(.secondary)
          .accessibilityHidden(true)
      }
    }
    .textRole(.status)
    .multilineTextAlignment(.leading)
    .fixedSize(horizontal: false, vertical: true)
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
  }
}
