import SwiftUI

/// Round bubbles packed as watchOS packs its apps: rows alternate one long
/// and one a bubble shorter, each bubble sitting in the hollow between two
/// above it. Themes & Markers lays out its choices this way.
///
/// As many fit in a long row as the width allows, at least two, so a wider
/// screen — an iPad, a bigger text size's bigger bubbles — gets longer or
/// shorter rows, never a scrolling one. Every bubble keeps to the comb's
/// lattice, the last row's too, so none ever sits straight under another: a
/// last row that isn't full is centred on the lattice, and the comb starts
/// with its short row when that's what centres it. Rows read first to last,
/// row by row.
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

  /// A row of the comb: how many bubbles it holds, whether it's a long one,
  /// and how many of its places it leaves empty before them.
  private struct Row {
    let count: Int
    let isLong: Bool
    let lead: Int
  }

  /// The rows, for `count` bubbles in rows of `long` and `long - 1`.
  ///
  /// A last row that isn't full can only be centred on the lattice when its
  /// empty places split evenly either side of it; centred off it, its
  /// bubbles would sit straight under the row above's and run into them. So
  /// the comb starts on a long row, or on a short one when that centres the
  /// last row instead — 17 bubbles four wide go 3, 4, 3, 4, 3 — and if
  /// neither does, the last row keeps to the lattice half a place off centre.
  private func rows(of count: Int, long: Int) -> [Row] {
    func comb(startingLong: Bool) -> [Row] {
      var rows: [Row] = []
      var left = count
      var isLong = startingLong
      while left > 0 {
        let places = isLong ? long : long - 1
        let row = min(left, places)
        rows.append(Row(count: row, isLong: isLong, lead: (places - row) / 2))
        left -= row
        isLong.toggle()
      }
      return rows
    }
    func isCentred(_ rows: [Row]) -> Bool {
      guard let last = rows.last else { return true }
      return ((last.isLong ? long : long - 1) - last.count).isMultiple(of: 2)
    }
    let fromLong = comb(startingLong: true)
    if isCentred(fromLong) { return fromLong }
    let fromShort = comb(startingLong: false)
    return isCentred(fromShort) ? fromShort : fromLong
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    // Four across when asked its ideal size — or its largest, which a stack
    // asks for and no row count can be made of.
    let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? CGFloat(4) * pitch - spacing
    let rows = rows(of: subviews.count, long: longRow(in: width))
    guard !rows.isEmpty else { return CGSize(width: width, height: 0) }
    return CGSize(width: width, height: diameter + CGFloat(rows.count - 1) * rowPitch)
  }

  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    for (subview, centre) in zip(subviews, centres(of: subviews.count, width: bounds.width)) {
      subview.place(
        at: CGPoint(x: bounds.minX + centre.x, y: bounds.minY + centre.y), anchor: .center,
        proposal: ProposedViewSize(width: diameter, height: diameter))
    }
  }

  /// Where `count` bubbles' centres go in a comb `width` wide, measured from
  /// its top left, first to last.
  public func centres(of count: Int, width: CGFloat) -> [CGPoint] {
    let long = longRow(in: width)
    // The lattice, centred: where a long row's first bubble sits. A short
    // row's places are half a pitch in from a long row's.
    let first = width / 2 - (CGFloat(long) * pitch - spacing) / 2 + diameter / 2
    return rows(of: count, long: long).enumerated().flatMap { number, row in
      let y = diameter / 2 + CGFloat(number) * rowPitch
      let start = first + (row.isLong ? 0 : pitch / 2) + CGFloat(row.lead) * pitch
      return (0..<row.count).map { CGPoint(x: start + CGFloat($0) * pitch, y: y) }
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

/// A theme as a bubble in the honeycomb: a lens on its own backdrop, held
/// still, lit from within by its accent, with its cursor in glass — so a
/// page of them reads as the themes' colours at a glance. Ringed when it's
/// the one being worn.
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
    let block = Lettering("", size: diameter / 2.7, weight: .heavy, tracking: 0).cursor
    Backdrop(mood: .idle)
      // Held still, and its photo read small: a page of bubbles all
      // following the phone would keep the glass over them busy for nothing.
      .environment(\.backdropFollowsTilt, false)
      .environment(\.backdropIsMiniature, true)
      // The accent pooled behind the cursor, as the wordmark's bloom pools
      // behind its letters: a dark texture at this size is all ink, and
      // this is what tells one theme from the next.
      .overlay {
        RadialGradient(
          colors: [theme.accent.opacity(0.6), theme.accent.opacity(0.22), theme.accent.opacity(0)],
          center: .center, startRadius: 0, endRadius: diameter * 0.46)
      }
      .overlay { LensShade(diameter: diameter) }
      .overlay {
        GlassCharacter(shape: RoundedRectangle(cornerRadius: block.width / 24), color: theme.accent, depth: .mark)
          .frame(width: block.width, height: block.height)
      }
      .theme(theme)
      .frame(width: diameter, height: diameter)
      .clipShape(.circle)
      .glassRim(in: Circle())
      // The backdrop takes no touches of its own: the whole disc does.
      .contentShape(.circle)
      .worn(isWorn, in: theme.accent, diameter: diameter)
  }
}

