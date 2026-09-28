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

  public var id: String { rawValue }

  public var name: LocalizedStringResource {
    switch self {
    case .classic: "Classic"
    case .suits: "Suits"
    case .elements: "Elements"
    case .sky: "Sky"
    case .critters: "Critters"
    }
  }

  public var tagline: LocalizedStringResource {
    switch self {
    case .classic: "Circle, triangle, square and diamond: the game's own"
    case .suits: "Clubs, spades, hearts and diamonds, from the card table"
    case .elements: "Leaf, water, fire and lightning"
    case .sky: "Sun, moon, cloud and star"
    case .critters: "A tortoise, a fish, a cat and a bird"
    }
  }

  /// The SF Symbol drawn beside `style`'s letter.
  public func symbol(for style: AnswerStyle) -> String {
    let symbols = switch self {
    case .classic: ["circle.fill", "triangle.fill", "square.fill", "diamond.fill"]
    case .suits: ["suit.club.fill", "suit.spade.fill", "suit.heart.fill", "suit.diamond.fill"]
    // Each where its colour puts it: a green leaf, cyan water, amber fire.
    case .elements: ["leaf.fill", "drop.fill", "flame.fill", "bolt.fill"]
    case .sky: ["sun.max.fill", "moon.fill", "cloud.fill", "star.fill"]
    case .critters: ["tortoise.fill", "fish.fill", "cat.fill", "bird.fill"]
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
    case (.critters, .a): "tortoise"
    case (.critters, .b): "fish"
    case (.critters, .c): "cat"
    case (.critters, .d): "bird"
    }
  }
}

nonisolated extension EnvironmentValues {
  /// The shapes the answers inside are drawn with.
  @Entry public var answerMarkers: AnswerMarkers = .classic
}
