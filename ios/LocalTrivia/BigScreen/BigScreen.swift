import DesignSystem
import Observation
import SwiftUI

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
  /// Whether a TV is showing the game right now.
  fileprivate(set) var isConnected = false
}

extension View {
  /// Offers a connected TV the game for the room (`BigScreenView`) in place
  /// of a mirror of the phone.
  ///
  /// Since iOS 27 the system connects a display's scene only for a scene
  /// accessory the app has registered, from a view that's on screen — so this
  /// goes on the phone's root view, which is always there. An app that only
  /// answers `application(_:configurationForConnecting:options:)` for the
  /// external-display role, as iOS 26 and earlier allowed, is never asked:
  /// the TV just mirrors the phone.
  func offersBigScreen(_ models: AppModels) -> some View {
    sceneAccessory {
      ExternalNonInteractiveAccessory {
        // A scene of its own, outside the phone's window: hand it the models
        // rather than count on the environment reaching it.
        BigScreenView()
          .chosenTheme()
          .environment(\.backdropFollowsTilt, false)
          .environment(models.store)
          .environment(models.host)
          .environment(models.looks)
      }
      .onAvailabilityChange { isAvailable in
        models.bigScreen.isConnected = isAvailable
      }
    }
  }
}
