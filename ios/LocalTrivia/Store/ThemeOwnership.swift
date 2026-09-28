import DesignSystem
import SwiftUI

extension Theme {
  /// Nil for the one every phone has.
  var productID: String? {
    self == .phosphor ? nil : "com.stuffbysam.localtrivia.theme.\(rawValue)"
  }
}

extension AnswerMarkers {
  /// Nil for the one every phone has.
  var productID: String? {
    self == .classic ? nil : "com.stuffbysam.localtrivia.markers.\(rawValue)"
  }
}

extension View {
  /// Dresses everything inside in the theme and the answer markers this phone
  /// chose in the shop.
  func chosenTheme() -> some View {
    modifier(ChosenTheme())
  }
}

private struct ChosenTheme: ViewModifier {
  @Environment(Shop.self) private var shop

  func body(content: Content) -> some View {
    content
      .theme(shop.theme)
      .environment(\.answerMarkers, shop.markers)
  }
}
