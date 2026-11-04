import SwiftUI

/// A look for the whole app: the accent, the ink behind the glass, and what
/// the glass refracts. Phosphor is the game's own; fourteen more come with
/// it, and the player can make their own in Themes & Markers
/// (`own(id:name:color:texture:photo:)`): a colour of theirs over one of the
/// backdrops, or over a photo of theirs.
///
/// A theme is this phone's own: other phones with the app keep theirs. The
/// one thing that leaves is the accent of a host's theme (`webAccent`), for
/// the browser players in their game, who have no theme of their own — the
/// laptop's web player dresses them in the operator's accent the same way.
/// A theme never touches the answer colours or the status colours. "B, the
/// cyan one" has to mean the same thing on every phone in the room and on the
/// TV, whoever's wearing what; green is still right and red still wrong. (The
/// shapes beside the letters are `AnswerMarkers`, chosen apart from the theme.)
nonisolated public struct Theme: Hashable, Identifiable, Sendable {
  let kind: Kind

  enum Kind: Hashable, Sendable {
    case builtIn(BuiltIn)
    case own(Own)
  }

  /// One the player made: their name for it, the colour they picked, and
  /// what it's over — with the accent and ink worked out from the colour
  /// once, here, rather than each time the palette's read.
  struct Own: Hashable, Sendable {
    let id: String
    let name: String
    let color: UInt32
    let accent: UInt32
    let ink: UInt32
    let texture: Backdrop.Texture
    let photo: ThemePhoto?
  }

  public static let phosphor = Theme(kind: .builtIn(.phosphor))
  public static let amber = Theme(kind: .builtIn(.amber))
  public static let cobalt = Theme(kind: .builtIn(.cobalt))
  public static let synthwave = Theme(kind: .builtIn(.synthwave))
  public static let noir = Theme(kind: .builtIn(.noir))
  public static let gold = Theme(kind: .builtIn(.gold))
  public static let holographic = Theme(kind: .builtIn(.holographic))
  public static let chalkboard = Theme(kind: .builtIn(.chalkboard))
  public static let glass = Theme(kind: .builtIn(.glass))
  public static let titanium = Theme(kind: .builtIn(.titanium))
  public static let aurora = Theme(kind: .builtIn(.aurora))
  public static let ember = Theme(kind: .builtIn(.ember))
  public static let sakura = Theme(kind: .builtIn(.sakura))
  public static let abyss = Theme(kind: .builtIn(.abyss))
  public static let circuit = Theme(kind: .builtIn(.circuit))

  /// The ones that come with the game, Phosphor first.
  public static let builtIn: [Theme] = BuiltIn.allCases.map { Theme(kind: .builtIn($0)) }

  /// The built-in theme called `id`, if there is one.
  public static func builtIn(id: String) -> Theme? {
    BuiltIn(rawValue: id).map { Theme(kind: .builtIn($0)) }
  }

  /// A theme of the player's own: `color` over `texture`, or over `photo`
  /// when there is one. `color` is lightened, keeping its hue, as far as it
  /// takes to read as well as every built-in theme does
  /// (`legibleAccent(for:)`); the ink is a breath of its hue in the dark.
  public static func own(id: String, name: String, color: UInt32, texture: Backdrop.Texture, photo: ThemePhoto? = nil) -> Theme {
    let accent = legibleAccent(for: color)
    return Theme(kind: .own(Own(id: id, name: name, color: color, accent: accent, ink: ink(for: accent), texture: texture, photo: photo)))
  }

  public var id: String {
    switch kind {
    case .builtIn(let theme): theme.rawValue
    case .own(let theme): theme.id
    }
  }

  public var isBuiltIn: Bool {
    if case .builtIn = kind { true } else { false }
  }

  public var name: ShownName {
    switch kind {
    case .builtIn(let theme): .builtIn(theme.name)
    case .own(let theme): .own(theme.name)
    }
  }

  public var tagline: ShownName {
    switch kind {
    case .builtIn(let theme): .builtIn(theme.tagline)
    case .own(let theme) where theme.photo != nil: .builtIn("Your own color, over a photo of yours")
    case .own(let theme): .builtIn("Your own color, over \(String(localized: theme.texture.name))")
    }
  }

  /// Headings, the cursor, the lit edge of controls. Bright enough for
  /// `Palette.onAccentInk` to sit on it wherever a control is filled with it.
  public var accent: Color { Color(hex: accentRGB) }

  /// The near-black the glow sinks into.
  public var ink: Color { Color(hex: inkRGB) }

  /// The accent as the web player takes it, `#rrggbb`: what a hosting
  /// phone's browser players are dressed in (`public/shared/theme.js`
  /// rotates the page's green family to it, as for a laptop's accent).
  public var webAccent: String {
    let hex = String(accentRGB, radix: 16)
    return "#" + String(repeating: "0", count: 6 - hex.count) + hex
  }

  public var texture: Backdrop.Texture {
    switch kind {
    case .builtIn(let theme): theme.texture
    case .own(let theme): theme.texture
    }
  }

  /// What a theme of the player's own shows instead of a texture.
  public var photo: ThemePhoto? {
    if case .own(let theme) = kind { theme.photo } else { nil }
  }

  /// The colour the player picked, before it was lightened to read: what
  /// the editor shows them.
  public var pickedColor: UInt32? {
    if case .own(let theme) = kind { theme.color } else { nil }
  }

  var accentRGB: UInt32 {
    switch kind {
    case .builtIn(let theme): theme.accentRGB
    case .own(let theme): theme.accent
    }
  }

  var inkRGB: UInt32 {
    switch kind {
    case .builtIn(let theme): theme.inkRGB
    case .own(let theme): theme.ink
    }
  }
}

