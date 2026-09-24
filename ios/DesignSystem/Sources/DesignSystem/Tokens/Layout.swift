import SwiftUI

/// The spacing scale: a 4-pt base. Related things sit `s` apart, a group
/// `m`, sections `xl`.
nonisolated public enum Space {
  public static let xxs: CGFloat = 2
  public static let xs: CGFloat = 4
  public static let s: CGFloat = 8
  public static let m: CGFloat = 12
  public static let l: CGFloat = 16
  public static let xl: CGFloat = 24
  public static let xxl: CGFloat = 32
  public static let xxxl: CGFloat = 48

  /// The screen's side margin, as the system's lists inset.
  public static let screen: CGFloat = l
}

/// Corner radii. Nested shapes are concentric: an inner radius is its
/// container's minus the inset between them, never below `minimum`.
nonisolated public enum Radius {
  /// Answers, fields, PIN cells.
  public static let control: CGFloat = 20
  /// Readouts, cards.
  public static let panel: CGFloat = 24
  /// The floor for anything nested.
  public static let minimum: CGFloat = 8

  public static func concentric(in outer: CGFloat, inset: CGFloat) -> CGFloat {
    max(outer - inset, minimum)
  }
}

/// Fixed dimensions. Anything touchable is at least `target` in both directions.
nonisolated public enum Size {
  /// The smallest touch target: 44 × 44 pt.
  public static let target: CGFloat = 44
  /// An answer button's minimum height.
  public static let answer: CGFloat = 60
  /// A text field drawn by the design system.
  public static let field: CGFloat = 56
  /// The game picker, with its two lines.
  public static let picker: CGFloat = 64
  /// One PIN cell.
  public static let pinCell: CGFloat = 72
  /// The verdict badge and the waiting badge.
  public static let badge: CGFloat = 92
  /// A status dot.
  public static let dot: CGFloat = 7
  /// The QR code on a card, and at full size.
  public static let qrCard: CGFloat = 112
  public static let qrFull: CGFloat = 240
  /// A theme swatch in the shop.
  public static let swatch: CGFloat = 52
  /// An app icon tile in the shop.
  public static let iconTile: CGFloat = 64
  /// The widest a column of game gets, on iPad.
  public static let column: CGFloat = 540
  /// The largest text a pinned bar grows to: the first accessibility size.
  /// Past it, a bar would cover the content it's for.
  public static let barTypeLimit = DynamicTypeSize.accessibility1
  /// A podium step's height, by place.
  public static func podiumStep(_ medal: Medal) -> CGFloat {
    switch medal {
    case .first: 112
    case .second: 84
    case .third: 64
    }
  }
}

/// The TV board's layout, in points on its 1920×1080 canvas.
nonisolated public enum TVMetrics {
  public static let canvas = CGSize(width: 1920, height: 1080)
  /// TVs crop their edges: everything stays inside the title-safe area.
  public static let safeInsets = EdgeInsets(top: 64, leading: 110, bottom: 64, trailing: 110)
  public static let gap: CGFloat = 36
  public static let wideGap: CGFloat = 110
  public static let tileGap: CGFloat = 28
  public static let rowGap: CGFloat = 12
  public static let textWidth: CGFloat = 1540
  public static let tableWidth: CGFloat = 1400
  public static let podiumWidth: CGFloat = 1500
  public static let instructionWidth: CGFloat = 900
  public static let qr: CGFloat = 400
  public static let tileHeight: CGFloat = 150
  public static let rowHeight: CGFloat = 76
  public static let nameHeight: CGFloat = 64
  public static let tileRadius: CGFloat = 28
  public static let rowRadius: CGFloat = 18
  public static let stepRadius: CGFloat = 24
  public static let keyWidth: CGFloat = 110
  public static let rankWidth: CGFloat = 90
  public static let voteBar: CGFloat = 10
  public static let progressScale: CGFloat = 2.5

  public static func podiumStep(_ medal: Medal) -> CGFloat {
    switch medal {
    case .first: 360
    case .second: 270
    case .third: 200
    }
  }
}
