#if DEBUG
import UIKit

/// Settings a UI test can't reach from outside the app. Launched with
/// `-increaseContrast YES`, every scene gets the trait Increase Contrast gives
/// it — what the system's glass and the design system's palette both read —
/// so a test sees the app as that setting draws it. `-resetTutorial YES`
/// forgets the tutorial was seen, so it shows as on a first launch — and,
/// unlike `-tutorialSeen NO`, finishing it still sticks.
enum UITestSettings {
  private static var observer: (any NSObjectProtocol)?

  static func apply() {
    if UserDefaults.standard.bool(forKey: "resetTutorial") {
      UserDefaults.standard.removeObject(forKey: TutorialPage.seenKey)
    }
    guard UserDefaults.standard.bool(forKey: "increaseContrast") else { return }
    observer = NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { note in
      let scene = note.object as? UIWindowScene
      MainActor.assumeIsolated { scene?.traitOverrides.accessibilityContrast = .high }
    }
  }
}
#endif
