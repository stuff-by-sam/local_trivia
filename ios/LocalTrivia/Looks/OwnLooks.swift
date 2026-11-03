import DesignSystem
import Foundation

/// A theme the player made, as it's kept: their name for it, the colour they
/// picked, and the backdrop it's over — one of the game's, or a photo of
/// theirs (a file in `Looks.photos`).
struct OwnTheme: Codable, Identifiable, Hashable {
  var id: String
  var name: String
  var color: UInt32
  /// A `Backdrop.Texture`, by its raw value: one this build doesn't know —
  /// from a newer one — reads as scanlines.
  var texture: String
  /// The photo's file name, if it's over one.
  var photo: String?

  init(id: String = "own-" + UUID().uuidString, name: String, color: UInt32, texture: Backdrop.Texture, photo: String? = nil) {
    self.id = id
    self.name = name
    self.color = color
    self.texture = texture.rawValue
    self.photo = photo
  }

  /// A new one that starts from `theme`: its colour and its backdrop.
  init(startingFrom theme: Theme, name: String) {
    self.init(name: name, color: theme.pickedColor ?? Theme.rgb(of: theme.accent), texture: theme.texture)
  }

  var backdrop: Backdrop.Texture {
    get { Backdrop.Texture(rawValue: texture) ?? .scanlines }
    set { texture = newValue.rawValue }
  }

  /// The theme, with its photo where `photos` keeps it.
  func theme(photos: URL) -> Theme {
    theme(photo: photo.map { ThemePhoto(url: photos.appending(path: $0)) })
  }

  /// The theme over `photo` — one an editor has dressed but not kept yet.
  func theme(photo: ThemePhoto?) -> Theme {
    .own(id: id, name: displayName, color: color, texture: backdrop, photo: photo)
  }

  /// Its name, or what it's called until it has one.
  var displayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? String(localized: "My Theme") : trimmed
  }
}

/// A set of markers the player made: their name for it, and its four
/// shapes, A to D, by SF Symbol name.
struct OwnMarkers: Codable, Identifiable, Hashable {
  var id: String
  var name: String
  var symbols: [String]

  init(id: String = "own-" + UUID().uuidString, name: String, symbols: [String]) {
    self.id = id
    self.name = name
    self.symbols = symbols
  }

  /// A new one that starts from `markers`' four shapes.
  init(startingFrom markers: AnswerMarkers, name: String) {
    self.init(name: name, symbols: markers.shapes.map(\.symbol))
  }

  var shapes: [MarkerShape] {
    symbols.compactMap(MarkerShape.named)
  }

  var markers: AnswerMarkers {
    .own(id: id, name: displayName, shapes: shapes)
  }

  var displayName: String {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? String(localized: "My Markers") : trimmed
  }

  /// Four different shapes: what a set needs before it's kept.
  var isComplete: Bool {
    shapes.count == AnswerStyle.allCases.count && Set(symbols).count == AnswerStyle.allCases.count
  }
}