/// A set of answer markers as a bubble: its four shapes, two by two, in the
/// answers' colours, in glass on a lens of glass. Ringed when it's in use.
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
    Grid(horizontalSpacing: diameter * 0.035, verticalSpacing: diameter * 0.035) {
      GridRow {
        glyph(.a)
        glyph(.b)
      }
      GridRow {
        glyph(.c)
        glyph(.d)
      }
    }
    .font(.system(size: diameter / 4.6, weight: .bold))
    .frame(width: diameter, height: diameter)
    // Under the shapes, over the glass: the lens's edge in shadow.
    .background { LensShade(diameter: diameter) }
    .glassCard(in: .circle)
    .glassRim(in: Circle())
    .contentShape(.circle)
    .environment(\.answerMarkers, markers)
    .worn(isWorn, in: palette.accent, diameter: diameter)
  }

  /// Each in a cell of its own, scaled to fit it, as a swatch draws them —
  /// as big as four can be and still clear the disc's edge.
  private func glyph(_ style: AnswerStyle) -> some View {
    AnswerGlyph(style: style, fitsFrame: true)
      .frame(width: diameter * 0.27, height: diameter * 0.27)
      .frame(width: diameter * 0.31, height: diameter * 0.31)
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
      .background { LensShade(diameter: diameter) }
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

/// Where a bubble's edge falls into shadow, as a lens's does: what makes a
/// flat disc read as one you could pick up.
private struct LensShade: View {
  let diameter: CGFloat

  var body: some View {
    RadialGradient(
      colors: [.clear, .black.opacity(0.5)],
      center: .center, startRadius: diameter * 0.3, endRadius: diameter * 0.5
    )
    .clipShape(.circle)
    .allowsHitTesting(false)
  }
}

extension View {
  /// The worn bubble: drawn in from its edge, with a ring in the gap, and a
  /// check badge on its shoulder — the check because the ring alone is
  /// colour, and the ring because the badge alone is small. All of it
  /// inside the bubble's own room, so a worn bubble never crowds the ones
  /// beside it, however tight the comb (the tutorial's, the editor's).
  fileprivate func worn(_ isWorn: Bool, in color: Color, diameter: CGFloat) -> some View {
    // The ring and the air inside it, in step with the bubble's size.
    let ring = Size.bubbleRing * diameter / Size.bubble
    let drawnIn = 1 - 4 * ring / diameter
    let badge = diameter * 0.32
    return
      self
      .scaleEffect(isWorn ? drawnIn : 1)
      .overlay {
        Circle()
          .strokeBorder(color, lineWidth: ring)
          .scaleEffect(isWorn ? 1 : drawnIn)
          .opacity(isWorn ? 1 : 0)
          .allowsHitTesting(false)
      }
      .overlay(alignment: .bottomTrailing) {
        Image(systemName: "checkmark")
          .font(.system(size: badge * 0.48, weight: .bold))
          .foregroundStyle(.onAccent)
          .frame(width: badge, height: badge)
          .background(color, in: .circle)
          .overlay { Circle().strokeBorder(.ink, lineWidth: ring / 2) }
          .scaleEffect(isWorn ? 1 : 0.4)
          .opacity(isWorn ? 1 : 0)
          .allowsHitTesting(false)
      }
      .motion(.pop, value: isWorn)
  }
}
