import SwiftUI

@main
struct LocalTriviaApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
  private let models = AppModels.shared

  var body: some Scene {
    WindowGroup {
      #if DEBUG
      if let fixture = ScreenPreview.fromLaunchArguments() {
        fixture
      } else {
        game
      }
      #else
      game
      #endif
    }
  }

  private var game: some View {
    RootView()
      .chosenTheme()
      .environment(models.store)
      .environment(models.browser)
      .environment(models.host)
      .environment(models.bigScreen)
      .environment(models.shop)
  }
}

/// The app's models, one of each. The phone's window and a TV's share them,
/// and UIKit creates the TV's scene outside SwiftUI — so this is where it
/// finds them.
final class AppModels {
  static let shared = AppModels()

  let store = GameStore()
  let browser = GameBrowser()
  let host = HostController()
  let bigScreen = BigScreen()
  let shop = Shop()
}
