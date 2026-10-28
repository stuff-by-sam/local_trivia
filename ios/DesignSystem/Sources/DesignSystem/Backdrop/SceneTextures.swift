import SwiftUI

// The scene themes' textures: Aurora's sky, Ember's campfire, Sakura's
// blossom, Abyss's deep water and Circuit's board. Each is drawn once, from
// seeded numbers, so it's the same picture on every redraw. The ones that
// follow the phone's tilt move what's drawn — an offset, a layer sliding over
// another — and never redraw it, so a phone in the hand costs the compositor
// a little and the CPU nothing (`TiltFollowing`).
//
// Each keeps its colour where the game's isn't: the sky above the question,
// a glow below the answers, faint enough under the glass that no answer's
// colour reads as another's. The bright ones go half as bright while a
// question is up.

// MARK: - Aurora

/// Aurora's texture: curtains of northern light hanging across the sky —
/// violet behind, teal, and green nearest — each a fringe of rays rising
/// from a bright, wavering hem. They sway as the phone tilts.
struct Aurora: View {
  let followsTilt: Bool
  let isQuiet: Bool

  var body: some View {
    GeometryReader { proxy in
      TiltFollowing(followsTilt: followsTilt) { tilt in
        AuroraCurtains()
          // Wider than what it's drawn on, so swaying never shows an edge.
          .frame(width: proxy.size.width * (1 + 2 * Self.reach))
          .offset(
            x: CGFloat(sin(tilt.roll)) * proxy.size.width * Self.reach * 0.8,
            y: CGFloat(sin(tilt.pitch - Tilt.Angles.level.pitch)) * proxy.size.height * 0.04)
          .frame(width: proxy.size.width, height: proxy.size.height)
      }
    }
    .opacity(isQuiet ? 0.5 : 1)
    .blendMode(.screen)
    .allowsHitTesting(false)
  }

  /// How far past each side the curtains hang, as a share of the width.
  private static let reach: CGFloat = 0.15
}

private struct AuroraCurtains: View {
  private struct Curtain {
    let color: UInt32
    /// Where its hem hangs, as a share of the height, and how far it wavers.
    let hem: CGFloat
    let sway: CGFloat
    /// Its rays' longest, as a share of the height.
    let rays: CGFloat
    /// Waves across the screen, and where they start.
    let waves: CGFloat
    let phase: CGFloat
    let brightness: Double
  }

  private static var curtains: [Curtain] {
    [
      Curtain(color: 0x9D7BFF, hem: 0.15, sway: 0.025, rays: 0.11, waves: 1.6, phase: 0.6, brightness: 0.3),
      Curtain(color: 0x3FE6D2, hem: 0.22, sway: 0.035, rays: 0.14, waves: 1.15, phase: 2.1, brightness: 0.34),
      Curtain(color: 0x5CFFA8, hem: 0.29, sway: 0.04, rays: 0.17, waves: 0.85, phase: 4, brightness: 0.4),
    ]
  }

  var body: some View {
    Canvas { context, size in
      var random = Seeded(0xA0C4)
      for curtain in Self.curtains {
        let color = Color(hex: curtain.color)
        func hem(_ x: CGFloat) -> CGFloat {
          let t = x / max(size.width, 1)
          let wave = sin(2 * .pi * curtain.waves * t + curtain.phase)
          let ripple = sin(2 * .pi * curtain.waves * 2.7 * t + curtain.phase * 1.7)
          return size.height * (curtain.hem + curtain.sway * (wave + 0.4 * ripple))
        }
        // The rays: brightest at the hem, fading as they rise, each its own
        // brightness — the curtain's folds — and swelling in bands along it.
        context.drawLayer { rays in
          rays.addFilter(.blur(radius: 2))
          var x: CGFloat = 0
          while x <= size.width {
            let foot = CGPoint(x: x, y: hem(x))
            let band = 0.5 + 0.5 * sin(x / max(size.width, 1) * 2 * .pi * 3.1 + curtain.phase)
            let swell = band * band
            let length = size.height * curtain.rays * (0.4 + 0.6 * swell) * CGFloat.random(in: 0.75...1.2, using: &random)
            let top = CGPoint(x: x, y: foot.y - length)
            var ray = Path()
            ray.move(to: foot)
            ray.addLine(to: top)
            let fold = Double.random(in: 0.35...1, using: &random)
            let glow = color.opacity(curtain.brightness * fold * (0.45 + 0.55 * Double(swell)))
            rays.stroke(ray, with: .linearGradient(Gradient(colors: [glow, glow.opacity(0)]), startPoint: foot, endPoint: top), lineWidth: 2)
            x += 2.5
          }
        }
        // The hem: the curtain's bright lower edge.
        var edge = Path()
        edge.move(to: CGPoint(x: 0, y: hem(0)))
        var x: CGFloat = 4
        while x < size.width + 4 {
          edge.addLine(to: CGPoint(x: x, y: hem(x)))
          x += 4
        }
        context.drawLayer { hemLayer in
          hemLayer.addFilter(.blur(radius: 2))
          hemLayer.stroke(edge, with: .color(color.opacity(curtain.brightness * 0.8)), lineWidth: 1.5)
        }
      }
    }
  }
}

