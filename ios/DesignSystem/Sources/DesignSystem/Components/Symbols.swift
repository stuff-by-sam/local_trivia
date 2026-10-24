import SwiftUI
import UIKit

/// SF Symbols, and the few the design system draws itself in their format
/// (`Resources/Symbols.xcassets`): marks SF Symbols hasn't got, such as the
/// Critters' fox. Each is an SF Symbol template, so it sizes, weights and
/// aligns with the font around it like a system symbol.
nonisolated public enum Symbols {
  /// The design system's own, by name.
  static let custom: Set<String> = ["fox.fill"]

  /// `name` as an image that sizes with the font around it.
  public static func image(_ name: String) -> Image {
    custom.contains(name) ? Image(name, bundle: .module) : Image(systemName: name)
  }

  /// `name` drawn by UIKit: for tracing it, and for checking it exists.
  public static func uiImage(_ name: String, configuration: UIImage.SymbolConfiguration? = nil) -> UIImage? {
    custom.contains(name)
      ? UIImage(named: name, in: .module, with: configuration)
      : UIImage(systemName: name, withConfiguration: configuration)
  }

  /// `name`'s width over its height, as the system lays it out.
  static func aspectRatio(_ name: String) -> CGFloat {
    guard let size = uiImage(name)?.size, size.height > 0 else { return 1 }
    return size.width / size.height
  }
}
