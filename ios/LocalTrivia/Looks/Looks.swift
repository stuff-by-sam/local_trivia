import DesignSystem
import Observation
import OSLog
import UIKit

/// How this phone dresses the game: its theme, the shapes beside the answers'
/// letters, and Trivia's icon on the Home Screen. Every one is free to pick.
///
/// The theme and the markers are kept in preferences, so they're on screen
/// from the first frame. The icon is iOS's to keep; it's read when the app
/// starts.
@Observable
final class Looks {
  private(set) var theme: Theme {
    didSet { defaults.set(theme.rawValue, forKey: Keys.theme) }
  }
  private(set) var markers: AnswerMarkers {
    didSet { defaults.set(markers.rawValue, forKey: Keys.markers) }
  }
  /// What the home screen shows. Read at `start`: iOS keeps it.
  private(set) var icon: AppIcon = .classic
  /// What went wrong changing the icon, when something did.
  var notice: String?

  var canChangeIcon: Bool { icons.supportsAlternateIcons }

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let icons: any IconSwitcher

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "looks")

  private enum Keys {
    static let theme = "theme"
    static let markers = "markers"
  }

  init(defaults: UserDefaults = .standard, icons: any IconSwitcher = HomeScreen()) {
    self.defaults = defaults
    self.icons = icons
    theme = defaults.string(forKey: Keys.theme).flatMap(Theme.init(rawValue:)) ?? .phosphor
    markers = defaults.string(forKey: Keys.markers).flatMap(AnswerMarkers.init(rawValue:)) ?? .classic
  }

  /// Reads the icon iOS is showing, once UIKit has finished launching the app.
  func start() {
    icon = AppIcon(alternateName: icons.alternateIconName)
  }

  func wear(_ theme: Theme) {
    self.theme = theme
  }

  func wear(_ markers: AnswerMarkers) {
    self.markers = markers
  }

  /// Changes the home screen icon. iOS tells the player it has.
  func setIcon(_ icon: AppIcon) async {
    guard icons.supportsAlternateIcons else { return }
    guard icon.alternateName != icons.alternateIconName else {
      self.icon = icon
      return
    }
    do {
      try await icons.setAlternateIconName(icon.alternateName)
      self.icon = icon
    } catch {
      Self.log.error("couldn't change the icon: \(error.localizedDescription, privacy: .public)")
      notice = String(localized: "Couldn't change the icon. Try again in a moment.")
    }
  }
}

/// Where the home screen icon is set: the app itself, or a stand-in in tests.
protocol IconSwitcher {
  var supportsAlternateIcons: Bool { get }
  var alternateIconName: String? { get }
  func setAlternateIconName(_ name: String?) async throws
}

/// The app's own icon. It asks UIKit each time rather than holding on to the
/// application: `Looks` is made before UIKit has finished launching the app.
struct HomeScreen: IconSwitcher {
  var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }
  var alternateIconName: String? { UIApplication.shared.alternateIconName }

  func setAlternateIconName(_ name: String?) async throws {
    try await UIApplication.shared.setAlternateIconName(name)
  }
}

#if DEBUG
extension Looks {
  /// Looks that never touch the real icon, for previews.
  static func preview(defaults: UserDefaults) -> Looks {
    Looks(defaults: defaults, icons: PreviewIcons())
  }
}

private struct PreviewIcons: IconSwitcher {
  var supportsAlternateIcons: Bool { true }
  var alternateIconName: String? { nil }
  func setAlternateIconName(_ name: String?) async throws {}
}
#endif
