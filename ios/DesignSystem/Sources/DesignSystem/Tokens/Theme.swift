import SwiftUI

/// A look for the whole app: the accent, the ink behind the glass, and the
/// texture the glass refracts. Phosphor is the game's own; the rest are sold
/// in the app's shop.
///
/// A theme is this phone's alone — it never crosses the network — and it
/// never touches the answer set or the status colours. "B, the cyan triangle"
/// has to mean the same thing on every phone in the room and on the TV,
/// whoever's wearing what; green is still right and red still wrong.
nonisolated public enum Theme: String, CaseIterable, Identifiable, Sendable {
  case phosphor, amber, cobalt, synthwave, noir, gold, holographic, chalkboard, glass, titanium

  public var id: String { rawValue }

  public var name: LocalizedStringResource {
    switch self {
    case .phosphor: "Phosphor"
    case .amber: "Amber"
    case .cobalt: "Cobalt"
    case .synthwave: "Synthwave"
    case .noir: "Noir"
    case .gold: "Gold"
    case .holographic: "Holographic"
    case .chalkboard: "Chalkboard"
    case .glass: "Glass"
    case .titanium: "Titanium"
    }
  }

  public var tagline: LocalizedStringResource {
    switch self {
    case .phosphor: "The broadcast terminal: green on black"
    case .amber: "A monochrome tube, warm as an old terminal"
    case .cobalt: "Cool blue on navy, over a vector display's grid"
    case .synthwave: "Violet on midnight, down to the horizon"
    case .noir: "White on black, through a dot-matrix screen"
    case .gold: "Brushed gold on black, for whoever keeps winning"
    case .holographic: "Iridescent foil that catches the light as you tilt it"
    case .chalkboard: "Chalk on slate, still dusty from the last round"
    case .glass: "Liquid colour under clear glass, pooling as you tilt"
    case .titanium: "Brushed titanium: tilt it and the light moves"
    }
  }

  /// Headings, the cursor, the lit edge of controls. Bright enough for
  /// `Palette.onAccentInk` to sit on it wherever a control is filled with it.
  public var accent: Color {
    switch self {
    case .phosphor: Color(hex: 0x56FF8A)
    case .amber: Color(hex: 0xFFB000)
    case .cobalt: Color(hex: 0x7C9DFF)
    case .synthwave: Color(hex: 0xC77DFF)
    case .noir: Color(hex: 0xEDEDED)
    case .gold: Color(hex: 0xF5C542)
    case .holographic: Color(hex: 0xD4C4FF)
    case .chalkboard: Color(hex: 0xFFF0A0)
    case .glass: Color(hex: 0xBFEFFF)
    case .titanium: Color(hex: 0xC5CDD8)
    }
  }

  /// The near-black the glow sinks into.
  public var ink: Color {
    switch self {
    case .phosphor: Color(hex: 0x04080A)
    case .amber: Color(hex: 0x0A0703)
    case .cobalt: Color(hex: 0x03060F)
    case .synthwave: Color(hex: 0x0A0414)
    case .noir: Color(hex: 0x060606)
    case .gold: Color(hex: 0x0B0903)
    case .holographic: Color(hex: 0x08080E)
    // Slate, not black: a board a shade lighter than the room.
    case .chalkboard: Color(hex: 0x141D19)
    case .glass: Color(hex: 0x04070F)
    case .titanium: Color(hex: 0x0D0F12)
    }
  }

  public var texture: Backdrop.Texture {
    switch self {
    case .phosphor, .amber: .scanlines
    case .cobalt: .grid
    case .synthwave: .horizon
    case .noir: .dotMatrix
    case .gold: .brushed
    case .holographic: .holofoil
    case .chalkboard: .chalk
    case .glass: .liquid
    case .titanium: .metal
    }
  }
}

nonisolated extension EnvironmentValues {
  /// The theme everything inside is drawn in. `palette` follows it.
  @Entry public var theme: Theme = .phosphor
}

extension View {
  /// Dresses everything inside in `theme`, tint included.
  public func theme(_ theme: Theme) -> some View {
    environment(\.theme, theme)
      .tint(theme.accent)
  }
}
