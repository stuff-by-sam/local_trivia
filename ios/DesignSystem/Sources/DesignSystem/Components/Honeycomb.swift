import SwiftUI

/// Round bubbles packed as watchOS packs its apps: rows alternate one long
/// and one a bubble shorter, each bubble sitting in the hollow between two
/// above it. Themes & Markers lays out its choices this way.
///
/// As many fit in a long row as the width allows, at least two, so a wider
/// screen — an iPad, a bigger text size's bigger bubbles — gets longer or
/// shorter rows, never a scrolling one. Rows are centred, and read first to
/// last, row by row.
public struct Honeycomb: Layout {
  let diameter: CGFloat
  let spacing: CGFloat

  public init(diameter: CGFloat, spacing: CGFloat = Space.m) {
    self.diameter = diameter
    self.spacing = spacing
  }

  /// Centre to centre, along a row.
  private var pitch: CGFloat { diameter + spacing }
  /// Row to row: the height of the triangle three touching bubbles make.
  private var rowPitch: CGFloat { pitch * 3.squareRoot() / 2 }

  /// How many a long row of `width` holds.
  private func longRow(in width: CGFloat) -> Int {
    max(2, Int((width + spacing) / pitch))
  }

  /// How many go in each row, for `count` bubbles in rows of `long` and
  /// `long - 1`.
  private func rows(of count: Int, long: Int) -> [Int] {
    var rows: [Int] = []
    var left = count
    while left > 0 {
      let row = min(left, rows.count.isMultiple(of: 2) ? long : long - 1)
      rows.append(row)
      left -= row
    }
    return rows
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? CGFloat(4) * pitch - spacing
    let rows = rows(of: subviews.count, long: longRow(in: width))
    guard !rows.isEmpty else { return CGSize(width: width, height: 0) }
    return CGSize(width: width, height: diameter + CGFloat(rows.count - 1) * rowPitch)
  }

  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let rows = rows(of: subviews.count, long: longRow(in: bounds.width))
    var index = subviews.startIndex
    for (row, count) in rows.enumerated() {
      let width = CGFloat(count) * pitch - spacing
      let y = bounds.minY + diameter / 2 + CGFloat(row) * rowPitch
      for column in 0..<count {
        let x = bounds.midX - width / 2 + diameter / 2 + CGFloat(column) * pitch
        subviews[index].place(
          at: CGPoint(x: x, y: y), anchor: .center,
          proposal: ProposedViewSize(width: diameter, height: diameter))
        index = subviews.index(after: index)
      }
    }
  }
}

extension View {
  /// Shrinks and fades this as it nears the top or bottom edge of the scroll
  /// view it's in, as watchOS's honeycomb does: full size more than `band`
  /// from the edge, a third of it at the edge. Still under Reduce Motion.
  ///
  /// Give the scroll view's content `band` of margin at each end, so at rest
  /// nothing sits in the lens: it's what scrolling does, not how a short
  /// page looks.
  public func fisheye(band: CGFloat) -> some View {
    modifier(Fisheye(band: band))
  }
}

private struct Fisheye: ViewModifier {
  let band: CGFloat
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The size and opacity a bubble shrinks to at the very edge.
  nonisolated private static let edgeScale: CGFloat = 0.34
  nonisolated private static let edgeOpacity: CGFloat = 0.2

  func body(content: Content) -> some View {
    let band = band
    let isOn = !reduceMotion
    content.visualEffect { content, proxy in
      var lens: CGFloat = 1
      if isOn, band > 0, let visible = proxy.bounds(of: .scrollView(axis: .vertical)) {
        let middle = proxy.size.height / 2
        let nearest = min(middle - visible.minY, visible.maxY - middle)
        let t = min(max(nearest / band, 0), 1)
        // Smoothstep: no kink where the shrinking starts.
        lens = t * t * (3 - 2 * t)
      }
      return content
        .scaleEffect(Self.edgeScale + (1 - Self.edgeScale) * lens)
        .opacity(Self.edgeOpacity + (1 - Self.edgeOpacity) * lens)
    }
  }
}

/// A bubble's press: it gives a little under the finger, as watchOS's do,
/// and lifts under an iPad's pointer.
public struct BubbleButtonStyle: ButtonStyle {
  public init() {}

  public func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.9 : 1)
      .motion(.snap, value: configuration.isPressed)
      .hoverEffect(.lift)
  }
}

extension ButtonStyle where Self == BubbleButtonStyle {
  /// A bubble in the honeycomb.
  public static var bubble: BubbleButtonStyle { BubbleButtonStyle() }
}

/// A theme as a bubble in the honeycomb: its own backdrop, held still, and
/// its cursor in glass. Lit when it's the one being worn.
public struct ThemeBubble: View {
  let theme: Theme
  let isWorn: Bool
  let diameter: CGFloat

