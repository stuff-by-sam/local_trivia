import DesignSystem
import SwiftUI

/// The home screen icon: the answer set on its ink, as the classic icon has
/// it, recoloured — one to match each theme. Classic is the app's own; the
/// rest are sold in the shop.
///
/// Each alternate is an Icon Composer file beside the classic one
/// (`AppIcon-Amber.icon`, …), named in the target's alternate app icon
/// setting. `IconArtwork` draws the same layers, for choosing between them.
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

  /// How it's painted, for drawing it in the shop.
  var design: IconDesign { IconDesign(rawValue: rawValue) ?? .classic }
}
