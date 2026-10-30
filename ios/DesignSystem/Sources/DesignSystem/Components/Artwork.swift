import SwiftUI

/// How each home screen icon is painted: the answer set on its ink, recoloured
/// to match a theme. Mirrors each `AppIcon-*.icon` file's layers, so the app
/// can show them.
nonisolated public enum IconDesign: String, CaseIterable, Sendable {
  case classic, amber, cobalt, synthwave, noir, gold, holographic, chalkboard, glass, titanium
  case aurora, ember, sakura, abyss, circuit

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
    case .classic: .flat(AnswerStyle.allCases.map(\.color))
    case .amber: .flat([0xFFB000, 0xFFD066, 0xE08600, 0xFFC233].map(Color.init(hex:)))
    case .cobalt: .flat([0x7C9DFF, 0xA8E0FF, 0x5B6CFF, 0xC9D6FF].map(Color.init(hex:)))
    case .synthwave: .flat([0xFF4FB8, 0x4FE3FF, 0xFF9A3C, 0xC77DFF].map(Color.init(hex:)))
    case .noir: .flat([0xFFFFFF, 0xD6D6D6, 0xA8A8A8, 0xEDEDED].map(Color.init(hex:)))
    case .gold: .flat([0xF5C542, 0xFFE08A, 0xD9A21E, 0xFFD35C].map(Color.init(hex:)))
    case .holographic: .sweep([0xFF8AD8, 0xB69CFF, 0x7FE3FF, 0xA6FFCB, 0xFFD59A].map(Color.init(hex:)))
    case .chalkboard: .flat([0xF4F1E6, 0xA8D8F0, 0xFFF0A0, 0xFFB8C8].map(Color.init(hex:)))
    case .glass: .glass
    case .titanium: .sweep([0xF4F6F9, 0xA7AFBA, 0xE6EAEF, 0x858E9A, 0xD9DEE4].map(Color.init(hex:)))
    case .aurora: .sweep([0x5CFFA8, 0x3FE6D2, 0x7AA8FF, 0xA58BFF, 0xFF9CD6].map(Color.init(hex:)))
    case .ember: .flat([0xFF9466, 0xFFC857, 0xFF5E3A, 0xFFB38A].map(Color.init(hex:)))
    case .sakura: .flat([0xFFADCB, 0xFFE3EE, 0xFF7FAE, 0xFFC8DC].map(Color.init(hex:)))
    case .abyss: .flat([0x5CC4FF, 0x3FF2E0, 0x2E7BFF, 0xA8E6FF].map(Color.init(hex:)))
    // Gold-plated pads, on the board's green.
    case .circuit: .sweep([0xFFE08A, 0xD9A21E, 0xFFF3C4, 0xB8860B, 0xFFD35C].map(Color.init(hex:)))
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
    case .aurora: return automatic(0.02, 0.09, 0.12)
    case .ember: return automatic(0.12, 0.05, 0.03)
    case .sakura: return automatic(0.11, 0.05, 0.08)
    case .abyss: return automatic(0.01, 0.05, 0.12)
    case .circuit: return automatic(0.03, 0.13, 0.07)
    }
  }
}

/// An icon as the home screen shows it, near enough: its four layers on a
/// 1024 pt canvas, scaled to `size` — each shape in its own paint, with its
/// shadow, under a pane of the system's glass in its outline, as Icon
/// Composer builds it. Under Increase Contrast, the paint alone.
public struct IconArtwork: View {
  let design: IconDesign
  let size: CGFloat

  @Environment(\.palette) private var palette

  public init(_ design: IconDesign, size: CGFloat = Size.iconTile) {
    self.design = design
    self.size = size
  }

  /// Where each shape sits, in the `AppIcon-*.icon` files: a 2 × 2 grid with
  /// room between, each shape 272 pt across.
  private static let layout: (low: CGFloat, high: CGFloat, scale: CGFloat) = (320, 704, 272.0 / 316)

  /// The four shapes — circle, triangle, square, diamond — on a canvas
  /// `side` across.
  nonisolated static func outlines(side: CGFloat) -> [Path] {
    let s = side / 1024
    let (low, high, k) = (CGFloat(320), CGFloat(704), CGFloat(272.0 / 316))
    /// A shape's points around its centre, at the icon's scale.
    func polygon(_ points: [(CGFloat, CGFloat)], around centre: (CGFloat, CGFloat)) -> Path {
      var path = Path()
      path.addLines(points.map { CGPoint(x: (centre.0 + $0.0 * k) * s, y: (centre.1 + $0.1 * k) * s) })
      path.closeSubpath()
      // Its corners rounded as the SVG's stroke rounds them.
      return path.union(path.strokedPath(StrokeStyle(lineWidth: 28 * k * s, lineJoin: .round)))
    }
    let half = 144 * k * s
    return [
      Path(ellipseIn: CGRect(x: (low - 158 * k) * s, y: (low - 158 * k) * s, width: 316 * k * s, height: 316 * k * s)),
      polygon([(0, -158), (168, 158), (-168, 158)], around: (high, low)),
      Path(roundedRect: CGRect(x: low * s - half, y: high * s - half, width: 2 * half, height: 2 * half), cornerRadius: 28 * k * s),
      polygon([(0, -168), (168, 0), (0, 168), (-168, 0)], around: (high, high)),
    ]
  }

