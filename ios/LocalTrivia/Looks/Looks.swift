import DesignSystem
import Foundation
import Observation
import OSLog

/// How this phone dresses the game: its theme and the shapes beside the
/// answers' letters — ones that come with the game, or the player's own.
/// Every one is free, to pick and to make.
///
/// What's worn and what the player has made are kept in preferences, so
/// they're on screen from the first frame. A theme's photo is a file beside
/// them (`photos`), already dressed for the glass.
@Observable
final class Looks {
  private(set) var theme: Theme {
    didSet { defaults.set(theme.id, forKey: Keys.theme) }
  }
  private(set) var markers: AnswerMarkers {
    didSet { defaults.set(markers.id, forKey: Keys.markers) }
  }
  /// The player's own, in the order they were made.
  private(set) var ownThemes: [OwnTheme] {
    didSet { store(ownThemes, as: Keys.ownThemes) }
  }
  private(set) var ownMarkers: [OwnMarkers] {
    didSet { store(ownMarkers, as: Keys.ownMarkers) }
  }

  /// Where the player's photos are kept.
  @ObservationIgnored let photos: URL
  @ObservationIgnored private let defaults: UserDefaults

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "looks")

  private enum Keys {
    static let theme = "theme"
    static let markers = "markers"
    static let ownThemes = "ownThemes"
    static let ownMarkers = "ownMarkers"
  }

  init(
    defaults: UserDefaults = .standard,
    photos: URL = .applicationSupportDirectory.appending(path: "Looks/Photos", directoryHint: .isDirectory)
  ) {
    self.defaults = defaults
    self.photos = photos
    let ownThemes = Self.load([OwnTheme].self, from: defaults, as: Keys.ownThemes) ?? []
    let ownMarkers = Self.load([OwnMarkers].self, from: defaults, as: Keys.ownMarkers) ?? []
    self.ownThemes = ownThemes
    self.ownMarkers = ownMarkers
    let wornTheme = defaults.string(forKey: Keys.theme)
    let wornMarkers = defaults.string(forKey: Keys.markers)
    theme =
      wornTheme.flatMap(Theme.builtIn(id:))
      ?? ownThemes.first { $0.id == wornTheme }.map { $0.theme(photos: photos) }
      ?? .phosphor
    markers =
      wornMarkers.flatMap(AnswerMarkers.builtIn(id:))
      ?? ownMarkers.first { $0.id == wornMarkers }?.markers
      ?? .classic
  }

  /// Every theme to pick from: the game's, then the player's.
  var themes: [Theme] {
    Theme.builtIn + ownThemes.map { $0.theme(photos: photos) }
  }

  /// Every set of markers to pick from: the game's, then the player's.
  var markerSets: [AnswerMarkers] {
    AnswerMarkers.builtIn + ownMarkers.map(\.markers)
  }

  /// Tidies up once the app is running: a photo no theme shows any more —
  /// one whose theme was deleted, or one an editor left behind — is let go.
  func start() {
    let kept = Set(ownThemes.compactMap(\.photo))
    let files = (try? FileManager.default.contentsOfDirectory(at: photos, includingPropertiesForKeys: nil)) ?? []
    for file in files where !kept.contains(file.lastPathComponent) {
      try? FileManager.default.removeItem(at: file)
    }
  }

  func wear(_ theme: Theme) {
    self.theme = theme
  }

  func wear(_ markers: AnswerMarkers) {
    self.markers = markers
  }

  // MARK: - The player's own

  /// The player's own theme by `id`.
  func ownTheme(_ id: String) -> OwnTheme? {
    ownThemes.first { $0.id == id }
  }

  func ownMarkers(_ id: String) -> OwnMarkers? {
    ownMarkers.first { $0.id == id }
  }

  /// Keeps `own` — new, or in place of the one with its id — and wears it.
  /// A photo at `newPhoto` (one an editor dressed) is moved in with it, and
  /// the one it replaces is let go.
  func keep(_ own: OwnTheme, newPhoto: URL? = nil) throws {
    var own = own
    let replaced = ownTheme(own.id)
    if let newPhoto {
      try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
      let name = UUID().uuidString + ".jpg"
      try FileManager.default.moveItem(at: newPhoto, to: photos.appending(path: name))
      own.photo = name
    }
    if let index = ownThemes.firstIndex(where: { $0.id == own.id }) {
      ownThemes[index] = own
    } else {
      ownThemes.append(own)
    }
    // A duplicate shares its original's photo until one of them changes it.
    if let old = replaced?.photo, !ownThemes.contains(where: { $0.photo == old }) {
      forgetPhoto(old)
    }
    theme = own.theme(photos: photos)
  }

  /// Keeps `own` — new, or in place of the one with its id — and wears it.
  func keep(_ own: OwnMarkers) {
    if let index = ownMarkers.firstIndex(where: { $0.id == own.id }) {
      ownMarkers[index] = own
    } else {
      ownMarkers.append(own)
    }
    markers = own.markers
  }

  /// Takes `own` out of the honeycomb. Its photo stays on the phone until
  /// the next launch, so an undo (`restore`) has it. Whatever was worn falls
  /// back to the game's own if it was this.
  func remove(_ own: OwnTheme) {
    ownThemes.removeAll { $0.id == own.id }
    if theme.id == own.id { theme = .phosphor }
  }

  func remove(_ own: OwnMarkers) {
    ownMarkers.removeAll { $0.id == own.id }
    if markers.id == own.id { markers = .classic }
  }

  /// Puts back one just removed, where it was, as an undo does.
  func restore(_ own: OwnTheme, at index: Int, wearing: Bool) {
    ownThemes.insert(own, at: min(index, ownThemes.count))
    if wearing { theme = own.theme(photos: photos) }
  }

  func restore(_ own: OwnMarkers, at index: Int, wearing: Bool) {
    ownMarkers.insert(own, at: min(index, ownMarkers.count))
    if wearing { markers = own.markers }
  }

  /// A name for a new one that isn't taken: "My Theme", "My Theme 2", …
  func freshName(_ base: String, taken: [String]) -> String {
    guard taken.contains(base) else { return base }
    var number = 2
    while taken.contains("\(base) \(number)") { number += 1 }
    return "\(base) \(number)"
  }

  // MARK: - Keeping

  private func forgetPhoto(_ name: String) {
    let url = photos.appending(path: name)
    ThemePhoto(url: url).forget()
    try? FileManager.default.removeItem(at: url)
  }

  private func store(_ value: some Encodable, as key: String) {
    do {
      defaults.set(try JSONEncoder().encode(value), forKey: key)
    } catch {
      Self.log.error("couldn't keep \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
  }

  private static func load<Value: Decodable>(_ type: Value.Type, from defaults: UserDefaults, as key: String) -> Value? {
    guard let data = defaults.data(forKey: key) else { return nil }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      log.error("couldn't read \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
      return nil
    }
  }
}

#if DEBUG
extension Looks {
  /// Looks kept apart from the app's own, for previews and fixtures.
  static func preview(defaults: UserDefaults) -> Looks {
    Looks(defaults: defaults, photos: .temporaryDirectory.appending(path: "PreviewPhotos", directoryHint: .isDirectory))
  }
}
#endif
