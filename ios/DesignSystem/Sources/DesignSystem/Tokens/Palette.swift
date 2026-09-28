import SwiftUI

// Colour, by role. A view asks for `.danger` or `palette.accent`, never a hex:
// the role resolves for the theme being worn, Increase Contrast and Reduce
// Transparency. Values and rules: ios/DESIGN.md, "Colour".

nonisolated extension Color {
  /// sRGB from `0xRRGGBB`. Only the design system names colours.
  public init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

/// Every colour a screen uses, resolved for where it's drawn.
nonisolated public struct Palette: Equatable, Sendable {
  /// Headings, the cursor, selection, the primary action's tint.
  public let accent: Color
  /// The ground under everything.
  public let ink: Color
  /// Text and glyphs on anything lit: the accent, a chosen answer, a medal.
  public let onAccent: Color
  /// Readout and card fills, and their borders.
  public let panel: Color
  public let panelStroke: Color
  /// Dividers between rows.
  public let hairline: Color
  public let success: Color
  public let danger: Color
  public let warning: Color
  /// Missed, no answer.
  public let neutral: Color
  public let isHighContrast: Bool
  public let reducesTransparency: Bool

  public init(theme: Theme, contrast: ColorSchemeContrast = .standard, reduceTransparency: Bool = false) {
    let high = contrast == .increased
    accent = theme.accent
    ink = theme.ink
    onAccent = Self.onAccentInk
    // Opaque under Reduce Transparency: a panel is then a shade of the ink,
    // not a veil over the backdrop.
    panel = reduceTransparency
      ? theme.ink.mix(with: .white, by: high ? 0.14 : 0.08)
      : .white.opacity(high ? 0.10 : 0.04)
    panelStroke = .white.opacity(high ? 0.40 : 0.12)
    hairline = .white.opacity(high ? 0.30 : 0.08)
    success = Self.success
    danger = Self.danger
    warning = Self.warning
    neutral = Self.neutral
    isHighContrast = high
    reducesTransparency = reduceTransparency
  }

  public static let onAccentInk = Color(hex: 0x04080A)
  public static let success = Color(hex: 0x56FF8A)
  public static let danger = Color(hex: 0xFF6A6A)
  public static let warning = Color(hex: 0xFFD60A)
  public static let neutral = Color(hex: 0x9AA8BA)

  /// The glass tint an answer wears: a breath of its colour while open, lit
  /// once chosen. Stronger under Increase Contrast.
  public func tint(for style: AnswerStyle, isLit: Bool) -> Color {
    style.color.opacity(isLit ? (isHighContrast ? 0.9 : 0.8) : (isHighContrast ? 0.18 : 0.09))
  }

  /// A faint slot: an empty PIN cell's underscore.
  public var slot: Color { .white.opacity(isHighContrast ? 0.4 : 0.14) }

  /// The phosphor bloom behind a lit figure. None under Increase Contrast,
  /// where a glow only blurs the edge.
  public func glow(_ color: Color) -> Color {
    isHighContrast ? .clear : color.opacity(0.45)
  }
}

nonisolated extension EnvironmentValues {
  /// The palette for the theme being worn and the reader's display settings.
  public var palette: Palette {
    Palette(theme: theme, contrast: colorSchemeContrast, reduceTransparency: accessibilityReduceTransparency)
  }
}

/// A palette role as a `ShapeStyle`: `.foregroundStyle(.danger)`.
nonisolated public struct PaletteRole: ShapeStyle {
  enum Name: Sendable {
    case accent, onAccent, ink, panel, panelStroke, hairline, success, danger, warning, neutral, slot
  }

  let name: Name

  public func resolve(in environment: EnvironmentValues) -> Color {
    let palette = environment.palette
    return switch name {
    case .accent: palette.accent
    case .onAccent: palette.onAccent
    case .ink: palette.ink
    case .panel: palette.panel
    case .panelStroke: palette.panelStroke
    case .hairline: palette.hairline
    case .success: palette.success
    case .danger: palette.danger
    case .warning: palette.warning
    case .neutral: palette.neutral
    case .slot: palette.slot
    }
  }
}

extension ShapeStyle where Self == PaletteRole {
  public static var themeAccent: PaletteRole { PaletteRole(name: .accent) }
  public static var onAccent: PaletteRole { PaletteRole(name: .onAccent) }
  public static var ink: PaletteRole { PaletteRole(name: .ink) }
  public static var panel: PaletteRole { PaletteRole(name: .panel) }
  public static var panelStroke: PaletteRole { PaletteRole(name: .panelStroke) }
  public static var hairline: PaletteRole { PaletteRole(name: .hairline) }
  public static var success: PaletteRole { PaletteRole(name: .success) }
  public static var danger: PaletteRole { PaletteRole(name: .danger) }
  public static var warning: PaletteRole { PaletteRole(name: .warning) }
  public static var neutral: PaletteRole { PaletteRole(name: .neutral) }
  public static var slot: PaletteRole { PaletteRole(name: .slot) }
}

/// The four answer options: colour + shape + letter, never colour alone, so
/// they stay distinguishable for colour-blind players.
///
/// Same set, same order as the web game (`PAL` in public/shared/common.js), so
/// "B, the cyan triangle" means the same thing wherever trivia is played. No
/// theme changes them, and they appear only on answers.
nonisolated public enum AnswerStyle: Int, CaseIterable, Identifiable, Sendable {
  case a, b, c, d

  public var id: Int { rawValue }

  public var letter: String { ["A", "B", "C", "D"][rawValue] }

  public var symbol: String { ["circle.fill", "triangle.fill", "square.fill", "diamond.fill"][rawValue] }

  public var shapeName: LocalizedStringResource {
    switch self {
    case .a: "circle"
    case .b: "triangle"
    case .c: "square"
    case .d: "diamond"
    }
  }

  public var color: Color {
    switch self {
    case .a: Color(hex: 0x56FF8A)
    case .b: Color(hex: 0x55E6FF)
    case .c: Color(hex: 0xFFB347)
    case .d: Color(hex: 0xFF6AD5)
    }
  }
}

/// First, second, third: gold, silver, bronze — never an answer's colour, so
/// third place doesn't read as "B". Always shown with its place in words.
nonisolated public enum Medal: Int, CaseIterable, Sendable {
  case first = 1, second, third

  public init?(rank: Int?) {
    guard let rank, let medal = Medal(rawValue: rank) else { return nil }
    self = medal
  }

  public var color: Color {
    switch self {
    case .first: Color(hex: 0xF5C542)
    case .second: Color(hex: 0xC7CED8)
    case .third: Color(hex: 0xD98E5B)
    }
  }

  public var label: LocalizedStringResource {
    switch self {
    case .first: "1st"
    case .second: "2nd"
    case .third: "3rd"
    }
  }
}

/// How far a phosphor bloom spreads behind a lit figure.
public enum Glow: Sendable {
  /// A lit edge: the next PIN cell.
  case edge
  /// A figure on a card: the join code.
  case figure
  /// A hero figure: the wordmark, the join code held up to the room.
  case hero
  /// A medal figure: rank on the podium.
  case medal
  /// Across a room, on the TV.
  case tv

  var radius: CGFloat {
    switch self {
    case .edge: 6
    case .figure: 10
    case .hero: 14
    case .medal: 18
    case .tv: 30
    }
  }
}

extension View {
  /// The TV's phosphor bloom behind this, in `color` (the accent by default).
  /// Off under Increase Contrast, where a glow only blurs the edge.
  public func glow(_ glow: Glow, color: Color? = nil) -> some View {
    modifier(GlowModifier(glow: glow, color: color))
  }
}

private struct GlowModifier: ViewModifier {
  let glow: Glow
  let color: Color?
  @Environment(\.palette) private var palette

  func body(content: Content) -> some View {
    content.shadow(color: palette.glow(color ?? palette.accent), radius: glow.radius)
  }
}