  /// Which way a sweep runs across each shape, as in the SVG layers.
  private static let sweepDirections: [(UnitPoint, UnitPoint)] = [
    (.topLeading, .bottomTrailing),
    (.topTrailing, .bottomLeading),
    (.bottomLeading, .topTrailing),
    (.topLeading, .bottomTrailing),
  ]

  /// The home screen's squircle, as a share of the icon's size.
  public static let cornerRatio: CGFloat = 0.225

  public var body: some View {
    let paint = design.paint
    let sweepDirections = Self.sweepDirections
    Canvas { context, canvas in
      let s = canvas.width / 1024
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
      // Each shape is its own layer: its shadow falls on what's behind it.
      for (index, outline) in Self.outlines(side: canvas.width).enumerated() {
        context.drawLayer { layer in
          layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 16 * s, y: 10 * s))
          layer.fill(outline, with: shading(index, over: outline.boundingRect))
        }
      }
    }
    .overlay {
      // The glass over each shape's paint, bending it and catching the light.
      if !palette.isHighContrast {
        GlassEffectContainer(spacing: 0) {
          ZStack {
            ForEach(0..<4, id: \.self) { index in
              Color.clear
                .glassEffect(.clear, in: IconLayer(index: index))
            }
          }
        }
      }
    }
    .frame(width: size, height: size)
    .background(LinearGradient(colors: design.background, startPoint: .top, endPoint: .bottom))
    .clipShape(.rect(cornerRadius: size * Self.cornerRatio, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: size * Self.cornerRatio, style: .continuous)
        .strokeBorder(.panelStroke, lineWidth: 1)
    }
    .accessibilityHidden(true)
  }
}

/// One of an icon's four shapes, on the frame it's given.
nonisolated private struct IconLayer: Shape {
  let index: Int

  func path(in rect: CGRect) -> Path {
    IconArtwork.outlines(side: rect.width)[index].offsetBy(dx: rect.minX, dy: rect.minY)
  }
}

/// A theme in miniature: its own backdrop, and its cursor in glass.
public struct ThemeSwatch: View {
  let theme: Theme
  let isShown: Bool

  public init(theme: Theme, isShown: Bool) {
    self.theme = theme
    self.isShown = isShown
  }

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.control / 2)
    // The wordmark's block, at the swatch's size: as tall as a capital.
    let block = Lettering("", size: Size.swatch / 3, weight: .heavy, tracking: 0).cursor
    Backdrop(mood: .idle)
      // Held still: a page of swatches all following the phone would keep
      // the glass over them busy for a movement too small to see. The page's
      // own backdrop follows it.
      .environment(\.backdropFollowsTilt, false)
      .overlay {
        GlassCharacter(shape: RoundedRectangle(cornerRadius: block.width / 24), color: theme.accent, depth: .mark)
          .frame(width: block.width, height: block.height)
      }
      .theme(theme)
      .frame(width: Size.swatch, height: Size.swatch)
      .clipShape(shape)
      .overlay {
        shape.strokeBorder(isShown ? AnyShapeStyle(theme.accent) : AnyShapeStyle(.panelStroke), lineWidth: isShown ? 1.5 : 1)
      }
      .accessibilityHidden(true)
  }
}

/// A set of answer markers as a swatch: its four shapes, two by two, in the
/// answers' colours and drawn in glass, on a tile of glass — the set's row in
/// Themes & Icons.
public struct MarkerSwatch: View {
  let markers: AnswerMarkers
  let isShown: Bool

  public init(markers: AnswerMarkers, isShown: Bool) {
    self.markers = markers
    self.isShown = isShown
  }

  public var body: some View {
    let shape = RoundedRectangle(cornerRadius: Radius.control / 2)
    Grid(horizontalSpacing: Space.xxs, verticalSpacing: Space.xxs) {
      GridRow {
        glyph(.a)
        glyph(.b)
      }
      GridRow {
        glyph(.c)
        glyph(.d)
      }
    }
    .font(.system(size: Size.swatch / 3.5, weight: .bold))
    .frame(width: Size.swatch, height: Size.swatch)
    .glassCard(in: shape)
    .overlay {
      shape.strokeBorder(isShown ? AnyShapeStyle(.themeAccent) : AnyShapeStyle(.panelStroke), lineWidth: isShown ? 1.5 : 1)
    }
    .environment(\.answerMarkers, markers)
    .accessibilityHidden(true)
  }

  /// Each in a cell of its own, scaled to fit it: a turtle or a fish is
  /// wider than a circle, and must stay clear of its neighbours.
  private func glyph(_ style: AnswerStyle) -> some View {
    AnswerGlyph(style: style, fitsFrame: true)
      .frame(width: Size.swatch / 2.9, height: Size.swatch / 2.9)
      .frame(width: Size.swatch / 2.6, height: Size.swatch / 2.6)
  }
}
