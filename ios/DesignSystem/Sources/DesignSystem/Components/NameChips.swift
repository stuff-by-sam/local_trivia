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
      for index in row.indices {
        let size = subviews[index].sizeThatFits(.unspecified)
        subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
        x += size.width + spacing
      }
      y += row.height + spacing
    }
  }

  private struct Row {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func arrange(_ subviews: Subviews, in width: CGFloat) -> [Row] {
    var rows: [Row] = []
    var row = Row()
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(.unspecified)
      let needed = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      if needed > width, !row.indices.isEmpty {
        rows.append(row)
        row = Row()
      }
      row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
      row.height = max(row.height, size.height)
      row.indices.append(index)
    }
    if !row.indices.isEmpty { rows.append(row) }
    return rows
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
    FlowLayout(spacing: Space.s) {
      ForEach(names, id: \.self) { name in
        let isMine = name.localizedCaseInsensitiveCompare(highlighted ?? "") == .orderedSame
        Text(verbatim: name)
          .textRole(isMine ? .bodyEmphasis : .body)
          .foregroundStyle(isMine ? AnyShapeStyle(.themeAccent) : AnyShapeStyle(.primary))
          .lineLimit(1)
          .padding(.horizontal, Space.m)
          .frame(minHeight: Size.target - Space.s)
          .background(.panel, in: .capsule)
          .overlay { Capsule().strokeBorder(.panelStroke, lineWidth: 1) }
          .transition(.scale.combined(with: .opacity))
      }
    }
    .motion(.pop, value: names)
    .accessibilityElement(children: .combine)
  }
}
