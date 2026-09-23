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
    .padding(.horizontal, Space.l)
    .frame(minHeight: Size.field)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.control))
  }
}

/// A tappable glass row for a picker's label: a status mark, two lines, and
/// the up–down chevron.
public struct PickerRow<Mark: View>: View {
  let title: String
  let detail: String
  @ViewBuilder var mark: Mark

  public init(title: String, detail: String, @ViewBuilder mark: () -> Mark) {
    self.title = title
    self.detail = detail
    self.mark = mark()
  }

  public var body: some View {
    HStack(spacing: Space.m) {
      mark
        .frame(width: Space.l)
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(verbatim: title)
          .textRole(.headline)
          .foregroundStyle(.primary)
        Text(verbatim: detail)
          .textRole(.figureSmall)
          .foregroundStyle(.secondary)
      }
      .lineLimit(1)
      Spacer(minLength: 0)
      Image(systemName: "chevron.up.chevron.down")
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }
    .padding(.horizontal, Space.l)
    .frame(minHeight: Size.picker)
    .contentShape(.rect)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: Radius.control))
  }
}
