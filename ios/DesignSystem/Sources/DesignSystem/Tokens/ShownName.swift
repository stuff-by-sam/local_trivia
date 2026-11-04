import SwiftUI

/// A name the player sees: one of the design system's own, translated where
/// it's read, or one the player gave — a theme or a set of markers of theirs.
nonisolated public enum ShownName: Equatable, Hashable, Sendable {
  case builtIn(LocalizedStringResource)
  case own(String)

  /// The name in the reader's language.
  public var string: String {
    switch self {
    case .builtIn(let resource): String(localized: resource)
    case .own(let name): name
    }
  }

  // `LocalizedStringResource` isn't `Hashable`; its key is what names it.
  public func hash(into hasher: inout Hasher) {
    switch self {
    case .builtIn(let resource):
      hasher.combine(0)
      hasher.combine(resource.key)
    case .own(let name):
      hasher.combine(1)
      hasher.combine(name)
    }
  }
}

extension Text {
  /// `name`, translated if it's the design system's own and verbatim if it's
  /// the player's.
  public init(_ name: ShownName) {
    switch name {
    case .builtIn(let resource): self.init(resource)
    case .own(let name): self.init(verbatim: name)
    }
  }
}
