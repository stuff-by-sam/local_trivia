import CoreMotion
import SwiftUI

// The themes' textures (`Backdrop.Texture`), apart from Phosphor's scanlines.
// Each is drawn once and holds still, bar the holographic foil, which follows
// the phone's tilt while it may.

/// Cobalt's texture: hairlines on a 22 pt square pitch, faint enough to read as
/// the glass's structure rather than a pattern of its own.
struct Graticule: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      var lines = Path()
      let pitch: CGFloat = 22
      var x = pitch / 2
      while x < size.width {
        lines.addRect(CGRect(x: x, y: 0, width: 1, height: size.height))
        x += pitch
      }
      var y = pitch / 2
      while y < size.height {
        lines.addRect(CGRect(x: 0, y: y, width: size.width, height: 1))
        y += pitch
      }
      context.fill(lines, with: .color(color.opacity(0.07)))
    }
  }
}

/// Synthwave's texture: a floor grid running to a horizon just below the
/// middle of the screen, brightest nearest the viewer.
struct Horizon: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      let horizon = size.height * 0.64
      let depth = size.height - horizon
      let vanishing = CGPoint(x: size.width / 2, y: horizon)
      var lines = Path()
      // Rungs crowd together toward the horizon, as they would in perspective.
      let rungs = 12
      for rung in 1...rungs {
        let t = Double(rung) / Double(rungs)
        let y = horizon + depth * t * t
        lines.move(to: CGPoint(x: 0, y: y))
        lines.addLine(to: CGPoint(x: size.width, y: y))
      }
      // Rails fan out from the vanishing point past both edges.
      let rails = 18
      for rail in 0...rails {
        let x = size.width * (-1 + 3 * Double(rail) / Double(rails))
        lines.move(to: vanishing)
        lines.addLine(to: CGPoint(x: x, y: size.height))
      }
      context.stroke(
        lines,
        with: .linearGradient(
          Gradient(colors: [color.opacity(0), color.opacity(0.22)]),
          startPoint: vanishing,
          endPoint: CGPoint(x: size.width / 2, y: size.height)
        ),
        lineWidth: 1
      )
    }
  }
}

/// Noir's texture: the scanlines, crossed. Over the glow it reads as a screen
/// of dots; over bare ink it vanishes, as the scanlines do.
struct DotMatrix: View {
  var body: some View {
    Canvas { context, size in
      var mesh = Path()
      var y: CGFloat = 0
      while y < size.height {
        mesh.addRect(CGRect(x: 0, y: y, width: size.width, height: 1.25))
        y += 4
      }
      var x: CGFloat = 0
      while x < size.width {
        mesh.addRect(CGRect(x: x, y: 0, width: 1.25, height: size.height))
        x += 4
      }
      context.fill(mesh, with: .color(.black.opacity(0.4)))
    }
  }
}

/// Gold's texture: hairline streaks running across the screen, some catching
/// the light and some in shadow, like brushed metal.
struct Brushed: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      var random = Seeded(0x601D)
      var light = Path()
      var shadow = Path()
      var y: CGFloat = 0
      while y < size.height {
        let length = size.width * CGFloat.random(in: 0.25...0.9, using: &random)
        let x = CGFloat.random(in: -0.2...1, using: &random) * size.width
        let streak = CGRect(x: x, y: y, width: length, height: 0.75)
        if Bool.random(using: &random) { light.addRect(streak) } else { shadow.addRect(streak) }
        y += CGFloat.random(in: 1.5...3.5, using: &random)
      }
      context.fill(light, with: .color(color.opacity(0.06)))
      context.fill(shadow, with: .color(.black.opacity(0.25)))
    }
  }
}

/// Chalkboard's texture: the broad, soft smears an eraser leaves, and a
/// scatter of chalk dust.
struct ChalkDust: View {
  var body: some View {
    Canvas { context, size in
      var random = Seeded(0xC4A1)
      context.drawLayer { smears in
        smears.addFilter(.blur(radius: 18))
        for _ in 0..<5 {
          let y = CGFloat.random(in: 0...1, using: &random) * size.height
          let start = CGPoint(x: CGFloat.random(in: -0.2...0.3, using: &random) * size.width, y: y)
          let end = CGPoint(x: CGFloat.random(in: 0.6...1.2, using: &random) * size.width, y: y + CGFloat.random(in: -60...60, using: &random))
          let control = CGPoint(x: (start.x + end.x) / 2, y: y + CGFloat.random(in: -90...90, using: &random))
          var smear = Path()
          smear.move(to: start)
          smear.addQuadCurve(to: end, control: control)
          let width = CGFloat.random(in: 50...110, using: &random)
          smears.stroke(smear, with: .color(.white.opacity(0.035)), style: StrokeStyle(lineWidth: width, lineCap: .round))
        }
      }
      var dust = Path()
      for _ in 0..<Int(size.width * size.height / 900) {
        let speck = CGFloat.random(in: 0.6...1.6, using: &random)
        let x = CGFloat.random(in: 0...1, using: &random) * size.width
        let y = CGFloat.random(in: 0...1, using: &random) * size.height
        dust.addEllipse(in: CGRect(x: x, y: y, width: speck, height: speck))
      }
      context.fill(dust, with: .color(.white.opacity(0.07)))
    }
  }
}

