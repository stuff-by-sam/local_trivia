import SwiftUI

// Content sits in drawn panels, not glass: glass is for what you touch. A
// panel is a faint fill and a hairline border, both from the palette, so they
// firm up under Increase Contrast and go opaque under Reduce Transparency.

extension View {
  /// A drawn panel behind this content.
  public func panel(radius: CGFloat = Radius.panel) -> some View {
    background(.panel, in: .rect(cornerRadius: radius))
      .overlay {
        RoundedRectangle(cornerRadius: radius)
          .strokeBorder(.panelStroke, lineWidth: 1)
      }
  }

  /// The margins every in-game screen shares.
  public func screenPadding() -> some View {
    padding(.horizontal, Space.screen)
      .padding(.top, Space.xs)
      .padding(.bottom, Space.m)
  }
}

/// A terminal readout: label–value rows in a panel.
public struct Readout<Content: View>: View {
  @ViewBuilder var content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    VStack(spacing: 0) {
      Group(subviews: content) { rows in
        ForEach(rows) { row in
          row
            .padding(.horizontal, Space.l)
            .padding(.vertical, Space.m)
          if row.id != rows.last?.id {
            Rectangle()
              .fill(.hairline)
              .frame(height: 1)
          }
        }
      }
    }
    .panel()
  }
}

public struct ReadoutRow<Value: View>: View {
  let label: LocalizedStringKey
  @ViewBuilder var value: Value

  @Environment(\.dynamicTypeSize) private var typeSize

  public init(_ label: LocalizedStringKey, @ViewBuilder value: () -> Value) {
    self.label = label
    self.value = value()
  }

  // Side by side when the value fits on the line; otherwise the label goes
  // above it, so a long value wraps instead of being cut off. Always stacked
  // at accessibility sizes, where sharing a line would squeeze both.
  public var body: some View {
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
    HStack(alignment: .firstTextBaseline, spacing: Space.m) {
      caption
      Spacer(minLength: Space.m)
      value
        .textRole(.figure)
        .lineLimit(1)
    }
  }

  private var stacked: some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      caption
      value
        .textRole(.figure)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private var caption: some View {
    Text(label)
      .textRole(.label)
      .foregroundStyle(.secondary)
      .fixedSize()
  }
}

/// A mono label over its control, like a form in a terminal. The label is
/// hidden from VoiceOver: the control carries its own.
public struct LabeledField<Content: View>: View {
  let label: LocalizedStringKey
  @ViewBuilder var content: Content

  public init(_ label: LocalizedStringKey, @ViewBuilder content: () -> Content) {
    self.label = label
    self.content = content()
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      Text(label)
        .textRole(.label)
        .foregroundStyle(.secondary)
        .padding(.leading, Space.xs)
        .accessibilityHidden(true)
      content
    }
  }
}

/// Mono, uppercase section titles for forms and lists.
public struct SectionHeader: View {
  let text: Text

  public init(_ text: LocalizedStringKey) {
    self.text = Text(text)
  }

  public init(verbatim text: String) {
    self.text = Text(verbatim: text)
  }

  public var body: some View {
    text
      .textRole(.label)
      .foregroundStyle(.secondary)
  }
}

/// A thin rule with a word in it: `——— OR ———`.
public struct DividerLabel: View {
  let text: LocalizedStringKey

  public init(_ text: LocalizedStringKey) {
    self.text = text
  }

  public var body: some View {
    HStack(spacing: Space.m) {
      Rectangle().fill(.hairline).frame(height: 1)
      Text(text)
        .textRole(.labelSmall)
        .foregroundStyle(.secondary)
      Rectangle().fill(.hairline).frame(height: 1)
    }
    .accessibilityHidden(true)
  }
}