// MARK: - The player's own colours

nonisolated extension Theme {
  /// The contrast every theme keeps: the accent as text on its ink, and
  /// `Palette.onAccentInk` as text on the accent wherever a control is lit
  /// with it — WCAG AAA, with a little to spare for rounding.
  static let readableContrast = 7.1

  /// A colour to start from in the editor, and what VoiceOver calls it.
  public struct Suggestion: Identifiable, Sendable {
    public let color: UInt32
    public let name: LocalizedStringResource
    public var id: UInt32 { color }
  }

  /// Colours to start from in the editor, around the wheel, all of them
  /// readable as they are.
  public static let suggestions: [Suggestion] = [
    Suggestion(color: 0x56FF8A, name: "Green"),
    Suggestion(color: 0x7AF5D3, name: "Mint"),
    Suggestion(color: 0x5CE1FF, name: "Cyan"),
    Suggestion(color: 0x7CC4FF, name: "Sky Blue"),
    Suggestion(color: 0x9AAEFF, name: "Periwinkle"),
    Suggestion(color: 0xC199FF, name: "Lavender"),
    Suggestion(color: 0xFF8AE2, name: "Magenta"),
    Suggestion(color: 0xFFA3C7, name: "Pink"),
    Suggestion(color: 0xFF8A80, name: "Coral"),
    Suggestion(color: 0xFFA066, name: "Orange"),
    Suggestion(color: 0xFFC94D, name: "Gold"),
    Suggestion(color: 0xEDEDED, name: "White"),
  ]

  /// `color` as an accent that reads: as bright as it can go keeping its hue
  /// and saturation, then toward white, until it has `readableContrast` on
  /// its ink and under `Palette.onAccentInk`. A colour that already does is
  /// returned as it is.
  public static func legibleAccent(for color: UInt32) -> UInt32 {
    func reads(_ accent: UInt32) -> Bool {
      RGB.contrast(accent, ink(for: accent)) >= readableContrast
        && RGB.contrast(Palette.onAccentInkRGB, accent) >= readableContrast
    }
    guard !reads(color) else { return color }
    let (hue, saturation, brightness) = RGB.hsb(color)
    var accent = color
    var level = brightness
    while level < 1, !reads(accent) {
      level = min(1, level + 0.02)
      accent = RGB.fromHSB(hue, saturation, level)
    }
    let bright = accent
    var toWhite = 0.0
    while toWhite < 1, !reads(accent) {
      toWhite = min(1, toWhite + 0.02)
      accent = RGB.mix(bright, 0xFFFFFF, by: toWhite)
    }
    return accent
  }

  /// Whether `color` had to be lightened to read.
  public static func isLightened(_ color: UInt32) -> Bool {
    legibleAccent(for: color) != color
  }

  /// The ink for `accent`: near-black, with a breath of its hue, as the
  /// built-in themes' inks have.
  public static func ink(for accent: UInt32) -> UInt32 {
    let (hue, saturation, _) = RGB.hsb(accent)
    return RGB.fromHSB(hue, saturation * 0.6, 0.055)
  }

  /// `color` as the editor's colour picker hands it back, as `0xRRGGBB`.
  public static func rgb(of color: Color) -> UInt32 {
    // Gamma-encoded sRGB, clamped: the picker can hand back a Display P3
    // colour beyond sRGB's range.
    let resolved = color.resolve(in: EnvironmentValues())
    return RGB.pack(Double(resolved.red), Double(resolved.green), Double(resolved.blue))
  }

  /// `rgb` as a colour, for the editor's swatches.
  public static func color(_ rgb: UInt32) -> Color {
    Color(hex: rgb)
  }
}