/// Holographic's texture: an iridescent sheen that slides across the ink as
/// the phone tilts, the way foil catches the light, over fine diffraction
/// lines.
///
/// Only the sheen redraws, and only while it's following the phone: never
/// under Reduce Motion, while a question is up, on a TV, or with the app in
/// the background. Otherwise it rests where a level phone would put it.
struct Holofoil: View {
  let followsTilt: Bool

  @Environment(\.scenePhase) private var scenePhase
  @State private var isWatching = false

  /// The holographic icon's sweep, back round to where it started.
  private static var foil: [Color] {
    [0xFF8AD8, 0xB69CFF, 0x7FE3FF, 0xA6FFCB, 0xFFD59A, 0xFF8AD8].map(Color.init(hex:))
  }

  var body: some View {
    let isLive = followsTilt && scenePhase == .active && Tilt.shared.isAvailable
    ZStack {
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !isLive)) { _ in
        sheen(isLive ? Tilt.shared.angles : .level)
      }
      Diffraction()
    }
    .onAppear { watch(isLive) }
    .onChange(of: isLive) { _, live in watch(live) }
    .onDisappear { watch(false) }
  }

  /// Rolling the phone slides the bands sideways; tipping it slides them up
  /// and down. Strongest at the top, calmer where the controls sit.
  private func sheen(_ tilt: Tilt.Angles) -> some View {
    let across = CGFloat(sin(tilt.roll)) * 0.9
    let down = CGFloat(sin(tilt.pitch - Tilt.Angles.level.pitch)) * 0.6
    return LinearGradient(
      colors: Self.foil,
      startPoint: UnitPoint(x: -0.6 + across, y: -0.2 + down),
      endPoint: UnitPoint(x: 1.2 + across, y: 1 + down)
    )
    .opacity(0.26)
    .blendMode(.screen)
    .mask(LinearGradient(colors: [.white, .white.opacity(0.35)], startPoint: .top, endPoint: .bottom))
  }

  private func watch(_ live: Bool) {
    guard live != isWatching else { return }
    isWatching = live
    if live { Tilt.shared.watch() } else { Tilt.shared.unwatch() }
  }
}

/// Hairlines at 45°, 3 pt apart: the grain of holographic foil.
struct Diffraction: View {
  var body: some View {
    Canvas { context, size in
      var lines = Path()
      var x = -size.height
      while x < size.width {
        lines.move(to: CGPoint(x: x, y: size.height))
        lines.addLine(to: CGPoint(x: x + size.height, y: 0))
        x += 3
      }
      context.stroke(lines, with: .color(.white.opacity(0.03)), lineWidth: 0.5)
    }
  }
}

/// Which way the phone's tilted, for foil that catches the light.
///
/// One motion manager for the app, as Core Motion asks, and it runs only
/// while a foil backdrop is on screen and following the phone. Device motion
/// needs no permission.
final class Tilt {
  struct Angles {
    var roll: Double
    var pitch: Double

    /// Held the way a phone usually is: upright, tipped back a little.
    static let level = Angles(roll: 0, pitch: 0.7)
  }

  static let shared = Tilt()

  private let motion = CMMotionManager()
  private var watchers = 0

  var isAvailable: Bool { motion.isDeviceMotionAvailable }

  var angles: Angles {
    guard let attitude = motion.deviceMotion?.attitude else { return .level }
    return Angles(roll: attitude.roll, pitch: attitude.pitch)
  }

  func watch() {
    watchers += 1
    guard watchers == 1, motion.isDeviceMotionAvailable else { return }
    motion.deviceMotionUpdateInterval = 1.0 / 30
    motion.startDeviceMotionUpdates()
  }

  func unwatch() {
    guard watchers > 0 else { return }
    watchers -= 1
    if watchers == 0 { motion.stopDeviceMotionUpdates() }
  }
}

/// The same "random" numbers every time, so a texture drawn from them is the
/// same texture on every redraw. (SplitMix64.)
struct Seeded: RandomNumberGenerator {
  private var state: UInt64

  init(_ seed: UInt64) { state = seed }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var z = state
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }
}
