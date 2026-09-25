import DesignSystem
import Observation
import SwiftUI
import UIKit

/// A TV showing the game to the room: an Apple TV or AirPlay TV the phone is
/// mirroring to, or a display on a cable.
///
/// iOS gives the app a second scene for a connected display. Rather than a
/// copy of the phone, the room gets the game as a game show would put it up —
/// the join code, each question with its clock, the reveal, the standings
/// (`BigScreenView`) — while the phone keeps its own screens and controls.
/// Any phone in a game can do it; it's usually the host's.
@Observable
final class BigScreen {
  /// Displays showing the game right now: almost always none or one.
  fileprivate(set) var displays = 0

  var isConnected: Bool { displays > 0 }
}

/// Hands a connected display the big screen, instead of a mirror of the phone.
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
    #if DEBUG
    UITestSettings.apply()
    #endif
    return true
  }

  func application(
    _ application: UIApplication,
    configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
    if session.role == .windowExternalDisplayNonInteractive {
      configuration.delegateClass = BigScreenSceneDelegate.self
    }
    return configuration
  }
}

final class BigScreenSceneDelegate: NSObject, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options: UIScene.ConnectionOptions) {
    guard let scene = scene as? UIWindowScene else { return }
    let models = AppModels.shared
    let window = UIWindow(windowScene: scene)
    window.overrideUserInterfaceStyle = .dark
    window.rootViewController = UIHostingController(
      rootView: BigScreenView()
        .chosenTheme()
        .environment(\.backdropFollowsTilt, false)
        .environment(models.store)
        .environment(models.host)
        .environment(models.shop)
    )
    window.isHidden = false
    self.window = window
    models.bigScreen.displays += 1
  }

  func sceneDidDisconnect(_ scene: UIScene) {
    guard window != nil else { return }
    window = nil
    AppModels.shared.bigScreen.displays -= 1
  }
}
