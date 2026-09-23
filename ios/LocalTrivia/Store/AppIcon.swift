import SwiftUI

/// The home screen icon: the answer set on its ink, as the classic icon has
/// it, recoloured — one to match each theme. Classic is the app's own; the
/// rest are sold in the shop.
///
/// Each alternate is an Icon Composer file beside the classic one
/// (`AppIcon-Amber.icon`, …), named in the target's alternate app icon
/// setting. `Artwork` draws the same layers, for choosing between them.
enum AppIcon: String, CaseIterable, Identifiable, Sendable {
  case classic, amber, cobalt, synthwave, noir, gold, holographic, chalkboard, glass, titanium

  var id: String { rawValue }

  /// The name iOS knows the icon by; nil for the primary icon.
  var alternateName: String? {
    self == .classic ? nil : "AppIcon-\(rawValue.capitalized)"
  }

  init(alternateName: String?) {
    self = Self.allCases.first { $0.alternateName == alternateName } ?? .classic
  }

  var name: LocalizedStringResource {
    switch self {
    case .classic: "Classic"
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

  /// Nil for the one every phone has.
  var productID: String? {
    self == .classic ? nil : "com.stuffbysam.localtrivia.icon.\(rawValue)"
  }

  /// How the shapes are painted, as the icon's layers paint them.
  enum Paint {
    /// One colour each: circle, triangle, square, diamond.
    case flat([Color])
    /// Every shape carries the whole sweep, each turned its own way, so they
    /// catch the light separately: foil, or metal.
    case sweep([Color])
    /// Clear glass, frosted toward the bottom. On the home screen these are
    /// glass layers, which the system refracts and lights.
    case glass
  }

  var paint: Paint {
    switch self {
    case .classic: .flat([0x56FF8A, 0x55E6FF, 0xFFB347, 0xFF6AD5].map(Color.init(hex:)))
    case .amber: .flat([0xFFB000, 0xFFD066, 0xE08600, 0xFFC233].map(Color.init(hex:)))
    case .cobalt: .flat([0x7C9DFF, 0xA8E0FF, 0x5B6CFF, 0xC9D6FF].map(Color.init(hex:)))
    case .synthwave: .flat([0xFF4FB8, 0x4FE3FF, 0xFF9A3C, 0xC77DFF].map(Color.init(hex:)))
    case .noir: .flat([0xFFFFFF, 0xD6D6D6, 0xA8A8A8, 0xEDEDED].map(Color.init(hex:)))
    case .gold: .flat([0xF5C542, 0xFFE08A, 0xD9A21E, 0xFFD35C].map(Color.init(hex:)))
    case .holographic: .sweep([0xFF8AD8, 0xB69CFF, 0x7FE3FF, 0xA6FFCB, 0xFFD59A].map(Color.init(hex:)))
    case .chalkboard: .flat([0xF4F1E6, 0xA8D8F0, 0xFFF0A0, 0xFFB8C8].map(Color.init(hex:)))
    case .glass: .glass
    case .titanium: .sweep([0xF4F6F9, 0xA7AFBA, 0xE6EAEF, 0x858E9A, 0xD9DEE4].map(Color.init(hex:)))
    }
  }

  /// The icon's background, top to bottom (its `icon.json` fill). Most are
  /// the system's automatic gradient from one colour; Glass and Titanium name
  /// both ends.
  var background: [Color] {
    func automatic(_ red: Double, _ green: Double, _ blue: Double) -> [Color] {
      let base = Color(red: red, green: green, blue: blue)
      return [base.mix(with: .white, by: 0.1), base]
    }
    switch self {
    case .classic: return automatic(0.03, 0.12, 0.07)
    case .amber: return automatic(0.12, 0.075, 0.015)
    case .cobalt: return automatic(0.03, 0.05, 0.16)
    case .synthwave: return automatic(0.09, 0.03, 0.18)
    case .noir: return automatic(0.05, 0.05, 0.05)
    case .gold: return automatic(0.07, 0.05, 0.01)
    case .holographic: return automatic(0.07, 0.06, 0.12)
    case .chalkboard: return automatic(0.09, 0.13, 0.11)
    case .glass: return [Color(red: 0.16, green: 0.78, blue: 0.92), Color(red: 0.43, green: 0.25, blue: 0.90)]
    case .titanium: return [Color(red: 0.22, green: 0.24, blue: 0.27), Color(red: 0.07, green: 0.08, blue: 0.09)]
    }
  }

  /// The icon as the home screen shows it, near enough: its layers on a
  /// 1024 pt canvas, scaled to `size`. The system's glass isn't reproduced.
  struct Artwork: View {
    let icon: AppIcon
    var size: CGFloat = 60

    /// Which way a sweep runs across each shape, as in the SVG layers.
    private static let sweepDirections: [(UnitPoint, UnitPoint)] = [
      (.topLeading, .bottomTrailing),
      (.topTrailing, .bottomLeading),
      (.bottomLeading, .topTrailing),
      (.topLeading, .bottomTrailing),
    ]

    var body: some View {
      let paint = icon.paint
      let sweepDirections = Self.sweepDirections
      Canvas { context, canvas in
        let s = canvas.width / 1024
        func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
          CGRect(x: x * s, y: y * s, width: width * s, height: height * s)
        }
        func polygon(_ points: [(CGFloat, CGFloat)]) -> Path {
          var path = Path()
          path.addLines(points.map { CGPoint(x: $0.0 * s, y: $0.1 * s) })
          path.closeSubpath()
          return path
        }
        func shading(_ shape: Int, over bounds: CGRect) -> GraphicsContext.Shading {
          switch paint {
          case .flat(let colors):
            return .color(colors[shape])
          case .sweep(let colors):
            let (from, to) = sweepDirections[shape]
            return .linearGradient(
              Gradient(colors: colors),
              startPoint: CGPoint(x: bounds.minX + from.x * bounds.width, y: bounds.minY + from.y * bounds.height),
              endPoint: CGPoint(x: bounds.minX + to.x * bounds.width, y: bounds.minY + to.y * bounds.height))
          case .glass:
            return .linearGradient(
              Gradient(colors: [.white.opacity(0.92), .white.opacity(0.55)]),
              startPoint: CGPoint(x: bounds.midX, y: bounds.minY),
              endPoint: CGPoint(x: bounds.midX, y: bounds.maxY))
          }
        }
        let rounded = StrokeStyle(lineWidth: 28 * s, lineJoin: .round)

        let circleBounds = rect(172, 172, 316, 316)
        context.fill(Path(ellipseIn: circleBounds), with: shading(0, over: circleBounds))

        let triangle = polygon([(694, 162), (862, 478), (526, 478)])
        let triangleShading = shading(1, over: triangle.boundingRect)
        context.fill(triangle, with: triangleShading)
        context.stroke(triangle, with: triangleShading, style: rounded)

        let squareBounds = rect(186, 550, 288, 288)
        context.fill(Path(roundedRect: squareBounds, cornerRadius: 28 * s), with: shading(2, over: squareBounds))

        let diamond = polygon([(694, 526), (862, 694), (694, 862), (526, 694)])
        let diamondShading = shading(3, over: diamond.boundingRect)
        context.fill(diamond, with: diamondShading)
        context.stroke(diamond, with: diamondShading, style: rounded)
      }
      .frame(width: size, height: size)
      .background(LinearGradient(colors: icon.background, startPoint: .top, endPoint: .bottom))
      .clipShape(.rect(cornerRadius: size * 0.225, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
          .strokeBorder(.white.opacity(0.14), lineWidth: 1)
      }
      .accessibilityHidden(true)
    }
  }
}
