import SwiftUI

/// Lays its children out in rows, left to right, wrapping when a row is full.
public struct FlowLayout: Layout {
  var spacing: CGFloat

  public init(spacing: CGFloat = Space.s) {
    self.spacing = spacing
  }

  public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let rows = arrange(subviews, in: proposal.width ?? .infinity)
    let width = rows.map(\.width).max() ?? 0
    let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
    return CGSize(width: width, height: height)
  }

  public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    var y = bounds.minY
    for row in arrange(subviews, in: bounds.width) {
      var x = bounds.minX
      for (index, size) in zip(row.indices, row.sizes) {
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var sizes: [CGSize] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(_ subviews: Subviews, in width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for index in subviews.indices {
      let size = self.size(of: subviews[index], within: width)
      let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      if needed > width, !row.indices.isEmpty {
        rows.append(row)
        row = Row()
      }
      row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
      row.sizes.append(size)
    }
    if !row.indices.isEmpty { rows.append(row) }
    return rows
  }

  /// A subview at its natural size, or — wider than a whole row, as a long
  /// name is at accessibility sizes — at the row's width, wrapping.
  private func size(of subview: LayoutSubview, within width: CGFloat) -> CGSize {
    let natural = subview.sizeThatFits(.unspecified)
    guard width.isFinite, natural.width > width else { return natural }
    return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
  }
}

/// Everyone in the game, as name chips that wrap: the host sees who's in at
/// a glance. `highlighted` is the viewer's own name.
public struct NameChips: View {
  let names: [String]
  let highlighted: String?

  public init(names: [String], highlighted: String? = nil) {
    self.names = names
    self.highlighted = highlighted
  }

  public var body: some View {
    // A capsule on one line; a rounded rectangle when a long name wraps.
    let shape = RoundedRectangle(cornerRadius: Radius.control)
    FlowLayout(spacing: Space.s) {
      ForEach(names, id: \.self) { name in
        Text(verbatim: name)
          .textRole(isViewer(name) ? .bodyEmphasis : .body)
          .foregroundStyle(isViewer(name) ? AnyShapeStyle(.themeAccent) : AnyShapeStyle(.primary))
          .multilineTextAlignment(.leading)
          .padding(.horizontal, Space.m)
          .padding(.vertical, Space.xs)
          .frame(minHeight: Size.target - Space.s)
          .background(.panel, in: shape)
          .overlay { shape.strokeBorder(.panelStroke, lineWidth: 1) }
          .transition(.scale.combined(with: .opacity))
      }
    }
    .motion(.pop, value: names)
    // One element, read in the order they joined: "Ada, Sam, and Robin (you)".
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(spokenNames))
  }

  private func isViewer(_ name: String) -> Bool {
    name.localizedCaseInsensitiveCompare(highlighted ?? "") == .orderedSame
  }

  private var spokenNames: String {
    names.map { isViewer($0) ? String(localized: "\($0) (you)") : $0 }.formatted(.list(type: .and))
  }
}