// MARK: - Ember

/// Ember's texture: a campfire's glow coming up over the foot of the screen,
/// and sparks rising from it — thickest low down, fewer and fainter as they
/// climb, some trailing a streak.
struct Embers: View {
  let isQuiet: Bool

  var body: some View {
    Sparks()
      .opacity(isQuiet ? 0.5 : 1)
      .blendMode(.screen)
      .allowsHitTesting(false)
  }
}

private struct Sparks: View {
  /// White-hot to the orange of the coals.
  private static var hot: Color { Color(hex: 0xFFD9A0) }
  private static var coal: Color { Color(hex: 0xFF7A3D) }

  var body: some View {
    Canvas { context, size in
      var random = Seeded(0xE3B5)
      // The fire, below the screen: its glow comes up over the edge.
      let fire = CGPoint(x: size.width / 2, y: size.height * 1.08)
      context.fill(
        Path(CGRect(origin: .zero, size: size)),
        with: .radialGradient(
          Gradient(colors: [Self.coal.opacity(0.2), Self.coal.opacity(0.06), Self.coal.opacity(0)]),
          center: fire, startRadius: 0, endRadius: max(size.width, size.height) * 0.55))

      let count = max(6, Int(size.width * size.height / 5200))
      let sparks = (0..<count).map { _ in Spark(&random, in: size) }
      // Each glows: a soft halo, then its point and the streak it trails.
      context.drawLayer { halos in
        halos.addFilter(.blur(radius: 3))
        for spark in sparks {
          halos.fill(Path(ellipseIn: spark.rect(scale: 3.5)), with: .color(spark.color.opacity(spark.brightness * 0.4)))
        }
      }
      for spark in sparks {
        // A streak below a rising spark, where it's just been.
        if spark.trail > 0 {
          var streak = Path()
          let tail = CGPoint(x: spark.center.x - spark.drift, y: spark.center.y + spark.trail)
          streak.move(to: spark.center)
          streak.addLine(to: tail)
          context.stroke(
            streak,
            with: .linearGradient(
              Gradient(colors: [spark.color.opacity(spark.brightness * 0.7), spark.color.opacity(0)]),
              startPoint: spark.center, endPoint: tail),
            style: StrokeStyle(lineWidth: spark.radius, lineCap: .round))
        }
        context.fill(Path(ellipseIn: spark.rect(scale: 1)), with: .color(spark.color.opacity(spark.brightness)))
      }
    }
  }

  private struct Spark {
    let center: CGPoint
    let radius: CGFloat
    let color: Color
    let brightness: Double
    let trail: CGFloat
    let drift: CGFloat

    init(_ random: inout Seeded, in size: CGSize) {
      // Most near the fire; a few have climbed most of the way up.
      let climb = pow(CGFloat.random(in: 0...1, using: &random), 1.7)
      center = CGPoint(x: CGFloat.random(in: 0...1, using: &random) * size.width, y: size.height * (1 - 0.95 * climb))
      radius = CGFloat.random(in: 0.6...1.5, using: &random) * (1.1 - 0.5 * climb)
      color = Sparks.hot.mix(with: Sparks.coal, by: Double.random(in: 0.2...1, using: &random))
      brightness = 0.85 * (1 - 0.7 * Double(climb))
      trail = Bool.random(using: &random) ? CGFloat.random(in: 6...18, using: &random) : 0
      drift = CGFloat.random(in: -4...4, using: &random)
    }

    func rect(scale: CGFloat) -> CGRect {
      CGRect(x: center.x - radius * scale, y: center.y - radius * scale, width: 2 * radius * scale, height: 2 * radius * scale)
    }
  }
}

// MARK: - Sakura

/// Sakura's texture: cherry blossom overhead, a blush in the top corners, and
/// petals drifting down through the night — far ones small, soft and dim,
/// near ones larger. The two depths part as the phone tilts, near ones more.
struct Blossom: View {
  let followsTilt: Bool

