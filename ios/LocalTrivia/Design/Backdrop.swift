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
/// above is Phosphor, the game's own. Holographic's foil is the one texture
/// that moves, following the phone's tilt — and it holds still while a
/// question is up.
struct Backdrop: View {
  enum Mood: Equatable {
    case idle
    case question
    case correct
    case wrong
    case missed
    case celebrate
  }

  /// What the glass has to bend. Each is drawn once and holds still, bar the
  /// holographic foil (`Textures.swift`).
  enum Texture: Equatable {
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
  }

  let mood: Mood
  let accent: Color

  @Environment(\.theme) private var theme
  @Environment(\.backdropFollowsTilt) private var followsTilt
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
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
      texture
      // Falls off toward the edges, like a tube.
      RadialGradient(
        colors: [.clear, .black.opacity(0.55)],
        center: .center,
        startRadius: 180,
        endRadius: 700
      )
    }
    .ignoresSafeArea()
    .animation(reduceMotion ? nil : .easeInOut(duration: 0.9), value: mood)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var texture: some View {
    switch theme.texture {
    case .scanlines: Scanlines()
    case .grid: Graticule(color: accent)
    case .horizon:
      ZStack {
        Horizon(color: accent)
        Scanlines()
      }
    case .dotMatrix: DotMatrix()
    case .brushed: Brushed(color: accent)
    // The one texture that moves — never while a question is up, when
    // nothing may compete with reading it.
    case .holofoil: Holofoil(followsTilt: followsTilt && !reduceMotion && mood != .question)
    case .chalk: ChalkDust()
    }
  }

  private var glow: Color {
    switch mood {
    case .idle, .question: accent
    case .correct: .broadcastGreen
    case .wrong: .broadcastRed
    case .missed: Color(hex: 0x7D8BA0)
    case .celebrate: .broadcastGold
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
private struct Scanlines: View {
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

extension EnvironmentValues {
  /// Whether a foil backdrop catches the light as the phone tilts. Off on a
  /// TV, which doesn't tilt.
  @Entry var backdropFollowsTilt = true
}
