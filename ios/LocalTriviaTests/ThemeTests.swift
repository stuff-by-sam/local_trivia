import DesignSystem
import SwiftUI
import Testing
import UIKit

@testable import LocalTrivia

/// What every theme has to keep, whoever adds the next one.
struct ThemeTests {
  /// The accent is text on the theme's ink, and `onAccentInk` is text on the
  /// accent wherever a control is lit with it. Both hold to WCAG AAA.
  @Test func everyThemeStaysReadable() {
    for theme in Theme.builtIn {
      expectReadable(theme)
    }
  }

  /// Whatever colour a player picks — black, pure blue, a dark red — their
  /// theme reads as well as the game's own: it's lightened as far as it
  /// takes, keeping its hue.
  @Test func anyColorAPlayerPicksIsMadeReadable() {
    let levels: [UInt32] = [0x00, 0x33, 0x80, 0xCC, 0xFF]
    for red in levels {
      for green in levels {
        for blue in levels {
          let color = red << 16 | green << 8 | blue
          expectReadable(Theme.own(id: "test", name: "Test", color: color, texture: .scanlines))
        }
      }
    }
    // Blue stays blue: lighter, never another hue.
    let blue = Theme.own(id: "test", name: "Test", color: 0x0000FF, texture: .grid)
    var red: CGFloat = 0, green: CGFloat = 0, blueness: CGFloat = 0, alpha: CGFloat = 0
    UIColor(blue.accent).getRed(&red, green: &green, blue: &blueness, alpha: &alpha)
    #expect(blueness > red && blueness > green, "pure blue became \(blue.webAccent)")
  }

  /// The editor's suggestions need no lightening: what you tap is what you get.
  @Test func suggestionsAreReadableAsTheyAre() {
    for suggestion in Theme.suggestions {
      #expect(!Theme.isLightened(suggestion.color), "\(String(localized: suggestion.name)) has to be lightened")
    }
    #expect(Set(Theme.suggestions.map { String(localized: $0.name) }).count == Theme.suggestions.count)
  }

  /// A hosting phone's browser players wear its theme's accent, so the
  /// colour the web gets has to be the one the app draws.
  @Test func givesTheWebPlayerTheSameAccent() throws {
    #expect(Theme.phosphor.webAccent == "#56ff8a", "the web player's own green, so it stays unrotated")
    let own = Theme.own(id: "test", name: "Test", color: 0x123456, texture: .chalk)
    for theme in Theme.builtIn + [own] {
      #expect(theme.webAccent.wholeMatch(of: /#[0-9a-f]{6}/) != nil, "\(theme.id): \(theme.webAccent)")
      let hex = try #require(Int(theme.webAccent.dropFirst(), radix: 16))
      var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
      UIColor(theme.accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      #expect([red, green, blue].map { Int(($0 * 255).rounded()) } == [hex >> 16 & 0xFF, hex >> 8 & 0xFF, hex & 0xFF], "\(theme.id)")
    }
  }

  /// The colour picker's colour comes back as the hex it was made from.
  @Test func readsAPickedColorBack() {
    for suggestion in Theme.suggestions {
      #expect(Theme.rgb(of: Theme.color(suggestion.color)) == suggestion.color)
    }
  }

  /// Every built-in theme is found by its id, and only those.
  @Test func findsBuiltInThemesByID() {
    for theme in Theme.builtIn {
      #expect(Theme.builtIn(id: theme.id) == theme)
    }
    #expect(Theme.builtIn(id: "own-123") == nil)
    #expect(Set(Theme.builtIn.map(\.id)).count == Theme.builtIn.count)
  }

  private func expectReadable(_ theme: Theme) {
    #expect(contrast(theme.accent, theme.ink) >= 7, "\(theme.id) \(theme.webAccent): accent on its ink")
    #expect(contrast(Palette.onAccentInk, theme.accent) >= 7, "\(theme.id) \(theme.webAccent): ink on a lit control")
    #expect(contrast(.white, theme.ink) >= 12, "\(theme.id): text on its ink")
  }

  private func contrast(_ a: Color, _ b: Color) -> Double {
    let (one, other) = (luminance(a), luminance(b))
    return (max(one, other) + 0.05) / (min(one, other) + 0.05)
  }

  /// WCAG relative luminance, from the colour's sRGB components.
  private func luminance(_ color: Color) -> Double {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    func linear(_ component: CGFloat) -> Double {
      let c = Double(component)
      return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }
}

/// What every set of answer markers has to keep, whoever adds the next one.
struct AnswerMarkersTests {
  /// Four shapes that exist, that differ, and that VoiceOver names apart —
  /// the shapes are how a colour-blind player tells the answers apart.
  @Test func everySetHasFourShapesToTellApart() {
    for markers in AnswerMarkers.builtIn {
      let symbols = AnswerStyle.allCases.map { markers.symbol(for: $0) }
      let names = AnswerStyle.allCases.map { String(localized: markers.shapeName(for: $0)) }
      #expect(Set(symbols).count == 4, "\(markers.id): \(symbols)")
      #expect(Set(names).count == 4, "\(markers.id): \(names)")
      for symbol in symbols {
        #expect(Symbols.uiImage(symbol) != nil, "\(markers.id): no symbol \(symbol)")
      }
    }
  }

  /// Classic is what the TV's web presenter and the web player draw.
  @Test func classicIsTheWebGamesSet() {
    #expect(AnswerStyle.allCases.map { AnswerMarkers.classic.symbol(for: $0) } == ["circle.fill", "triangle.fill", "square.fill", "diamond.fill"])
  }

  /// Every shape a player can choose exists on this system, appears once,
  /// and has a name of its own — so any four of them are spoken apart.
  @Test func everyLibraryShapeExistsWithItsOwnName() {
    let library = MarkerShape.library
    #expect(library.count >= 140, "the library has \(library.count)")
    #expect(Set(library.map(\.symbol)).count == library.count, "a symbol appears twice")
    let names = library.map { String(localized: $0.name) }
    #expect(Set(names).count == names.count, "a name appears twice: \(Dictionary(grouping: names) { $0 }.filter { $1.count > 1 }.keys)")
    for shape in library {
      #expect(Symbols.uiImage(shape.symbol) != nil, "no symbol \(shape.symbol)")
      // Nothing that reads as right or wrong, or as one of the app's own controls.
      #expect(!["checkmark", "xmark", "questionmark", "exclamationmark", "hand.thumbs", "hourglass", "apple"].contains { shape.symbol.hasPrefix($0) }, "\(shape.symbol)")
    }
    for category in MarkerShape.Category.allCases {
      #expect(library.contains { $0.category == category }, "\(category) is empty")
    }
  }

  /// A built-in set's shapes, and the library's, are found by symbol.
  @Test func findsShapesBySymbol() {
    #expect(MarkerShape.named("fox.fill").map { String(localized: $0.name) } == "fox")
    #expect(MarkerShape.named("suit.heart.fill").map { String(localized: $0.name) } == "heart")
    #expect(MarkerShape.named("no.such.symbol") == nil)
  }

  @Test func findsBuiltInSetsByID() {
    for markers in AnswerMarkers.builtIn {
      #expect(AnswerMarkers.builtIn(id: markers.id) == markers)
    }
    #expect(AnswerMarkers.builtIn(id: "own-123") == nil)
  }

  /// The tagline of a set of the player's own says what's in it.
  @Test func saysWhatsInASetOfThePlayersOwn() {
    let own = AnswerMarkers.own(id: "test", name: "Space", shapes: ["sparkles", "moon.fill", "globe.americas.fill", "airplane"].compactMap(MarkerShape.named))
    #expect(own.tagline.string.hasPrefix("Sparkles, moon, globe"))
    #expect(own.tagline.string.hasSuffix("airplane"))
  }
}

/// A photo behind the glass is dressed so the game reads over it, however
/// bright it was.
struct ThemePhotoTests {
  /// A photo to dress: one colour all over, or a white sky with a red kite.
  private func photo(_ color: UIColor, kite: UIColor? = nil) throws -> URL {
    let url = URL.temporaryDirectory.appending(path: "photo-\(UUID().uuidString).png")
    let image = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 600)).pngData { context in
      color.setFill()
      context.fill(CGRect(x: 0, y: 0, width: 400, height: 600))
      if let kite {
        kite.setFill()
        context.fill(CGRect(x: 120, y: 160, width: 160, height: 160))
      }
    }
    try image.write(to: url)
    return url
  }