  var body: some View {
    ZStack {
      Canopy()
      Parallax(followsTilt: followsTilt) {
        Petals(isNear: false)
      } near: {
        Petals(isNear: true)
      }
      .blendMode(.screen)
    }
    .allowsHitTesting(false)
  }
}

private struct Canopy: View {
  var body: some View {
    Canvas { context, size in
      let blush = Color(hex: 0xFF9CC2)
      for corner in [CGPoint(x: 0, y: 0), CGPoint(x: size.width, y: 0)] {
        context.fill(
          Path(CGRect(origin: .zero, size: size)),
          with: .radialGradient(
            Gradient(colors: [blush.opacity(0.11), blush.opacity(0)]),
            center: corner, startRadius: 0, endRadius: max(size.width, size.height) * 0.42))
      }
    }
  }
}

private struct Petals: View {
  let isNear: Bool

  var body: some View {
    Canvas { context, size in
      var random = Seeded(isNear ? 0x5A4C : 0x5A4D)
      let count = max(3, Int(size.width * size.height / (isNear ? 15000 : 9000)))
      let pink = Color(hex: 0xFFA3C8)
      let pale = Color(hex: 0xFFD6E6)
      context.drawLayer { layer in
        if !isNear { layer.addFilter(.blur(radius: 1.2)) }
        for _ in 0..<count {
          let length = CGFloat.random(in: isNear ? 10...16 : 5...9, using: &random)
          let place = CGAffineTransform(
            translationX: CGFloat.random(in: 0...1, using: &random) * size.width,
            y: CGFloat.random(in: 0...1, using: &random) * size.height
          )
          .rotated(by: CGFloat.random(in: 0...(2 * .pi), using: &random))
          .scaledBy(x: length, y: length)
          let color = Bool.random(using: &random) ? pink : pale
          let opacity = isNear ? Double.random(in: 0.26...0.44, using: &random) : Double.random(in: 0.12...0.22, using: &random)
          layer.fill(Self.petal.applying(place), with: .color(color.opacity(opacity)))
        }
      }
    }
  }

  /// A cherry blossom petal a unit long, its base at the origin: broad, with
  /// the notch at its tip that sets a cherry's apart.
  private static var petal: Path {
    var path = Path()
    path.move(to: .zero)
    path.addCurve(to: CGPoint(x: -0.1, y: -1), control1: CGPoint(x: -0.55, y: -0.25), control2: CGPoint(x: -0.5, y: -0.92))
    path.addLine(to: CGPoint(x: 0, y: -0.84))
    path.addLine(to: CGPoint(x: 0.1, y: -1))
    path.addCurve(to: .zero, control1: CGPoint(x: 0.5, y: -0.92), control2: CGPoint(x: 0.55, y: -0.25))
    path.closeSubpath()
    return path
  }
}

// MARK: - Abyss

/// Abyss's texture: daylight rippling down through deep water — a net of
/// caustic light near the surface, a few shafts slanting down from it — and
/// specks of plankton glowing in the dark, at two depths that drift apart as
/// the phone tilts.
struct DeepWater: View {
  let followsTilt: Bool
  let isQuiet: Bool

  var body: some View {
    ZStack {
      Surface()
      Parallax(followsTilt: followsTilt) {
        Plankton(isNear: false)
      } near: {
        Plankton(isNear: true)
      }
    }
    .opacity(isQuiet ? 0.5 : 1)
    .blendMode(.screen)
    .allowsHitTesting(false)
  }
}

private struct Surface: View {
  private static var light: Color { Color(hex: 0x6FD8FF) }

