import DesignSystem
import SwiftUI

extension View {
  /// Dresses everything inside in the theme and the answer markers this phone
  /// chose.
  func chosenTheme() -> some View {
    modifier(ChosenLooks())
  }
}

private struct ChosenLooks: ViewModifier {
  @Environment(Looks.self) private var looks

  func body(content: Content) -> some View {
    content
      .theme(looks.theme)
      .environment(\.answerMarkers, looks.markers)
  }
}
