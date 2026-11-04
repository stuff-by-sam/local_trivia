import SwiftUI

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
      .environment(\.backdropIsMiniature, true)
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
/// answers' colours and drawn in glass, on a tile of glass — as the tutorial
/// shows the sets.
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