  public init(theme: Theme, isWorn: Bool, diameter: CGFloat = Size.bubble) {
    self.theme = theme
    self.isWorn = isWorn
    self.diameter = diameter
  }

  public var body: some View {
    // The wordmark's block, at the bubble's size: as tall as a capital.
    let block = Lettering("", size: diameter / 3.2, weight: .heavy, tracking: 0).cursor
    Backdrop(mood: .idle)
      // Held still, and its photo read small: a page of bubbles all
      // following the phone would keep the glass over them busy for nothing.
      .environment(\.backdropFollowsTilt, false)
      .environment(\.backdropIsMiniature, true)
      .overlay {
        GlassCharacter(shape: RoundedRectangle(cornerRadius: block.width / 24), color: theme.accent, depth: .mark)
          .frame(width: block.width, height: block.height)
      }
      .theme(theme)
      .frame(width: diameter, height: diameter)
      .clipShape(.circle)
      .overlay { Circle().strokeBorder(.panelStroke, lineWidth: 1) }
      // The backdrop takes no touches of its own: the whole disc does.
      .contentShape(.circle)
      .worn(isWorn, in: theme.accent, diameter: diameter)
  }
}

/// A set of answer markers as a bubble: its four shapes, two by two, in the
/// answers' colours, in glass on a disc of glass. Lit when it's in use.
public struct MarkerBubble: View {
  let markers: AnswerMarkers
  let isWorn: Bool
  let diameter: CGFloat

  @Environment(\.palette) private var palette

  public init(markers: AnswerMarkers, isWorn: Bool, diameter: CGFloat = Size.bubble) {
    self.markers = markers
    self.isWorn = isWorn
    self.diameter = diameter
  }

  public var body: some View {
    Grid(horizontalSpacing: diameter * 0.05, verticalSpacing: diameter * 0.05) {
      GridRow {
        glyph(.a)
        glyph(.b)
      }
      GridRow {
        glyph(.c)
        glyph(.d)
      }
    }
    .font(.system(size: diameter / 5, weight: .bold))
    .frame(width: diameter, height: diameter)
    .glassCard(in: .circle)
    .contentShape(.circle)
    .environment(\.answerMarkers, markers)
    .worn(isWorn, in: palette.accent, diameter: diameter)
  }

  /// Each in a cell of its own, scaled to fit it, as a swatch draws them.
  private func glyph(_ style: AnswerStyle) -> some View {
    AnswerGlyph(style: style, fitsFrame: true)
      .frame(width: diameter * 0.25, height: diameter * 0.25)
      .frame(width: diameter * 0.29, height: diameter * 0.29)
  }
}

/// The honeycomb's last bubble: make one of your own.
public struct MakeBubble: View {
  let diameter: CGFloat

  public init(diameter: CGFloat = Size.bubble) {
    self.diameter = diameter
  }

  public var body: some View {
    AccentPlus(diameter: diameter)
      .frame(width: diameter, height: diameter)
      .glassCard(in: .circle)
      .contentShape(.circle)
      .overlay {
        Circle()
          .strokeBorder(.themeAccent, style: StrokeStyle(lineWidth: Size.bubbleRing / 2, dash: [diameter / 14, diameter / 18]))
          .padding(Size.bubbleRing)
      }
  }
}

/// The plus, in the accent's glass.
private struct AccentPlus: View {
  let diameter: CGFloat
  @Environment(\.palette) private var palette

  var body: some View {
    GlassSymbol("plus", color: palette.accent, depth: .mark)
      .font(.system(size: diameter * 0.34, weight: .semibold))
  }
}

extension View {
  /// The worn bubble's ring, a little out from its edge, and a check badge
  /// on its shoulder — the check because the ring alone is colour, and the
  /// ring because the badge alone is small.
  fileprivate func worn(_ isWorn: Bool, in color: Color, diameter: CGFloat) -> some View {
    let badge = diameter * 0.32
    return
      self
      .overlay {
        Circle()
          .strokeBorder(color, lineWidth: Size.bubbleRing)
          .padding(-(Size.bubbleRing + Space.xs))
          .opacity(isWorn ? 1 : 0)
      }
      .overlay(alignment: .bottomTrailing) {
        Image(systemName: "checkmark")
          .font(.system(size: badge * 0.48, weight: .bold))
          .foregroundStyle(.onAccent)
          .frame(width: badge, height: badge)
          .background(color, in: .circle)
          .overlay { Circle().strokeBorder(.ink, lineWidth: Size.bubbleRing / 2) }
          .offset(x: Space.xs, y: Space.xs)
          .scaleEffect(isWorn ? 1 : 0.4)
          .opacity(isWorn ? 1 : 0)
      }
      .motion(.pop, value: isWorn)
  }
}
