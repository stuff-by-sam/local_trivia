import CoreMotion
import Observation
import SwiftUI

// The themes' textures (`Backdrop.Texture`), apart from Phosphor's scanlines.
// Each is drawn once and holds still, bar Holographic's foil, Glass's liquid
// and Titanium's shine, which follow the phone's tilt while they may
// (`TiltFollowing`).

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
  /// How strongly the streaks catch the light, and how dark their shadows.
  var light = 0.06
  var shadow = 0.25

  var body: some View {
    Canvas { context, size in
      var random = Seeded(0x601D)
      var lit = Path()
      var shaded = Path()
      var y: CGFloat = 0
      while y < size.height {
        let length = size.width * CGFloat.random(in: 0.25...0.9, using: &random)
        let x = CGFloat.random(in: -0.2...1, using: &random) * size.width
        let streak = CGRect(x: x, y: y, width: length, height: 0.75)
        if Bool.random(using: &random) { lit.addRect(streak) } else { shaded.addRect(streak) }
        y += CGFloat.random(in: 1.5...3.5, using: &random)
      }
      context.fill(lit, with: .color(color.opacity(light)))
      context.fill(shaded, with: .color(.black.opacity(shadow)))
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
struct Holofoil: View {
  let followsTilt: Bool

  /// The holographic icon's sweep, back round to where it started.
  private static var foil: [Color] {
    [0xFF8AD8, 0xB69CFF, 0x7FE3FF, 0xA6FFCB, 0xFFD59A, 0xFF8AD8].map(Color.init(hex:))
  }

  var body: some View {
    ZStack {
      TiltFollowing(followsTilt: followsTilt) { sheen($0) }
      Diffraction()
    }
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

/// Glass's texture: pools of liquid colour — sky, indigo, violet — for the
/// glass controls to refract, running downhill as the phone tilts. Each pool
/// runs its own distance, so they slide past one another. A cool family, clear
/// of the answer colours, so no answer's glass picks up another's hue. Half as
/// bright while a question is up.
struct LiquidPools: View {
  let followsTilt: Bool
  let isQuiet: Bool

  private struct Pool {
    let color: UInt32
    /// Where it rests, as a fraction of the screen, and its width, as a
    /// fraction of the screen's.
    let x: CGFloat, y: CGFloat, size: CGFloat
    /// How far it runs when the phone tilts.
    let drift: CGFloat
  }

  private static var pools: [Pool] {
    [
      Pool(color: 0x3FB6F0, x: 0.12, y: 0.2, size: 1.1, drift: 1),
      Pool(color: 0x5B6BFF, x: 0.92, y: 0.36, size: 1, drift: 0.6),
      Pool(color: 0x9A6BFF, x: 0.3, y: 0.74, size: 1.2, drift: 1.4),
      Pool(color: 0x7FA8FF, x: 0.95, y: 0.92, size: 0.9, drift: 0.8),
    ]
  }

  var body: some View {
    GeometryReader { proxy in
      TiltFollowing(followsTilt: followsTilt) { tilt in
        let run = CGSize(
          width: CGFloat(sin(tilt.roll)) * 90,
          height: CGFloat(sin(tilt.pitch - Tilt.Angles.level.pitch)) * 90)
        ZStack {
          ForEach(Array(Self.pools.enumerated()), id: \.offset) { _, pool in
            let size = proxy.size.width * pool.size
            let color = Color(hex: pool.color)
            Circle()
              .fill(RadialGradient(colors: [color.opacity(0.5), color.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
              .frame(width: size, height: size)
              .position(
                x: proxy.size.width * pool.x + run.width * pool.drift,
                y: proxy.size.height * pool.y + run.height * pool.drift)
          }
          // The pane itself, catching the light along its top.
          LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: UnitPoint(x: 0.5, y: 0.3))
        }
      }
    }
    .opacity(isQuiet ? 0.5 : 1)
    .blendMode(.screen)
  }
}

/// Titanium's texture: brushed metal, lit from above — brighter, harsher
/// streaks than Gold's — and a band of light across it that slides and leans
/// as the phone tilts, the way metal catches a window.
struct BrushedMetal: View {
  let color: Color
  let followsTilt: Bool

  var body: some View {
    ZStack {
      Brushed(color: color, light: 0.1, shadow: 0.32)
      TiltFollowing(followsTilt: followsTilt) { shine($0) }
    }
  }

  private func shine(_ tilt: Tilt.Angles) -> some View {
    let lean = CGFloat(sin(tilt.roll)) * 0.35
    let middle = 0.28 + CGFloat(sin(tilt.pitch - Tilt.Angles.level.pitch)) * 0.5
    func at(_ location: CGFloat) -> CGFloat { min(max(location, 0), 1) }
    return LinearGradient(
      stops: [
        .init(color: .clear, location: at(middle - 0.14)),
        .init(color: .white.opacity(0.12), location: at(middle)),
        .init(color: .clear, location: at(middle + 0.14)),
      ],
      startPoint: UnitPoint(x: 0.5 - lean, y: 0),
      endPoint: UnitPoint(x: 0.5 + lean, y: 1)
    )
    .blendMode(.screen)
  }
}

/// Draws `content` from the phone's tilt, for the textures that follow it.
///
/// Only `content` redraws, and only when the phone actually moves (`Tilt`
/// publishes changes past sensor noise): a phone lying on a table draws
/// nothing. Never under Reduce Motion, while a question is up, on a TV (the
/// backdrop decides those, through `followsTilt`), or with the app in the
/// background. Otherwise it rests where a level phone would put it.
struct TiltFollowing<Content: View>: View {
  let followsTilt: Bool
  @ViewBuilder var content: (Tilt.Angles) -> Content

  @Environment(\.scenePhase) private var scenePhase
  @State private var isWatching = false

  var body: some View {
    let isLive = followsTilt && scenePhase == .active && Tilt.shared.isAvailable
    content(isLive ? Tilt.shared.angles : .level)
      .onAppear { watch(isLive) }
      .onChange(of: isLive) { _, live in watch(live) }
      .onDisappear { watch(false) }
  }

  private func watch(_ live: Bool) {
    guard live != isWatching else { return }
    isWatching = live
    if live { Tilt.shared.watch() } else { Tilt.shared.unwatch() }
  }
}

/// Which way the phone's tilted, for textures that catch the light.
///
/// One motion manager for the app, as Core Motion asks, and it runs only
/// while a texture on screen is following the phone. Device motion needs no
/// permission. Readings arrive at 30 Hz but only a real movement is
/// published, so a still phone costs no redraws.
@Observable
final class Tilt {
  struct Angles: Equatable {
    var roll: Double
    var pitch: Double

    /// Held the way a phone usually is: upright, tipped back a little.
    static let level = Angles(roll: 0, pitch: 0.7)
  }

  static let shared = Tilt()

  /// Smaller changes than this — about 0.7° — are sensor noise, not a tilt.
  static let threshold = 0.012

  private(set) var angles = Angles.level

  @ObservationIgnored private let motion = CMMotionManager()
  @ObservationIgnored private var watchers = 0

  var isAvailable: Bool { motion.isDeviceMotionAvailable }

  func watch() {
    watchers += 1
    guard watchers == 1, motion.isDeviceMotionAvailable else { return }
    motion.deviceMotionUpdateInterval = 1.0 / 30
    motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
      guard let attitude = data?.attitude else { return }
      let next = Angles(roll: attitude.roll, pitch: attitude.pitch)
      MainActor.assumeIsolated { self?.update(next) }
    }
  }

  func unwatch() {
    guard watchers > 0 else { return }
    watchers -= 1
    if watchers == 0 { motion.stopDeviceMotionUpdates() }
  }

  private func update(_ next: Angles) {
    guard abs(next.roll - angles.roll) > Self.threshold || abs(next.pitch - angles.pitch) > Self.threshold else { return }
    angles = next
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
