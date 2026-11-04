import SwiftUI

/// A shape a player can put beside an answer's letter in a set of their own:
/// an SF Symbol, and what VoiceOver calls it.
///
/// The library is chosen, not every SF Symbol: each is filled and solid
/// enough to read as glass at a key's size, says nothing about right or
/// wrong (no checkmarks, crosses or thumbs), suits every age, and isn't
/// Apple's (no product, logo or service symbols). No two have the same
/// name, so the four of a set are always spoken apart.
nonisolated public struct MarkerShape: Hashable, Identifiable, Sendable {
  public let symbol: String
  public let name: LocalizedStringResource
  public let category: Category

  public var id: String { symbol }

  public init(_ symbol: String, _ name: LocalizedStringResource, in category: Category) {
    self.symbol = symbol
    self.name = name
    self.category = category
  }

  // A symbol is one shape, whatever it's called.
  public static func == (one: MarkerShape, other: MarkerShape) -> Bool {
    one.symbol == other.symbol
  }

  public func hash(into hasher: inout Hasher) {
    hasher.combine(symbol)
  }

  /// The library's sections, in the order the editor shows them.
  nonisolated public enum Category: String, CaseIterable, Identifiable, Sendable {
    case shapes, animals, nature, food, games, arts, travel, school, things

    public var id: String { rawValue }

    public var name: LocalizedStringResource {
      switch self {
      case .shapes: "Shapes"
      case .animals: "Animals"
      case .nature: "Nature"
      case .food: "Food"
      case .games: "Games & Sports"
      case .arts: "Music & Arts"
      case .travel: "Travel"
      case .school: "Science & School"
      case .things: "Things"
      }
    }
  }

  /// The shape for `symbol`: from the library, or from a built-in set — a
  /// set of the player's own started from one keeps its shapes.
  public static func named(_ symbol: String) -> MarkerShape? {
    library.first { $0.symbol == symbol }
      ?? AnswerMarkers.builtIn.lazy.flatMap(\.shapes).first { $0.symbol == symbol }
  }

  /// Everything a player can choose from.
  public static let library: [MarkerShape] = [
    MarkerShape("circle.fill", "circle", in: .shapes),
    MarkerShape("triangle.fill", "triangle", in: .shapes),
    MarkerShape("square.fill", "square", in: .shapes),
    MarkerShape("diamond.fill", "diamond", in: .shapes),
    MarkerShape("pentagon.fill", "pentagon", in: .shapes),
    MarkerShape("hexagon.fill", "hexagon", in: .shapes),
    MarkerShape("octagon.fill", "octagon", in: .shapes),
    MarkerShape("star.fill", "star", in: .shapes),
    MarkerShape("heart.fill", "heart", in: .shapes),
    MarkerShape("shield.fill", "shield", in: .shapes),
    MarkerShape("capsule.fill", "capsule", in: .shapes),
    MarkerShape("oval.fill", "oval", in: .shapes),
    MarkerShape("rhombus.fill", "rhombus", in: .shapes),
    MarkerShape("seal.fill", "badge", in: .shapes),
    MarkerShape("burst.fill", "starburst", in: .shapes),
    MarkerShape("suit.club.fill", "club", in: .shapes),
    MarkerShape("suit.spade.fill", "spade", in: .shapes),
    MarkerShape("cube.fill", "cube", in: .shapes),
    MarkerShape("cone.fill", "cone", in: .shapes),
    MarkerShape("pyramid.fill", "pyramid", in: .shapes),
    MarkerShape("cylinder.fill", "cylinder", in: .shapes),

    MarkerShape("tortoise.fill", "turtle", in: .animals),
    MarkerShape("hare.fill", "rabbit", in: .animals),
    MarkerShape("fish.fill", "fish", in: .animals),
    MarkerShape("bird.fill", "bird", in: .animals),
    MarkerShape("ladybug.fill", "ladybug", in: .animals),
    MarkerShape("ant.fill", "ant", in: .animals),
    MarkerShape("lizard.fill", "lizard", in: .animals),
    MarkerShape("cat.fill", "cat", in: .animals),
    MarkerShape("dog.fill", "dog", in: .animals),
    MarkerShape("fox.fill", "fox", in: .animals),
    MarkerShape("pawprint.fill", "paw print", in: .animals),
    MarkerShape("teddybear.fill", "teddy bear", in: .animals),
    MarkerShape("fossil.shell.fill", "shell", in: .animals),
    MarkerShape("microbe.fill", "microbe", in: .animals),

    MarkerShape("leaf.fill", "leaf", in: .nature),
    MarkerShape("tree.fill", "tree", in: .nature),
    MarkerShape("sun.max.fill", "sun", in: .nature),
    MarkerShape("moon.fill", "moon", in: .nature),
    MarkerShape("cloud.fill", "cloud", in: .nature),
    MarkerShape("cloud.rain.fill", "rain cloud", in: .nature),
    MarkerShape("cloud.bolt.fill", "storm cloud", in: .nature),
    MarkerShape("snowflake", "snowflake", in: .nature),
    MarkerShape("bolt.fill", "lightning bolt", in: .nature),
    MarkerShape("flame.fill", "flame", in: .nature),
    MarkerShape("drop.fill", "drop", in: .nature),
    MarkerShape("rainbow", "rainbow", in: .nature),
    MarkerShape("mountain.2.fill", "mountains", in: .nature),
    MarkerShape("sun.horizon.fill", "sunset", in: .nature),
    MarkerShape("sparkles", "sparkles", in: .nature),
    MarkerShape("globe.americas.fill", "globe", in: .nature),

    MarkerShape("carrot.fill", "carrot", in: .food),
    MarkerShape("birthday.cake.fill", "cake", in: .food),
    MarkerShape("popcorn.fill", "popcorn", in: .food),
    MarkerShape("cup.and.saucer.fill", "teacup", in: .food),
    MarkerShape("mug.fill", "mug", in: .food),
    MarkerShape("takeoutbag.and.cup.and.straw.fill", "takeout", in: .food),
    MarkerShape("frying.pan.fill", "frying pan", in: .food),
    MarkerShape("waterbottle.fill", "water bottle", in: .food),

    MarkerShape("dice.fill", "dice", in: .games),
    MarkerShape("puzzlepiece.fill", "puzzle piece", in: .games),
    MarkerShape("gamecontroller.fill", "controller", in: .games),
    MarkerShape("crown.fill", "crown", in: .games),
    MarkerShape("trophy.fill", "trophy", in: .games),
    MarkerShape("medal.fill", "medal", in: .games),
    MarkerShape("flag.checkered", "checkered flag", in: .games),
    MarkerShape("target", "target", in: .games),
    MarkerShape("soccerball", "soccer ball", in: .games),
    MarkerShape("basketball.fill", "basketball", in: .games),
    MarkerShape("football.fill", "football", in: .games),
    MarkerShape("baseball.fill", "baseball", in: .games),
    MarkerShape("tennisball.fill", "tennis ball", in: .games),
    MarkerShape("volleyball.fill", "volleyball", in: .games),
    MarkerShape("hockey.puck.fill", "hockey puck", in: .games),
    MarkerShape("rugbyball.fill", "rugby ball", in: .games),
    MarkerShape("cricket.ball.fill", "cricket ball", in: .games),
    MarkerShape("skateboard.fill", "skateboard", in: .games),
    MarkerShape("surfboard.fill", "surfboard", in: .games),
    MarkerShape("dumbbell.fill", "dumbbell", in: .games),
    MarkerShape("tennis.racket", "tennis racket", in: .games),

    MarkerShape("music.note", "music note", in: .arts),
    MarkerShape("guitars.fill", "guitars", in: .arts),
    MarkerShape("pianokeys", "piano keys", in: .arts),
    MarkerShape("horn.fill", "horn", in: .arts),
    MarkerShape("metronome.fill", "metronome", in: .arts),
    MarkerShape("headphones", "headphones", in: .arts),
    MarkerShape("mic.fill", "microphone", in: .arts),
    MarkerShape("theatermasks.fill", "theater masks", in: .arts),
    MarkerShape("ticket.fill", "ticket", in: .arts),
    MarkerShape("movieclapper.fill", "clapperboard", in: .arts),
    MarkerShape("film.fill", "film", in: .arts),
    MarkerShape("camera.fill", "camera", in: .arts),
    MarkerShape("paintbrush.fill", "paintbrush", in: .arts),
    MarkerShape("paintpalette.fill", "paint palette", in: .arts),

    MarkerShape("airplane", "airplane", in: .travel),
    MarkerShape("suitcase.rolling.fill", "suitcase", in: .travel),
    MarkerShape("car.fill", "car", in: .travel),
    MarkerShape("bus.fill", "bus", in: .travel),
    MarkerShape("tram.fill", "tram", in: .travel),
    MarkerShape("train.side.front.car", "train", in: .travel),
    MarkerShape("sailboat.fill", "sailboat", in: .travel),
    MarkerShape("ferry.fill", "ferry", in: .travel),
    MarkerShape("fuelpump.fill", "gas pump", in: .travel),
    MarkerShape("signpost.right.fill", "signpost", in: .travel),
    MarkerShape("map.fill", "map", in: .travel),
    MarkerShape("house.fill", "house", in: .travel),
    MarkerShape("building.2.fill", "buildings", in: .travel),
    MarkerShape("tent.fill", "tent", in: .travel),
    MarkerShape("beach.umbrella.fill", "beach umbrella", in: .travel),

    MarkerShape("lightbulb.fill", "light bulb", in: .school),
    MarkerShape("brain.fill", "brain", in: .school),
    MarkerShape("flask.fill", "flask", in: .school),
    MarkerShape("testtube.2", "test tubes", in: .school),
    MarkerShape("atom", "atom", in: .school),
    MarkerShape("book.fill", "book", in: .school),
    MarkerShape("books.vertical.fill", "books", in: .school),
    MarkerShape("graduationcap.fill", "graduation cap", in: .school),
    MarkerShape("studentdesk", "desk", in: .school),
    MarkerShape("ruler.fill", "ruler", in: .school),
    MarkerShape("backpack.fill", "backpack", in: .school),
    MarkerShape("lamp.desk.fill", "desk lamp", in: .school),

    // Not "key": a string catalog key of that name collides with
    // `LocalizedStringResource.key` once Xcode generates its symbols.
    MarkerShape("key.fill", "skeleton key", in: .things),
    MarkerShape("bell.fill", "bell", in: .things),
    MarkerShape("gift.fill", "present", in: .things),
    MarkerShape("balloon.fill", "balloon", in: .things),
    MarkerShape("party.popper.fill", "party popper", in: .things),
    MarkerShape("fireworks", "fireworks", in: .things),
    MarkerShape("rosette", "ribbon", in: .things),
    MarkerShape("wand.and.stars", "magic wand", in: .things),
    MarkerShape("umbrella.fill", "umbrella", in: .things),
    MarkerShape("briefcase.fill", "briefcase", in: .things),
    MarkerShape("bag.fill", "shopping bag", in: .things),
    MarkerShape("basket.fill", "basket", in: .things),
    MarkerShape("cart.fill", "cart", in: .things),
    MarkerShape("shippingbox.fill", "box", in: .things),
    MarkerShape("tag.fill", "tag", in: .things),
    MarkerShape("bookmark.fill", "bookmark", in: .things),
    MarkerShape("pin.fill", "pushpin", in: .things),
    MarkerShape("flag.fill", "flag", in: .things),
    MarkerShape("envelope.fill", "envelope", in: .things),
    MarkerShape("paperplane.fill", "paper airplane", in: .things),
    MarkerShape("megaphone.fill", "megaphone", in: .things),
    MarkerShape("binoculars.fill", "binoculars", in: .things),
    MarkerShape("hammer.fill", "hammer", in: .things),
    MarkerShape("wrench.adjustable.fill", "wrench", in: .things),
    MarkerShape("tshirt.fill", "T-shirt", in: .things),
    MarkerShape("shoe.fill", "sneaker", in: .things),
    MarkerShape("sunglasses.fill", "sunglasses", in: .things),
    MarkerShape("hat.widebrim.fill", "sun hat", in: .things),
    MarkerShape("comb.fill", "comb", in: .things),
    MarkerShape("mustache.fill", "mustache", in: .things),
    MarkerShape("eye.fill", "eye", in: .things),
    MarkerShape("face.smiling.inverse", "smiley face", in: .things),
    MarkerShape("hand.wave.fill", "waving hand", in: .things),
    MarkerShape("chair.fill", "chair", in: .things),
    MarkerShape("sofa.fill", "sofa", in: .things),
    MarkerShape("bed.double.fill", "bed", in: .things),
    MarkerShape("bathtub.fill", "bathtub", in: .things),
  ]
}