/// sRGB arithmetic on `0xRRGGBB`, for colours the player picks.
nonisolated enum RGB {
  static func components(_ rgb: UInt32) -> (red: Double, green: Double, blue: Double) {
    (Double((rgb >> 16) & 0xFF) / 255, Double((rgb >> 8) & 0xFF) / 255, Double(rgb & 0xFF) / 255)
  }

  static func pack(_ red: Double, _ green: Double, _ blue: Double) -> UInt32 {
    func byte(_ value: Double) -> UInt32 { UInt32((min(max(value, 0), 1) * 255).rounded()) }
    return byte(red) << 16 | byte(green) << 8 | byte(blue)
  }

  /// WCAG relative luminance.
  static func luminance(_ rgb: UInt32) -> Double {
    let (red, green, blue) = components(rgb)
    func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }

  /// WCAG contrast ratio, 1 to 21.
  static func contrast(_ one: UInt32, _ other: UInt32) -> Double {
    let (a, b) = (luminance(one), luminance(other))
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)
  }

  static func mix(_ one: UInt32, _ other: UInt32, by fraction: Double) -> UInt32 {
    let (a, b) = (components(one), components(other))
    return pack(
      a.red + (b.red - a.red) * fraction,
      a.green + (b.green - a.green) * fraction,
      a.blue + (b.blue - a.blue) * fraction)
  }

  static func hsb(_ rgb: UInt32) -> (hue: Double, saturation: Double, brightness: Double) {
    let (red, green, blue) = components(rgb)
    let high = max(red, green, blue)
    let low = min(red, green, blue)
    let range = high - low
    guard range > 0 else { return (0, 0, high) }
    var hue: Double
    switch high {
    case red: hue = (green - blue) / range
    case green: hue = 2 + (blue - red) / range
    default: hue = 4 + (red - green) / range
    }
    hue = (hue / 6).truncatingRemainder(dividingBy: 1)
    if hue < 0 { hue += 1 }
    return (hue, range / high, high)
  }

  static func fromHSB(_ hue: Double, _ saturation: Double, _ brightness: Double) -> UInt32 {
    let sector = (hue * 6).truncatingRemainder(dividingBy: 6)
    let chroma = brightness * saturation
    let x = chroma * (1 - abs(sector.truncatingRemainder(dividingBy: 2) - 1))
    let low = brightness - chroma
    let (red, green, blue): (Double, Double, Double) =
      switch sector {
      case ..<1: (chroma, x, 0)
      case ..<2: (x, chroma, 0)
      case ..<3: (0, chroma, x)
      case ..<4: (0, x, chroma)
      case ..<5: (x, 0, chroma)
      default: (chroma, 0, x)
      }
    return pack(red + low, green + low, blue + low)
  }
}

// MARK: - The built-in themes

nonisolated extension Theme {
  /// The themes that come with the game.
  enum BuiltIn: String, CaseIterable, Sendable {
    case phosphor, amber, cobalt, synthwave, noir, gold, holographic, chalkboard, glass, titanium
    case aurora, ember, sakura, abyss, circuit

    var name: LocalizedStringResource {
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
      case .aurora: "Aurora"
      case .ember: "Ember"
      case .sakura: "Sakura"
      case .abyss: "Abyss"
      case .circuit: "Circuit"
      }
    }

    var tagline: LocalizedStringResource {
      switch self {
      case .phosphor: "The broadcast terminal: green on black"
      case .amber: "A monochrome tube, warm as an old terminal"
      case .cobalt: "Cool blue on navy, over a vector display's grid"
      case .synthwave: "Violet on midnight, down to the horizon"
      case .noir: "White on black, through a dot-matrix screen"
      case .gold: "Brushed gold on black, for whoever keeps winning"
      case .holographic: "Iridescent foil that catches the light as you tilt it"
      case .chalkboard: "Chalk on slate, still dusty from the last round"
      case .glass: "Liquid color under clear glass, pooling as you tilt"
      case .titanium: "Brushed titanium: tilt it and the light moves"
      case .aurora: "Northern lights over a polar night, swaying as you tilt"
      case .ember: "Sparks rising from a campfire, late into the night"
      case .sakura: "Cherry blossoms drifting by on a spring night"
      case .abyss: "Light rippling down from far above, and glowing plankton that drift as you tilt"
      case .circuit: "The circuit board behind the screen, with a signal or two lit up"
      }
    }

    var accentRGB: UInt32 {
      switch self {
      case .phosphor: 0x56FF8A
      case .amber: 0xFFB000
      case .cobalt: 0x7C9DFF
      case .synthwave: 0xC77DFF
      case .noir: 0xEDEDED
      case .gold: 0xF5C542
      case .holographic: 0xD4C4FF
      case .chalkboard: 0xFFF0A0
      case .glass: 0xBFEFFF
      case .titanium: 0xC5CDD8
      case .aurora: 0x7AF5D3
      case .ember: 0xFF9466
      case .sakura: 0xFFADCB
      case .abyss: 0x5CC4FF
      case .circuit: 0xC6FF5C
      }
    }

    var inkRGB: UInt32 {
      switch self {
      case .phosphor: 0x04080A
      case .amber: 0x0A0703
      case .cobalt: 0x03060F
      case .synthwave: 0x0A0414
      case .noir: 0x060606
      case .gold: 0x0B0903
      case .holographic: 0x08080E
      // Slate, not black: a board a shade lighter than the room.
      case .chalkboard: 0x141D19
      case .glass: 0x04070F
      case .titanium: 0x0D0F12
      case .aurora: 0x02090C
      case .ember: 0x0D0604
      case .sakura: 0x0E0709
      case .abyss: 0x010711
      // Solder mask: a green so dark it's nearly the room.
      case .circuit: 0x020C06
      }
    }

    var texture: Backdrop.Texture {
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
      case .aurora: .aurora
      case .ember: .embers
      case .sakura: .blossom
      case .abyss: .deepWater
      case .circuit: .traces
      }
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
