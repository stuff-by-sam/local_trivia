import SwiftUI

/// The four shapes beside the answers' letters. Classic's — circle, triangle,
/// square, diamond — are the game's own, and what the web game shows (`PAL`
/// in public/shared/common.js); ten more sets come with it, and the player
/// can make their own from the shapes in `MarkerShape.library`
/// (`own(id:name:shapes:)`).
///
/// A set is this phone's, like a theme: it dresses this phone and any TV it
/// puts the game on. It changes only the shapes. An answer's letter and
/// colour are the same on every phone in the room, so B is always cyan, and
/// every built-in set's four shapes can be told apart without their colours;
/// a set of the player's own has four different ones.
nonisolated public struct AnswerMarkers: Hashable, Identifiable, Sendable {
  let kind: Kind

  enum Kind: Hashable, Sendable {
    case builtIn(BuiltIn)
    case own(Own)
  }

  /// One the player made: their name for it, and its four shapes, A to D.
  struct Own: Hashable, Sendable {
    let id: String
    let name: String
    let shapes: [MarkerShape]
  }

  public static let classic = AnswerMarkers(kind: .builtIn(.classic))
  public static let suits = AnswerMarkers(kind: .builtIn(.suits))
  public static let elements = AnswerMarkers(kind: .builtIn(.elements))
  public static let sky = AnswerMarkers(kind: .builtIn(.sky))
  public static let critters = AnswerMarkers(kind: .builtIn(.critters))
  public static let smarts = AnswerMarkers(kind: .builtIn(.smarts))
  public static let gameNight = AnswerMarkers(kind: .builtIn(.gameNight))
  public static let party = AnswerMarkers(kind: .builtIn(.party))
  public static let showtime = AnswerMarkers(kind: .builtIn(.showtime))
  public static let quest = AnswerMarkers(kind: .builtIn(.quest))
  public static let backyard = AnswerMarkers(kind: .builtIn(.backyard))

  /// The sets that come with the game, Classic first.
  public static let builtIn: [AnswerMarkers] = BuiltIn.allCases.map { AnswerMarkers(kind: .builtIn($0)) }

  /// The built-in set called `id`, if there is one.
  public static func builtIn(id: String) -> AnswerMarkers? {
    BuiltIn(rawValue: id).map { AnswerMarkers(kind: .builtIn($0)) }
  }

  /// A set of the player's own: `shapes` beside A, B, C and D. Four
  /// different ones; a short list is made up from Classic's.
  public static func own(id: String, name: String, shapes: [MarkerShape]) -> AnswerMarkers {
    var four = Array(shapes.prefix(AnswerStyle.allCases.count))
    for shape in AnswerMarkers.classic.shapes where four.count < AnswerStyle.allCases.count && !four.contains(shape) {
      four.append(shape)
    }
    return AnswerMarkers(kind: .own(Own(id: id, name: name, shapes: four)))
  }

  public var id: String {
    switch kind {
    case .builtIn(let markers): markers.rawValue
    case .own(let markers): markers.id
    }
  }

  public var isBuiltIn: Bool {
    if case .builtIn = kind { true } else { false }
  }

  public var name: ShownName {
    switch kind {
    case .builtIn(let markers): .builtIn(markers.name)
    case .own(let markers): .own(markers.name)
    }
  }

  /// What's in it, in words: "Sun, moon, cloud and star".
  public var tagline: ShownName {
    switch kind {
    case .builtIn(let markers):
      return .builtIn(markers.tagline)
    case .own(let markers):
      let names = markers.shapes.map { String(localized: $0.name) }.formatted(.list(type: .and))
      return .own(names.prefix(1).uppercased() + names.dropFirst())
    }
  }

  /// Its four shapes, A to D.
  public var shapes: [MarkerShape] {
    switch kind {
    case .builtIn(let markers):
      AnswerStyle.allCases.map { MarkerShape(markers.symbol(for: $0), markers.shapeName(for: $0), in: .shapes) }
    case .own(let markers): markers.shapes
    }
  }

  /// The SF Symbol drawn beside `style`'s letter. (The fox is the design
  /// system's own, drawn as an SF Symbol: see `Symbols`.)
  public func symbol(for style: AnswerStyle) -> String {
    switch kind {
    case .builtIn(let markers): markers.symbol(for: style)
    case .own(let markers): markers.shapes[style.rawValue].symbol
    }
  }

  /// What VoiceOver calls `style`'s shape: "B, spade: Saturn".
  public func shapeName(for style: AnswerStyle) -> LocalizedStringResource {
    switch kind {
    case .builtIn(let markers): markers.shapeName(for: style)
    case .own(let markers): markers.shapes[style.rawValue].name
    }
  }
}

// MARK: - The built-in sets

