import SwiftUI

/// A screen in two halves: first what's there to be read, then what's there
/// to be touched.
///
/// For a screen with room for two halves side by side or one above the
/// other — regular in both size classes (`hasRoomToSpread`): iPad, and
/// iPhone Duo open. It splits along its longer side, at iPhone Duo's hinge,
/// whichever way the phone's turned — where the system says the hinge is
/// (its `.division` reserved region, iOS 27.1), and elsewhere at the
/// window's middle — at least `Space.fold` apart, and wider if the hinge
/// asks. Nothing sits on the fold: held like a book, the halves are facing
/// pages; propped up like a laptop, the first stands up to be read across
/// the table and the second lies under the hand.
///
/// Each half centres what's in it, no wider than a phone's column
/// (`Size.column`). `hidesStackedLead` gives the second half the whole screen
/// while the halves are stacked: for a form whose keyboard would cover it.
public struct Spread<Lead: View, Trail: View>: View {
  let hidesStackedLead: Bool
  let lead: Lead
  let trail: Trail

  @Environment(\.windowFrame) private var window
  @Environment(\.layoutDirection) private var direction
  @State private var geometry = SpreadGeometry()

  public init(hidesStackedLead: Bool = false, @ViewBuilder lead: () -> Lead, @ViewBuilder trail: () -> Trail) {
    self.hidesStackedLead = hidesStackedLead
    self.lead = lead()
    self.trail = trail()
  }

  public var body: some View {
    let frame = geometry.frame
    let hidesLead = hidesStackedLead && frame.height > frame.width
    SpreadLayout(fold: fold, gutter: gutter, hidesLead: hidesLead) {
      half { lead }
        .opacity(hidesLead ? 0 : 1)
        .allowsHitTesting(!hidesLead)
        .accessibilityHidden(hidesLead)
      half { trail }
    }
    .motion(.settle, value: hidesLead)
    .motion(.settle, value: gutter)
    .onGeometryChange(for: SpreadGeometry.self) { SpreadGeometry($0) } action: { geometry = $0 }
  }

  private func half(@ViewBuilder _ content: () -> some View) -> some View {
    content()
      .frame(maxWidth: Size.column)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  /// How far the fold is from this spread's middle, along its longer side:
  /// the hinge where the system knows it, and otherwise the window's middle.
  /// They differ from the spread's own middle when the insets around it do —
  /// a vertical toolbar down one side of iPhone Duo, say.
  private var fold: CGFloat {
    let frame = geometry.frame
    guard !frame.isEmpty else { return 0 }
    let isSideBySide = frame.width >= frame.height
    if let hinge = geometry.hinge {
      return isSideBySide ? hinge.frame.midX - frame.width / 2 : hinge.frame.midY - frame.height / 2
    }
    guard let window else { return 0 }
    guard isSideBySide else { return window.midY - frame.midY }
    let offset = window.midX - frame.midX
    // Laid out from the leading edge: right to left, that's the far side.
    return direction == .rightToLeft ? -offset : offset
  }

  /// `Space.fold`, or more where a folded hinge needs more room.
  private var gutter: CGFloat {
    guard let hinge = geometry.hinge, hinge.isActive else { return Space.fold }
    let frame = geometry.frame
    let room = frame.width >= frame.height
      ? hinge.frame.width + hinge.margins.leading + hinge.margins.trailing
      : hinge.frame.height + hinge.margins.top + hinge.margins.bottom
    return max(Space.fold, room)
  }
}

/// Where a spread is, and the hinge across it, if there is one.
nonisolated struct SpreadGeometry: Equatable, Sendable {
  /// iPhone Duo's hinge, in the spread's own space — mirrored right to left,
  /// as its layout is. Flat, it's there but inactive, and no wider than a
  /// line; folded, it's as wide as the display's curve, and its margins say
  /// how far to keep clear of it.
  struct Hinge: Equatable, Sendable {
    var frame: CGRect
    var margins: EdgeInsets
    var isActive: Bool
  }

  var frame: CGRect = .zero
  var hinge: Hinge?

  init() {}

  init(_ proxy: GeometryProxy) {
    frame = proxy.frame(in: .global)
    if #available(iOS 27.1, *), let region = proxy.reservedRegions(kind: .division, options: .includeInactive).first {
      hinge = Hinge(frame: region.frame, margins: region.margins, isActive: region.isActive)
    }
  }
}

