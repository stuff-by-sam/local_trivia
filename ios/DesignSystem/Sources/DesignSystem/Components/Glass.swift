import SwiftUI

// Layered glass, everywhere, as iOS 27's own icons are built:
//
// - Surfaces: the controls, and the cards, chips, steps and badges content
//   sits on. How see-through a card is depends on the screen
//   (`GlassClarity`): clear on menus, tinted toward the ink on game screens,
//   where a question has to be read at a glance.
// - Characters: the wordmark, the figures, the answer markers and every mark
//   are made of glass themselves, in their own outlines (`GlassText`,
//   `GlassSymbol`, in GlassCharacters.swift).

/// How see-through the glass under a screen's content is.
nonisolated public enum GlassClarity: Sendable {
  /// Menus, lobbies, the join screen: short, high-contrast content, so the
  /// backdrop shows through.
  case clear
  /// Questions, results, standings: tinted toward the ink, so text reads at
  /// a glance whatever the backdrop is doing behind it.
  case tinted
}

nonisolated extension EnvironmentValues {
  /// How see-through the cards, chips and badges inside are.
  @Entry public var glassClarity: GlassClarity = .tinted
}

extension View {
  /// Sets how see-through the glass under this screen's content is.
  public func glassClarity(_ clarity: GlassClarity) -> some View {
    environment(\.glassClarity, clarity)
  }
}

extension Palette {
  /// The glass content sits on, for a screen of `clarity`. `tint` colours it
  /// — a medal, the viewer's own name — instead of the ink.
  ///
  /// Under Increase Contrast it's always the regular, frosted glass: clear
  /// glass is for content that holds up on anything, and the reader has asked
  /// for more than that. Reduce Transparency is the system's to handle.
  public func contentGlass(_ clarity: GlassClarity, tint: Color? = nil) -> Glass {
    if let tint {
      return .regular.tint(tint.opacity(isHighContrast ? 0.3 : 0.2))
    }
    switch clarity {
    case .clear where !isHighContrast:
      return .clear
    case .clear, .tinted:
      return .regular.tint(ink.opacity(isHighContrast ? 0.7 : 0.5))
    }
  }
}

/// How big a glass character is, for its glass: how much colour it holds,
/// how far its bloom spreads, and the room its glass's shadow needs. Sized to
/// what it's drawn on.
nonisolated public enum GlassDepth: Sendable {
  /// A status dot: a bead.
  case dot
  /// An answer's key, a swatch, a marker beside text.
  case mark
  /// A figure in a card: the join code.
  case figure
  /// A hero figure: the wordmark, the rank, the points.
  case hero
  /// Across a room, on the TV.
  case tv

  /// The lit edge's width.
  var rim: CGFloat {
    switch self {
    case .dot, .mark: 0.75
    case .figure: 1.25
    case .hero: 2
    case .tv: 4
    }
  }

  /// The shadow's radius; it falls half that far.
  var shadow: CGFloat {
    switch self {
    case .dot: 3
    case .mark: 1
    case .figure: 2.5
    case .hero: 5
    case .tv: 10
    }
  }

  /// Room around a glass character for the glass's shadow to fall in.
  var room: CGFloat {
    4 * shadow
  }

  /// How much colour a glass character holds: more the smaller it is, so a
  /// marker beside a letter still reads as its answer's colour.
  var tint: Double {
    switch self {
    case .dot: 0.9
    case .mark: 0.85
    case .figure: 0.75
    case .hero, .tv: 0.65
    }
  }
}

extension View {
  /// An SF Symbol drawn to look like glass: its own gradient rendering
  /// (`symbolColorRenderingMode(.gradient)`), its top edge catching the light
  /// and its bottom edge a little of it, lifted by a shadow. What a
  /// `GlassSymbol` shows for the moment before its outline is traced.
  func glassSymbol(_ color: Color, depth: GlassDepth = .mark) -> some View {
    modifier(DrawnGlassSymbol(color: color, depth: depth))
  }

  /// A drawn glass edge around `shape`: bright along the top, faint along the
  /// bottom, as the system lights its own glass. For small things drawn on
  /// glass already — an answer's key — where glass on glass would only blur.
  public func glassRim(in shape: some InsettableShape) -> some View {
    modifier(GlassRim(shape: shape))
  }
}

private struct DrawnGlassSymbol: ViewModifier {
  let color: Color
  let depth: GlassDepth

  @Environment(\.palette) private var palette

  func body(content: Content) -> some View {
    if palette.isHighContrast {
      content.foregroundStyle(color)
    } else {
      content
        .foregroundStyle(color)
        .symbolColorRenderingMode(.gradient)
        // The top edge, catching the light.
        .overlay { edge(of: content, from: depth.rim, opacity: 0.9) }
        // The bottom edge, catching a little of it.
        .overlay { edge(of: content, from: -depth.rim, opacity: 0.35) }
        .shadow(color: .black.opacity(0.5), radius: depth.shadow, y: depth.shadow / 2)
    }
  }

  /// The glyph's edge facing away from `offset`: the glyph, less itself moved
  /// `offset` down — what's left is a crescent along every top edge (or, moved
  /// up, every bottom edge).
  private func edge(of content: Content, from offset: CGFloat, opacity: Double) -> some View {
    content
      .foregroundStyle(.white.opacity(opacity))
      .mask {
        content
          .overlay {
            content
              .offset(y: offset)
              .blendMode(.destinationOut)
          }
          .compositingGroup()
      }
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }
}

private struct GlassRim<S: InsettableShape>: ViewModifier {
  let shape: S

  @Environment(\.palette) private var palette

  func body(content: Content) -> some View {
    content.overlay {
      shape.strokeBorder(
        LinearGradient(
          stops: [
            .init(color: .white.opacity(palette.isHighContrast ? 0.6 : 0.45), location: 0),
            .init(color: .white.opacity(0.04), location: 0.45),
            .init(color: .white.opacity(palette.isHighContrast ? 0.4 : 0.16), location: 1),
          ],
          startPoint: .top,
          endPoint: .bottom
        ),
        lineWidth: 1
      )
      .allowsHitTesting(false)
    }
  }
}

extension View {
  /// Puts this on a card of glass, as clear or tinted as the screen's
  /// `glassClarity`. Under Increase Contrast the card keeps a hairline edge,
  /// so it reads as a card on any backdrop.
  public func glassCard(in shape: some Shape, tint: Color? = nil) -> some View {
    modifier(GlassCard(shape: shape, tint: tint))
  }
}

private struct GlassCard<S: Shape>: ViewModifier {
  let shape: S
  let tint: Color?

  @Environment(\.palette) private var palette
  @Environment(\.glassClarity) private var clarity

  func body(content: Content) -> some View {
    content
      .glassEffect(palette.contentGlass(clarity, tint: tint), in: shape)
      .overlay {
        if palette.isHighContrast {
          shape.stroke(.panelStroke, lineWidth: 1)
            .allowsHitTesting(false)
        }
      }
  }
}
