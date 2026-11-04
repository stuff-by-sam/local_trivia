import SwiftUI

/// The four shapes beside the answers' letters. Classic's — circle, triangle,
/// square, diamond — are the game's own, and what the web game shows (`PAL`
/// in public/shared/common.js); the rest are the player's to pick.
///
/// A set is this phone's, like a theme: it dresses this phone and any TV it
/// puts the game on. It changes only the shapes. An answer's letter and
/// colour are the same on every phone in the room, so B is always cyan, and
/// every set's four shapes can be told apart without their colours.
nonisolated public enum AnswerMarkers: String, CaseIterable, Identifiable, Sendable {
  case classic, suits, elements, sky, critters
  case smarts, gameNight, party, showtime, quest, backyard

  public var id: String { rawValue }

  public var name: LocalizedStringResource {
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

  public var tagline: LocalizedStringResource {
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

  /// The SF Symbol drawn beside `style`'s letter. (The fox is the design
  /// system's own, drawn as an SF Symbol: see `Symbols`.)
  public func symbol(for style: AnswerStyle) -> String {
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

  /// What VoiceOver calls `style`'s shape: "B, spade: Saturn".
  public func shapeName(for style: AnswerStyle) -> LocalizedStringResource {
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

extension AnswerMarkers {
  /// `style`'s symbol as an image, sized by the font around it.
  public func image(for style: AnswerStyle) -> Image {
    Symbols.image(symbol(for: style))
  }

  /// Every set's symbols, `first`'s before the rest: what a launch traces
  /// for glass (`GlassSymbol.prepare(_:)`).
  public static func allSymbols(first: AnswerMarkers) -> [String] {
    ([first] + allCases.filter { $0 != first }).flatMap { markers in
      AnswerStyle.allCases.map(markers.symbol(for:))
    }
  }
}

nonisolated extension EnvironmentValues {
  /// The shapes the answers inside are drawn with.
  @Entry public var answerMarkers: AnswerMarkers = .classic
}