  var body: some View {
    Canvas { context, size in
      var random = Seeded(0xAB55)
      let depth = size.height * 0.4
      // The surface, far above, lighting the top of the water.
      context.fill(
        Path(CGRect(x: 0, y: 0, width: size.width, height: depth)),
        with: .linearGradient(
          Gradient(colors: [Self.light.opacity(0.1), Self.light.opacity(0)]),
          startPoint: .zero, endPoint: CGPoint(x: 0, y: depth)))

      // Shafts of light, slanting down from it.
      context.drawLayer { shafts in
        shafts.addFilter(.blur(radius: 14))
        for _ in 0..<4 {
          let x = CGFloat.random(in: 0.05...0.95, using: &random) * size.width
          let width = CGFloat.random(in: 0.04...0.09, using: &random) * size.width
          let slant = size.width * 0.18
          let reach = size.height * CGFloat.random(in: 0.5...0.75, using: &random)
          var shaft = Path()
          shaft.move(to: CGPoint(x: x - width / 2, y: 0))
          shaft.addLine(to: CGPoint(x: x + width / 2, y: 0))
          shaft.addLine(to: CGPoint(x: x + width * 1.6 + slant, y: reach))
          shaft.addLine(to: CGPoint(x: x - width * 1.6 + slant, y: reach))
          shaft.closeSubpath()
          shafts.fill(
            shaft,
            with: .linearGradient(
              Gradient(colors: [Self.light.opacity(0.12), Self.light.opacity(0)]),
              startPoint: CGPoint(x: x, y: 0), endPoint: CGPoint(x: x + slant, y: reach)))
        }
      }

      // Caustics: the net of light the ripples focus on the water — the
      // zero line of a field of crossing, warping waves, traced cell by cell
      // (marching squares) — brightest near the surface, fading with depth.
      context.drawLayer { caustics in
        caustics.addFilter(.blur(radius: 0.9))
        let step: CGFloat = 4
        let columns = Int(size.width / step) + 2
        let rows = Int(depth / step) + 1
        var field = [Double](repeating: 0, count: columns * rows)
        for row in 0..<rows {
          for column in 0..<columns {
            field[row * columns + column] = Self.ripple(Double(column) * step, Double(row) * step)
          }
        }
        let bands = 8
        var nets = Array(repeating: Path(), count: bands)
        for row in 0..<(rows - 1) {
          let band = min(bands - 1, row * bands / max(rows - 1, 1))
          for column in 0..<(columns - 1) {
            let corners = [
              (CGPoint(x: CGFloat(column) * step, y: CGFloat(row) * step), field[row * columns + column]),
              (CGPoint(x: CGFloat(column + 1) * step, y: CGFloat(row) * step), field[row * columns + column + 1]),
              (CGPoint(x: CGFloat(column + 1) * step, y: CGFloat(row + 1) * step), field[(row + 1) * columns + column + 1]),
              (CGPoint(x: CGFloat(column) * step, y: CGFloat(row + 1) * step), field[(row + 1) * columns + column]),
            ]
            // Where the line crosses each side of the cell.
            var crossings: [CGPoint] = []
            for side in 0..<4 {
              let (a, va) = corners[side]
              let (b, vb) = corners[(side + 1) % 4]
              guard (va < 0) != (vb < 0) else { continue }
              let t = CGFloat(va / (va - vb))
              crossings.append(CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
            }
            var index = 0
            while index + 1 < crossings.count {
              nets[band].move(to: crossings[index])
              nets[band].addLine(to: crossings[index + 1])
              index += 2
            }
          }
        }
        for (band, net) in nets.enumerated() {
          let fade = 0.2 * (1 - Double(band) / Double(bands))
          caustics.stroke(net, with: .color(Self.light.opacity(fade)), lineWidth: 1.2)
        }
      }
    }
  }

  /// Waves crossing, each warped by the other, and a third across them both
  /// to break the pattern up: where it's zero, the light's focused.
  private static func ripple(_ x: Double, _ y: Double) -> Double {
    sin(x * 0.12 + 1.6 * sin(y * 0.085)) + sin(y * 0.13 + 1.4 * sin(x * 0.073 + 0.7)) + 0.55 * sin((x - y) * 0.066 + 2.1)
  }
}

private struct Plankton: View {
  let isNear: Bool

  var body: some View {
    Canvas { context, size in
      var random = Seeded(isNear ? 0x91A1 : 0x91A2)
      let count = max(6, Int(size.width * size.height / (isNear ? 9000 : 4500)))
      let colors = [0x7DF9FF, 0x5CC4FF, 0x6BFFD8].map(Color.init(hex:))
      var specks: [(CGRect, Color, Double)] = []
      for _ in 0..<count {
        let radius = CGFloat.random(in: isNear ? 0.9...1.8 : 0.5...1, using: &random)
        let center = CGPoint(x: CGFloat.random(in: 0...1, using: &random) * size.width, y: CGFloat.random(in: 0...1, using: &random) * size.height)
        let color = colors[Int.random(in: 0..<colors.count, using: &random)]
        let brightness = isNear ? Double.random(in: 0.45...0.85, using: &random) : Double.random(in: 0.2...0.45, using: &random)
        specks.append((CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius), color, brightness))
      }
      // Each glows: a soft halo, then its point.
      context.drawLayer { halos in
        halos.addFilter(.blur(radius: isNear ? 4 : 2.5))
        for (rect, color, brightness) in specks {
          halos.fill(Path(ellipseIn: rect.insetBy(dx: -rect.width * 1.5, dy: -rect.height * 1.5)), with: .color(color.opacity(brightness * 0.5)))
        }
      }
      for (rect, color, brightness) in specks {
        context.fill(Path(ellipseIn: rect), with: .color(color.opacity(brightness)))
      }
    }
  }
}

