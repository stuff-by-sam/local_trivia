import DesignSystem
import Foundation
import Testing

@testable import LocalTrivia

/// This phone's look: every theme, marker set and icon is free to pick, and a
/// pick stays picked.
struct LooksTests {
  let defaults = UserDefaults(suiteName: "com.stuffbysam.localtrivia.tests.looks.\(UUID().uuidString)")!
  let icons = FakeIcons()

  @Test func startsInTheGamesOwnLook() {
    let looks = Looks(defaults: defaults, icons: icons)
    looks.start()
    #expect(looks.theme == .phosphor)
    #expect(looks.markers == .classic)
    #expect(looks.icon == .classic)
  }

  /// Nothing is locked: any theme or set goes on when it's picked, and is
  /// still on at the next launch.
  @Test func remembersWhatsPicked() {
    let looks = Looks(defaults: defaults, icons: icons)
    for theme in Theme.allCases {
      looks.wear(theme)
      #expect(looks.theme == theme)
    }
    for markers in AnswerMarkers.allCases {
      looks.wear(markers)
      #expect(looks.markers == markers)
    }
    looks.wear(Theme.amber)
    looks.wear(AnswerMarkers.suits)

    let relaunched = Looks(defaults: defaults, icons: icons)
    #expect(relaunched.theme == .amber)
    #expect(relaunched.markers == .suits)
  }

  /// A saved pick this build doesn't know — from a newer one, say — falls
  /// back to the game's own.
  @Test func forgetsAPickItDoesntKnow() {
    defaults.set("vaporwave", forKey: "theme")
    defaults.set("runes", forKey: "markers")
    let looks = Looks(defaults: defaults, icons: icons)
    #expect(looks.theme == .phosphor)
    #expect(looks.markers == .classic)
  }

  @Test func putsAnIconOnTheHomeScreen() async {
    let looks = Looks(defaults: defaults, icons: icons)
    await looks.setIcon(.gold)
    #expect(looks.icon == .gold)
    #expect(icons.alternateIconName == "AppIcon-Gold")

    await looks.setIcon(.classic)
    #expect(looks.icon == .classic)
    #expect(icons.alternateIconName == nil)

    // At launch, it reads what iOS kept.
    try? await icons.setAlternateIconName("AppIcon-Noir")
    let relaunched = Looks(defaults: defaults, icons: icons)
    relaunched.start()
    #expect(relaunched.icon == .noir)
  }

  @Test func saysWhenTheIconCouldntChange() async {
    icons.fails = true
    let looks = Looks(defaults: defaults, icons: icons)
    await looks.setIcon(.cobalt)
    #expect(looks.icon == .classic)
    #expect(looks.notice != nil)
  }

  /// Every alternate icon is built into the app under the name it's set by.
  @Test func everyAlternateIconIsInTheApp() throws {
    let icons = try #require(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
    let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
    for icon in AppIcon.allCases {
      guard let name = icon.alternateName else { continue }
      #expect(alternates[name] != nil, "\(name) isn't in the app")
      #expect(AppIcon(alternateName: name) == icon)
    }
  }
}

/// Keeps the icon to itself rather than changing the simulator's.
final class FakeIcons: IconSwitcher {
  struct Refused: Error {}

  var supportsAlternateIcons: Bool { true }
  private(set) var alternateIconName: String?
  var fails = false

  func setAlternateIconName(_ name: String?) async throws {
    if fails { throw Refused() }
    alternateIconName = name
  }
}
