import SwiftUI

/// The screen behind the glass: near-black, one phosphor glow, faint scanlines.
///
/// Liquid Glass takes its character from what it refracts, so this is the one
/// place colour lives. It's calm on purpose: the glow's hue follows the game
/// (accent while playing, green or red at the reveal, gold on the podium),
/// and the scanlines give the glass texture to bend, the way the TV's CRT
/// theme does. It's static between moods — it only animates when one changes.
struct Backdrop: View {
  enum Mood: Equatable {
    case idle
    case question
    case correct
    case wrong
    case missed
    case celebrate
  }

  let mood: Mood
  let accent: Color

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
        background: .broadcastInk
      )
      Scanlines()
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
    let ink = Color.broadcastInk
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