nonisolated extension AnswerMarkers {
  /// The sets that come with the game.
  enum BuiltIn: String, CaseIterable, Sendable {
    case classic, suits, elements, sky, critters
    case smarts, gameNight, party, showtime, quest, backyard

    var name: LocalizedStringResource {
      switch self {
      case .classic: "Classic"
      case .suits: "Suits"
      case .elements: "Elements"
      case .sky: "Sky"
      case .critters: "Critters"
      case .smarts: "Smarts"
      case .gameNight: "Game Night"
      case .party: "Party"
      case .showtime: "Showtime"
      case .quest: "Quest"
      case .backyard: "Backyard"
      }
    }

    var tagline: LocalizedStringResource {
      switch self {
      case .classic: "Circle, triangle, square and diamond: the game's own"
      case .suits: "Clubs, spades, hearts and diamonds, from the card table"
      case .elements: "Leaf, water, fire and lightning"
      case .sky: "Sun, moon, cloud and star"
      case .critters: "A turtle, a fish, a fox and a dog"
      case .smarts: "A light bulb, a book, a brain and a graduation cap: for know-it-alls"
      case .gameNight: "Dice, a puzzle piece, a controller and a crown"
      case .party: "A present, a balloon, a party popper and a cake"
      case .showtime: "Theater masks, a ticket, popcorn and a clapperboard"
      case .quest: "A map, a key, a shield and a flag"
      case .backyard: "A lizard, a bird, a rabbit and a ladybug"
      }
    }

    func symbol(for style: AnswerStyle) -> String {
      let symbols = switch self {
      case .classic: ["circle.fill", "triangle.fill", "square.fill", "diamond.fill"]
      case .suits: ["suit.club.fill", "suit.spade.fill", "suit.heart.fill", "suit.diamond.fill"]
      // Each where its colour puts it: a green leaf, cyan water, amber fire.
      case .elements: ["leaf.fill", "drop.fill", "flame.fill", "bolt.fill"]
      case .sky: ["sun.max.fill", "moon.fill", "cloud.fill", "star.fill"]
      // Each in its colour too: a green turtle, a cyan fish, an amber fox.
      case .critters: ["tortoise.fill", "fish.fill", "fox.fill", "dog.fill"]
      case .smarts: ["lightbulb.fill", "book.fill", "brain.fill", "graduationcap.fill"]
      case .gameNight: ["dice.fill", "puzzlepiece.fill", "gamecontroller.fill", "crown.fill"]
      // A cyan balloon, an amber popper, a pink cake.
      case .party: ["gift.fill", "balloon.fill", "party.popper.fill", "birthday.cake.fill"]
      // Popcorn in amber, buttered.
      case .showtime: ["theatermasks.fill", "ticket.fill", "popcorn.fill", "movieclapper.fill"]
      case .quest: ["map.fill", "key.fill", "shield.fill", "flag.fill"]
      // A green lizard, a bluebird, a sandy rabbit.
      case .backyard: ["lizard.fill", "bird.fill", "hare.fill", "ladybug.fill"]
      }
      return symbols[style.rawValue]
    }

    func shapeName(for style: AnswerStyle) -> LocalizedStringResource {
      switch (self, style) {
      case (.classic, .a): "circle"
      case (.classic, .b): "triangle"
      case (.classic, .c): "square"
      case (.classic, .d): "diamond"
      case (.suits, .a): "club"
      case (.suits, .b): "spade"
      case (.suits, .c): "heart"
      case (.suits, .d): "diamond"
      case (.elements, .a): "leaf"
      case (.elements, .b): "drop"
      case (.elements, .c): "flame"
      case (.elements, .d): "lightning bolt"
      case (.sky, .a): "sun"
      case (.sky, .b): "moon"
      case (.sky, .c): "cloud"
      case (.sky, .d): "star"
      case (.critters, .a): "turtle"
      case (.critters, .b): "fish"
      case (.critters, .c): "fox"
      case (.critters, .d): "dog"
      case (.smarts, .a): "light bulb"
      case (.smarts, .b): "book"
      case (.smarts, .c): "brain"
      case (.smarts, .d): "graduation cap"
      case (.gameNight, .a): "dice"
      case (.gameNight, .b): "puzzle piece"
      case (.gameNight, .c): "controller"
      case (.gameNight, .d): "crown"
      case (.party, .a): "present"
      case (.party, .b): "balloon"
      case (.party, .c): "party popper"
      case (.party, .d): "cake"
      case (.showtime, .a): "theater masks"
      case (.showtime, .b): "ticket"
      case (.showtime, .c): "popcorn"
      case (.showtime, .d): "clapperboard"
      case (.quest, .a): "map"
      case (.quest, .b): "skeleton key"
      case (.quest, .c): "shield"
      case (.quest, .d): "flag"
      case (.backyard, .a): "lizard"
      case (.backyard, .b): "bird"
      case (.backyard, .c): "rabbit"
      case (.backyard, .d): "ladybug"
      }
    }
  }
}

extension AnswerMarkers {
  /// `style`'s symbol as an image, sized by the font around it.
  public func image(for style: AnswerStyle) -> Image {
    Symbols.image(symbol(for: style))
  }

  /// The symbols of every set in `sets`, `first`'s before the rest and each
  /// once: what a launch traces for glass (`GlassSymbol.prepare(_:)`).
  public static func allSymbols(first: AnswerMarkers, in sets: [AnswerMarkers] = builtIn) -> [String] {
    var seen: Set<String> = []
    return ([first] + sets.filter { $0 != first }).flatMap { markers in
      AnswerStyle.allCases.map(markers.symbol(for:))
    }
    .filter { seen.insert($0).inserted }
  }
}

nonisolated extension EnvironmentValues {
  /// The shapes the answers inside are drawn with.
  @Entry public var answerMarkers: AnswerMarkers = .classic
}
