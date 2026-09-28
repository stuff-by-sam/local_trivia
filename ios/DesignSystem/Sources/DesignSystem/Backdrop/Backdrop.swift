import SwiftUI

/// The screen behind the glass: near-black, one phosphor glow, faint scanlines.
///
/// Liquid Glass takes its character from what it refracts, so this is the one
/// place colour lives. It's calm on purpose: the glow's hue follows the game
/// (accent while playing, green or red at the reveal, gold on the podium),
/// and the scanlines give the glass texture to bend, the way the TV's CRT
/// theme does. It's static between moods — it only animates when one changes.
///
/// The ink and the texture come from the theme (`Theme`); what's described
/// above is Phosphor, the game's own. Holographic's foil, Glass's liquid and
/// Titanium's shine follow the phone's tilt — and hold still while a
/// question is up.
///
/// Under Reduce Transparency or Increase Contrast it's the glow alone: no
/// texture under text, and under Increase Contrast no vignette either.
public struct Backdrop: View {
  nonisolated public enum Mood: Hashable, Sendable {
    case idle
    case question
    case correct
    case wrong
    case missed
    case celebrate
  }

  /// What the glass has to bend. Each is drawn once and holds still, bar the
  /// three that follow the phone's tilt (`Textures.swift`).
  nonisolated public enum Texture: Equatable, Sendable {
    case scanlines
    /// A vector display's graticule.
    case grid
    /// A perspective grid running to a horizon, under the scanlines.
    case horizon
    /// A fine mesh the glow shows through as dots.
    case dotMatrix
    /// Hairline streaks, like brushed metal.
    case brushed
    /// An iridescent sheen that slides as the phone tilts, over fine
    /// diffraction lines.
    case holofoil
    /// Eraser smears and chalk dust.
    case chalk
    /// Pools of liquid colour for the glass to refract, running downhill as
    /// the phone tilts.
    case liquid
    /// Brushed metal, with a band of light that slides as the phone tilts.
    case metal
  }

  let mood: Mood

  @Environment(\.theme) private var theme
  @Environment(\.palette) private var palette
  @Environment(\.backdropFollowsTilt) private var followsTilt
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  public init(mood: Mood) {
    self.mood = mood
  }

  public var body: some View {
    ZStack {
      MeshGradient(
        width: 3,
        height: 3,
        points: [
          [0, 0], [0.5, 0], [1, 0],
          [0, 0.45], [0.5, 0.4], [1, 0.45],
          [0, 1], [0.5, 1], [1, 1],
        ],
        colors: colors,
        background: theme.ink
      )
      if !isPlain {
        texture
      }
      if !palette.isHighContrast {
        // Falls off toward the edges, like a tube.
        RadialGradient(
          colors: [.clear, .black.opacity(0.55)],
          center: .center,
          startRadius: 180,
          endRadius: 700
        )
      }
    }
    .ignoresSafeArea()
    .motion(.mood, value: mood)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  /// Nothing drawn under text but the glow itself.
  private var isPlain: Bool {
    palette.isHighContrast || palette.reducesTransparency
  }

  @ViewBuilder
  private var texture: some View {
    switch theme.texture {
    case .scanlines: Scanlines()
    case .grid: Graticule(color: theme.accent)
    case .horizon:
      ZStack {
        Horizon(color: theme.accent)
        Scanlines()
      }
    case .dotMatrix: DotMatrix()
    case .brushed: Brushed(color: theme.accent)
    case .holofoil: Holofoil(followsTilt: movesWithTilt)
    case .chalk: ChalkDust()
    case .liquid: LiquidPools(followsTilt: movesWithTilt, isQuiet: mood == .question)
    case .metal: BrushedMetal(color: theme.accent, followsTilt: movesWithTilt)
    }
  }

  /// Whether a texture that can follow the phone's tilt does. Never while a
  /// question is up, when nothing may compete with reading it.
  private var movesWithTilt: Bool {
    followsTilt && !reduceMotion && mood != .question
  }

  private var glow: Color {
    switch mood {
    case .idle, .question: theme.accent
    case .correct: palette.success
    case .wrong: palette.danger
    case .missed: palette.neutral
    case .celebrate: Medal.first.color
    }
  }

  /// How far the glow sinks into the ink: higher is darker. Quietest while a
  /// question is up, so nothing competes with reading it.
  private var depth: Double {
    switch mood {
    case .question: 0.8
    case .idle: 0.68
    case .correct, .wrong, .missed: 0.58
    case .celebrate: 0.52
    }
  }

  private var colors: [Color] {
    let ink = theme.ink
    let crown = glow.mix(with: ink, by: depth)
    let shoulder = glow.mix(with: ink, by: min(1, depth + 0.14))
    let floor = glow.mix(with: ink, by: min(1, depth + 0.24))
    return [
      shoulder, crown, shoulder,
      ink, ink, ink,
      ink, floor, ink,
    ]
  }
}

/// 1 pt lines on a 4 pt pitch — the texture of the TV's CRT theme, faint enough
/// that it reads as grain under text and as structure under glass.
struct Scanlines: View {
  var body: some View {
    Canvas { context, size in
      var lines = Path()
      var y: CGFloat = 0
      while y < size.height {
        lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
        y += 4
      }
      context.fill(lines, with: .color(.black.opacity(0.32)))
    }
  }
}

nonisolated extension EnvironmentValues {
  /// Whether a backdrop that can follow the phone's tilt does. Off on a TV,
  /// which doesn't tilt.
  @Entry public var backdropFollowsTilt = true
}