  /// The average and brightest relative luminance of a dressed photo.
  private func light(of data: Data) throws -> (average: Double, brightest: Double) {
    let image = try #require(UIImage(data: data)?.cgImage)
    let (width, height) = (image.width, image.height)
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = try #require(
      CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    func linear(_ byte: UInt8) -> Double {
      let c = Double(byte) / 255
      return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    var total = 0.0, brightest = 0.0
    for pixel in stride(from: 0, to: pixels.count, by: 4) {
      let l = 0.2126 * linear(pixels[pixel]) + 0.7152 * linear(pixels[pixel + 1]) + 0.0722 * linear(pixels[pixel + 2])
      total += l
      brightest = max(brightest, l)
    }
    return (total / Double(width * height), brightest)
  }

  @Test func dimsABrightPhotoForTheGlass() throws {
    let dressed = try #require(ThemePhoto.dress(contentsOf: try photo(.white, kite: .systemRed)))
    let (average, brightest) = try light(of: dressed)
    // A little over the marks: JPEG and rounding.
    #expect(average <= 0.035, "average light \(average)")
    #expect(brightest <= 0.16, "brightest light \(brightest)")
  }

  @Test func refusesWhatIsntAPhoto() throws {
    let url = URL.temporaryDirectory.appending(path: "not-a-photo-\(UUID().uuidString).jpg")
    try Data("hello".utf8).write(to: url)
    #expect(ThemePhoto.dress(contentsOf: url) == nil)
  }

  /// The red kite, not the white sky, is the colour offered.
  @Test func offersAPhotosMostVividColor() throws {
    let color = try #require(ThemePhoto.suggestedColor(in: try photo(.white, kite: .systemRed)))
    let red = Double((color >> 16) & 0xFF), green = Double((color >> 8) & 0xFF), blue = Double(color & 0xFF)
    #expect(red > green * 1.5 && red > blue * 1.5, "offered #\(String(color, radix: 16))")
    #expect(ThemePhoto.suggestedColor(in: try photo(.gray)) == nil, "a grey photo has no colour to offer")
  }
}
