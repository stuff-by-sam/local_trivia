#if DEBUG
import DesignSystem
import SwiftUI
import UIKit

/// Settings a UI test can't reach from outside the app. Launched with
/// `-increaseContrast YES`, every scene gets the trait Increase Contrast gives
/// it — what the system's glass and the design system's palette both read —
/// so a test sees the app as that setting draws it. `-resetTutorial YES`
/// forgets the tutorial was seen, so it shows as on a first launch — and,
/// unlike `-tutorialSeen NO`, finishing it still sticks. `-showsFold YES`
/// draws where a `Spread` folds: the hinge, on iPhone Duo.
enum UITestSettings {
  private static var observer: (any NSObjectProtocol)?

  static func apply() {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: "resetTutorial") {
      defaults.removeObject(forKey: TutorialPage.seenKey)
    }
    guard defaults.bool(forKey: "increaseContrast") else { return }
    observer = NotificationCenter.default.addObserver(forName: UIScene.willConnectNotification, object: nil, queue: .main) { note in
      let scene = note.object as? UIWindowScene
      MainActor.assumeIsolated { scene?.traitOverrides.accessibilityContrast = .high }
    }
  }

  static var showsFold: Bool { UserDefaults.standard.bool(forKey: "showsFold") }
}

extension View {
  /// Under `-showsFold YES`: on a screen with room to spread, the middle of
  /// the window along its longer side — where a `Spread` folds — and the
  /// gutter either side of it; and on iPhone Duo, the hinge where iOS reports
  /// it: an outline while the phone's flat, filled once it's folded.
  func foldGuide() -> some View {
    overlay {
      if UITestSettings.showsFold { FoldGuide() }
    }
  }
}

private struct FoldGuide: View {
  @Environment(\.hasRoomToSpread) private var spreads

  var body: some View {
    GeometryReader { proxy in
      if spreads {
        let isSideBySide = proxy.size.width >= proxy.size.height
        ZStack {
          Rectangle()
            .fill(.danger.opacity(0.15))
            .frame(width: isSideBySide ? Space.fold : nil, height: isSideBySide ? nil : Space.fold)
          Rectangle()
            .fill(.danger)
            .frame(width: isSideBySide ? 1 : nil, height: isSideBySide ? nil : 1)
        }
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
      }
      if #available(iOS 27.1, *) {
        ForEach(proxy.reservedRegions(kind: .division, options: .includeInactive)) { hinge in
          Rectangle()
            .fill(.warning.opacity(hinge.isActive ? 0.35 : 0))
            .stroke(.warning, lineWidth: 2)
            .frame(width: max(hinge.frame.width, 2), height: max(hinge.frame.height, 2))
            .position(x: hinge.frame.midX, y: hinge.frame.midY)
        }
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
  }
}
#endif
