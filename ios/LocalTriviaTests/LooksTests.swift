import DesignSystem
import Foundation
import Testing

@testable import LocalTrivia

/// This phone's look: every theme and marker set is free to pick and to
/// make, and a pick — or something made — stays.
struct LooksTests {
  let defaults = UserDefaults(suiteName: "com.stuffbysam.localtrivia.tests.looks.\(UUID().uuidString)")!
  let photos = URL.temporaryDirectory.appending(path: "LooksTests-\(UUID().uuidString)", directoryHint: .isDirectory)

  private func looks() -> Looks {
    Looks(defaults: defaults, photos: photos)
  }

  /// A photo file, as an editor leaves one once it's dressed.
  private func dressedPhoto() throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "dressed-\(UUID().uuidString).jpg")
    try Data([0xFF, 0xD8, 0xFF]).write(to: url)
    return url
  }

  @Test func startsInTheGamesOwnLook() {
    let looks = looks()
    #expect(looks.theme == .phosphor)
    #expect(looks.markers == .classic)
    #expect(looks.themes == Theme.builtIn)
    #expect(looks.markerSets == AnswerMarkers.builtIn)
  }

  /// Nothing is locked: any theme or set goes on when it's picked, and is
  /// still on at the next launch.
  @Test func remembersWhatsPicked() {
    let looks = looks()
    for theme in Theme.builtIn {
      looks.wear(theme)
      #expect(looks.theme == theme)
    }
    for markers in AnswerMarkers.builtIn {
      looks.wear(markers)
      #expect(looks.markers == markers)
    }
    looks.wear(Theme.amber)
    looks.wear(AnswerMarkers.suits)

    let relaunched = self.looks()
    #expect(relaunched.theme == .amber)
    #expect(relaunched.markers == .suits)
  }

  /// A saved pick this build doesn't know — from a newer one, say, or one
  /// since deleted — falls back to the game's own.
  @Test func forgetsAPickItDoesntKnow() {
    defaults.set("vaporwave", forKey: "theme")
    defaults.set("runes", forKey: "markers")
    let looks = looks()
    #expect(looks.theme == .phosphor)
    #expect(looks.markers == .classic)
  }

  @Test func keepsAThemeOfThePlayersOwn() throws {
    let looks = looks()
    let own = OwnTheme(name: "Night Swim", color: Theme.suggestions[2].color, texture: .deepWater)
    try looks.keep(own)
    #expect(looks.theme.id == own.id)
    #expect(looks.theme.name == .own("Night Swim"))
    #expect(looks.theme.texture == .deepWater)
    #expect(looks.themes.last?.id == own.id)

    let relaunched = self.looks()
    #expect(relaunched.ownThemes == [own])
    #expect(relaunched.theme == own.theme(photos: photos))
  }

  /// Saving one that's being edited changes it where it is.
  @Test func changingAThemeKeepsItsPlace() throws {
    let looks = looks()
    var first = OwnTheme(name: "One", color: Theme.suggestions[0].color, texture: .grid)
    let second = OwnTheme(name: "Two", color: Theme.suggestions[1].color, texture: .chalk)
    try looks.keep(first)
    try looks.keep(second)
    first.name = "Uno"
    first.backdrop = .embers
    try looks.keep(first)
    #expect(looks.ownThemes.map(\.name) == ["Uno", "Two"])
    #expect(looks.theme.texture == .embers)
  }

  /// Deleting the theme being worn puts the game's own back on; undoing puts
  /// it back where it was, and back on.
  @Test func deletingTheWornThemeFallsBackUntilUndone() throws {
    let looks = looks()
    let one = OwnTheme(name: "One", color: Theme.suggestions[3].color, texture: .aurora)
    let two = OwnTheme(name: "Two", color: Theme.suggestions[4].color, texture: .horizon)
    try looks.keep(one)
    try looks.keep(two)
    looks.wear(one.theme(photos: photos))
    looks.remove(one)
    #expect(looks.theme == .phosphor)
    #expect(looks.ownThemes == [two])

    looks.restore(one, at: 0, wearing: true)
    #expect(looks.ownThemes == [one, two])
    #expect(looks.theme.id == one.id)
  }

  @Test func keepsMarkersOfThePlayersOwn() {
    let looks = looks()
    let own = OwnMarkers(name: "Space Race", symbols: ["sparkles", "moon.fill", "globe.americas.fill", "airplane"])
    #expect(own.isComplete)
    looks.keep(own)
    #expect(looks.markers.id == own.id)
    #expect(looks.markers.symbol(for: .c) == "globe.americas.fill")
    #expect(String(localized: looks.markers.shapeName(for: .d)) == "airplane")

    looks.remove(own)
    #expect(looks.markers == .classic)
    looks.restore(own, at: 0, wearing: true)

    let relaunched = self.looks()
    #expect(relaunched.markers.id == own.id)
    #expect(relaunched.markerSets.last?.id == own.id)
  }

  /// A photo an editor dressed moves in with its theme; one it replaces is
  /// let go — unless a duplicate still shows it.
  @Test func movesPhotosInAndLetsReplacedOnesGo() throws {
    let looks = looks()
    var own = OwnTheme(name: "Beach", color: Theme.suggestions[9].color, texture: .scanlines)
    try looks.keep(own, newPhoto: try dressedPhoto())
    own = try #require(looks.ownTheme(own.id))
    let first = try #require(own.photo)
    #expect(FileManager.default.fileExists(atPath: photos.appending(path: first).path(percentEncoded: false)))
    #expect(looks.theme.photo?.url == photos.appending(path: first))

    // A duplicate shares it…
    var copy = own
    copy.id = "own-copy"
    try looks.keep(copy)
    // …so replacing the original's leaves it for the copy.
    try looks.keep(own, newPhoto: try dressedPhoto())
    #expect(FileManager.default.fileExists(atPath: photos.appending(path: first).path(percentEncoded: false)))

    // Once neither shows it, it goes.
    try looks.keep(copy, newPhoto: try dressedPhoto())
    #expect(!FileManager.default.fileExists(atPath: photos.appending(path: first).path(percentEncoded: false)))
  }

  /// At launch, a photo no theme shows — a deleted theme's, one an editor
  /// left — is let go.
  @Test func letsGoOfPhotosNoThemeShows() throws {
    let looks = looks()
    let own = OwnTheme(name: "Beach", color: Theme.suggestions[9].color, texture: .scanlines)
    try looks.keep(own, newPhoto: try dressedPhoto())
    let kept = try #require(looks.ownTheme(own.id)?.photo)
    let stray = photos.appending(path: "stray.jpg")
    try Data([1]).write(to: stray)

    looks.start()
    #expect(!FileManager.default.fileExists(atPath: stray.path(percentEncoded: false)))
    #expect(FileManager.default.fileExists(atPath: photos.appending(path: kept).path(percentEncoded: false)))
  }

  @Test func namesANewOneFreshly() {
    let looks = looks()
    #expect(looks.freshName("My Theme", taken: []) == "My Theme")
    #expect(looks.freshName("My Theme", taken: ["My Theme"]) == "My Theme 2")
    #expect(looks.freshName("My Theme", taken: ["My Theme", "My Theme 2"]) == "My Theme 3")
  }

  /// One whose shapes this build doesn't know any more is made up to four.
  @Test func aShortSetIsMadeUpToFour() {
    let own = OwnMarkers(name: "Half", symbols: ["moon.fill", "not.a.symbol"])
    #expect(!own.isComplete)
    let markers = own.markers
    let symbols = AnswerStyle.allCases.map(markers.symbol(for:))
    #expect(symbols.count == 4)
    #expect(Set(symbols).count == 4)
    #expect(symbols.first == "moon.fill")
  }
}