/// Two subviews either side of a fold, across the longer side of the bounds.
struct SpreadLayout: Layout {
  /// The fold's distance from the middle, towards the second subview.
  var fold: CGFloat
  /// The room kept clear around the fold.
  var gutter: CGFloat = Space.fold
  /// The first subview gives the second all the room while they're stacked.
  var hidesLead: Bool

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    proposal.replacingUnspecifiedDimensions()
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    guard subviews.count == 2 else {
      for subview in subviews { subview.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
      return
    }
    let (lead, trail) = (subviews[0], subviews[1])
    let isSideBySide = bounds.width >= bounds.height
    if hidesLead, !isSideBySide {
      lead.place(at: CGPoint(x: bounds.midX, y: bounds.minY), anchor: .top, proposal: ProposedViewSize(width: bounds.width, height: 0))
      trail.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
      return
    }
    let length = isSideBySide ? bounds.width : bounds.height
    // Off the middle by a little at most: each half keeps 40 % of the screen.
    let middle = length / 2 + min(max(fold, -length / 10), length / 10)
    let first = max(middle - gutter / 2, 0)
    let second = max(length - middle - gutter / 2, 0)
    if isSideBySide {
      lead.place(at: bounds.origin, proposal: ProposedViewSize(width: first, height: bounds.height))
      trail.place(at: CGPoint(x: bounds.maxX - second, y: bounds.minY), proposal: ProposedViewSize(width: second, height: bounds.height))
    } else {
      lead.place(at: bounds.origin, proposal: ProposedViewSize(width: bounds.width, height: first))
      trail.place(at: CGPoint(x: bounds.minX, y: bounds.maxY - second), proposal: ProposedViewSize(width: bounds.width, height: second))
    }
  }
}

nonisolated extension EnvironmentValues {
  /// The window's frame in global coordinates, once `measuresWindow()` has
  /// measured it: where a `Spread` finds the window's middle.
  @Entry public var windowFrame: CGRect? = nil

  /// Room to lay a screen out as a `Spread`: regular in both size classes —
  /// iPad, and iPhone Duo open. Closed, a Duo is compact like any phone.
  public var hasRoomToSpread: Bool {
    horizontalSizeClass == .regular && verticalSizeClass == .regular
  }
}

extension View {
  /// Measures the window this view fills, so a `Spread` inside it can find
  /// the window's middle. Goes on the window's root view.
  public func measuresWindow() -> some View {
    modifier(WindowMeasure())
  }

  /// Keeps a bar that would run the width of the screen to the second half
  /// of a side-by-side spread, where a spread's actions are — so none runs
  /// across the fold. Anywhere else it's left as it is.
  public func inSpreadsSecondHalf() -> some View {
    modifier(SecondHalf())
  }
}

private struct SecondHalf: ViewModifier {
  @Environment(\.hasRoomToSpread) private var spreads
  @Environment(\.windowFrame) private var window

  func body(content: Content) -> some View {
    if spreads, let window, window.width >= window.height {
      content
        .containerRelativeFrame(.horizontal) { length, _ in max((length - Space.fold) / 2, 0) }
        .frame(maxWidth: .infinity, alignment: .trailing)
    } else {
      content
    }
  }
}

private struct WindowMeasure: ViewModifier {
  @State private var frame: CGRect?

  func body(content: Content) -> some View {
    content
      .environment(\.windowFrame, frame)
      .background {
        Color.clear
          .ignoresSafeArea()
          .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
      }
  }
}