/// Two layers of a scene, far and near, that part as the phone tilts — the
/// near one further — by as much of the screen as they're drawn on, so a
/// swatch moves as a screen does. Each is drawn a little larger than its
/// frame, so moving never shows an edge.
private struct Parallax<Far: View, Near: View>: View {
  let followsTilt: Bool
  @ViewBuilder var far: Far
  @ViewBuilder var near: Near

  var body: some View {
    GeometryReader { proxy in
      let side = max(proxy.size.width, proxy.size.height)
      TiltFollowing(followsTilt: followsTilt) { tilt in
        let roll = CGFloat(sin(tilt.roll))
        let pitch = CGFloat(sin(tilt.pitch - Tilt.Angles.level.pitch))
        ZStack {
          far
            .offset(x: roll * side * 0.008, y: pitch * side * 0.006)
          near
            .offset(x: roll * side * 0.022, y: pitch * side * 0.016)
        }
        .padding(-side * 0.03)
      }
    }
  }
}

// MARK: - Circuit

/// Circuit's texture: the board behind the screen — traces on a grid,
/// running straight and turning through 45° bends from pad to pad, as a
/// circuit board's are — faint, with a few lit by a signal.
struct Traces: View {
  let color: Color

  var body: some View {
    Canvas { context, size in
      var random = Seeded(0xC1C7)
      let pitch: CGFloat = 16
      let columns = max(1, Int(size.width / pitch))
      let rows = max(1, Int(size.height / pitch))
      let count = max(4, Int(size.width * size.height / 3800))
      let headings = [(1, 0), (0, 1), (-1, 0), (0, -1)]
      var traces = Path()
      var lit = Path()
      var pads = Path()
      func pad(at point: CGPoint, radius: CGFloat = 2.6) {
        pads.addEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: 2 * radius, height: 2 * radius))
      }
      for index in 0..<count {
        var point = CGPoint(x: CGFloat(Int.random(in: 0...columns, using: &random)) * pitch, y: CGFloat(Int.random(in: 0...rows, using: &random)) * pitch)
        var heading = headings[Int.random(in: 0..<headings.count, using: &random)]
        var trace = Path()
        trace.move(to: point)
        pad(at: point)
        for _ in 0..<Int.random(in: 1...3, using: &random) {
          // A straight run, then a 45° bend onto a new heading.
          let run = CGFloat(Int.random(in: 2...7, using: &random)) * pitch
          point = CGPoint(x: point.x + CGFloat(heading.0) * run, y: point.y + CGFloat(heading.1) * run)
          trace.addLine(to: point)
          let turn = Bool.random(using: &random) ? (-heading.1, heading.0) : (heading.1, -heading.0)
          point = CGPoint(x: point.x + CGFloat(heading.0 + turn.0) * pitch, y: point.y + CGFloat(heading.1 + turn.1) * pitch)
          trace.addLine(to: point)
          heading = turn
        }
        let run = CGFloat(Int.random(in: 1...4, using: &random)) * pitch
        point = CGPoint(x: point.x + CGFloat(heading.0) * run, y: point.y + CGFloat(heading.1) * run)
        trace.addLine(to: point)
        pad(at: point)
        if index % 7 == 3 { lit.addPath(trace) } else { traces.addPath(trace) }
      }
      // Vias, scattered between.
      for _ in 0..<max(2, count / 3) {
        pad(at: CGPoint(x: CGFloat(Int.random(in: 0...columns, using: &random)) * pitch, y: CGFloat(Int.random(in: 0...rows, using: &random)) * pitch), radius: 1.8)
      }
      let line = StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
      context.stroke(traces, with: .color(color.opacity(0.075)), style: line)
      context.stroke(pads, with: .color(color.opacity(0.12)), lineWidth: 1.2)
      // The signal: lit traces, glowing.
      context.drawLayer { glow in
        glow.addFilter(.blur(radius: 3))
        glow.stroke(lit, with: .color(color.opacity(0.32)), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
      }
      context.stroke(lit, with: .color(color.opacity(0.26)), style: line)
    }
    .allowsHitTesting(false)
  }
}
