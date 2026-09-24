import SwiftUI

/// A screen's action, full width, in the game's voice: `JOIN GAME →`.
///
/// Primary is the system's prominent glass in the accent, with `onAccent` ink
/// on it — every theme's accent holds 7:1 with that ink (`ThemeTests`), which
/// the system's own label colour can't promise for all ten. Secondary is
/// plain glass. Both are stock system button styles; only the label is ours.
public struct ActionButton: View {
  public enum Prominence: Sendable {
    case primary, secondary
  }

  let title: Text
  let systemImage: String?
  let prominence: Prominence
  let isLoading: Bool
  /// Played on the tap itself — for actions whose result isn't felt otherwise.
  let tapHaptic: Haptic?
  let action: () -> Void

  @State private var taps = 0

  public init(
    _ title: LocalizedStringKey,
    systemImage: String? = nil,
    prominence: Prominence = .primary,
    isLoading: Bool = false,
    tapHaptic: Haptic? = nil,
    action: @escaping () -> Void
  ) {
    self.title = Text(title)
    self.systemImage = systemImage
    self.prominence = prominence
    self.isLoading = isLoading
    self.tapHaptic = tapHaptic
    self.action = action
  }

  public var body: some View {
    let button = Button {
      taps += 1
      action()
    } label: {
      ActionLabel(title: title, systemImage: systemImage, prominence: prominence, isLoading: isLoading)
    }
    .controlSize(.large)
    .accessibilityShowsLargeContentViewer()
    .haptic(trigger: taps) { [tapHaptic] _, _ in tapHaptic }

    switch prominence {
    case .primary: button.buttonStyle(.glassProminent)
    case .secondary: button.buttonStyle(.glass)
    }
  }
}

private struct ActionLabel: View {
  let title: Text
  let systemImage: String?
  let prominence: ActionButton.Prominence
  let isLoading: Bool

  @Environment(\.isEnabled) private var isEnabled

  var body: some View {
    ZStack {
      HStack(spacing: Space.s) {
        title
        if let systemImage {
          Image(systemName: systemImage)
            .accessibilityHidden(true)
        }
      }
      .opacity(isLoading ? 0 : 1)
      if isLoading {
        ProgressView()
          .tint(prominence == .primary ? Palette.onAccentInk : nil)
      }
    }
    .textRole(.action)
    .foregroundStyle(foreground)
    .frame(maxWidth: .infinity, minHeight: Size.target - Space.m)
  }

  private var foreground: AnyShapeStyle {
    switch prominence {
    case .primary: isEnabled || isLoading ? AnyShapeStyle(.onAccent) : AnyShapeStyle(.secondary)
    case .secondary: AnyShapeStyle(.tint)
    }
  }
}

/// A screen's actions, pinned to the bottom where the thumb is. A bar, not an
/// inset: content softens under it with the system's scroll-edge effect.
///
/// Like the system's own bars, its text stops growing at the first
/// accessibility size (`Size.barTypeLimit`), where a pinned bar at AX5 would
/// cover half the screen; a long press shows a label at full size.
public struct ActionBar<Content: View>: View {
  @ViewBuilder var content: Content

  public init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  public var body: some View {
    VStack(spacing: Space.s) {
      content
    }
    .dynamicTypeSize(...Size.barTypeLimit)
    .padding(.horizontal, Space.screen)
    .padding(.top, Space.s)
    .padding(.bottom, Space.s)
  }
}

/// A quiet text button, at least a full target tall.
public struct QuietButton: View {
  let title: Text
  let systemImage: String?
  let action: () -> Void

  public init(_ title: LocalizedStringKey, systemImage: String? = nil, action: @escaping () -> Void) {
    self.title = Text(title)
    self.systemImage = systemImage
    self.action = action
  }

  public var body: some View {
    Button(action: action) {
      Group {
        if let systemImage {
          Label { title } icon: { Image(systemName: systemImage) }
        } else {
          title
        }
      }
      .textRole(.label)
      .frame(minHeight: Size.target)
      .contentShape(.rect)
    }
    .buttonStyle(.borderless)
  }
}
