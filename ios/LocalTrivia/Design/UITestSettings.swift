#if DEBUG
import UIKit

/// Display settings a UI test can't reach from outside the app. Launched with
/// `-increaseContrast YES`, every scene gets the trait Increase Contrast gives
/// it — what the system's glass and the design system's palette both read —
/// so a test sees the app as that setting draws it.
enum UITestSettings {
  private static var observer: (any NSObjectProtocol)?

  static func apply() {
    guard UserDefaults.standard.bool(forKey: "increaseContrast") else { return }
    observer = NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { note in
      let scene = note.object as? UIWindowScene
      MainActor.assumeIsolated { scene?.traitOverrides.accessibilityContrast = .high }
    }
  }
}
#endif
