import SwiftUI

// Two voices, never more. SF Pro carries content — questions, answers, names —
// because it's the most legible face on the platform. SF Mono is the game's own
// voice: labels, figures, the clock, anything the game reports back. Every role
// rides a Dynamic Type text style. Ramp: ios/DESIGN.md, "Type".

extension Font {
  static func mono(_ style: Font.TextStyle, weight: Font.Weight = .medium) -> Font {
    .system(style, design: .monospaced, weight: weight)
  }
}

/// What a piece of text is, which decides how it looks.
public enum TextRole: Equatable, Sendable {
  /// The question, stepped down by its length so the answers never leave
  /// the screen (the web client's `SIZE_STEPS`).
  case question(length: Int)
  /// An answer, sized by the longest of its set so all four match.
  case answer(longestOption: Int, isChosen: Bool = false)
  case body
  case bodyEmphasis
  /// A player's own name, as a title.
  case title
  /// Row titles and the game's name in the picker.
  case headline
  /// Supporting sentences: taglines, explanations under a control.
  case detail
  /// Verdicts and screen titles, in the game's voice: `CORRECT`.
  case shout
  /// Action button labels: `JOIN GAME`.
  case action
  /// Status lines and toolbar readouts: `WAITING FOR HOST_`, `Q 03/12`.
  case status
  /// Field and readout labels: `PIN`, `TOTAL`.
  case label
  /// Metadata nobody needs to act on.
  case labelSmall
  /// A value in a readout, a score.
  case figure
  /// A small figure or address: `192.168.1.20 · ONLINE`.
  case figureSmall
  /// Oversized numerals: rank, points, the PIN.
  case display(Display)

  public enum Display: Sendable {
    /// Rank on the standings and the podium.
    case hero
    /// Points at the reveal.
    case points
    /// The join code as the lobby's hero, or held up to the room.
    case pinLarge
    /// The join code on a card.
    case pin
    /// A PIN cell.
    case cell

    var base: CGFloat {
      switch self {
      case .hero: 100
      case .points: 58
      case .pinLarge: 64
      case .pin: 44
      case .cell: 34
      }
    }
  }

  var font: Font {
    switch self {
    case .question(let length):
      switch length {
      case ...45: .system(.largeTitle, weight: .bold)
      case ...100: .system(.title, weight: .bold)
      case ...180: .system(.title2, weight: .semibold)
      default: .system(.title3, weight: .semibold)
      }
    case .answer(let longest, let isChosen):
      {
        let style: Font.TextStyle =
          switch longest {
          case ...24: .title3
          case ...56: .body
          default: .callout
          }
        return .system(style, weight: isChosen ? .bold : .semibold)
      }()
    case .body: .body
    case .title: .system(.largeTitle, weight: .bold)
    case .bodyEmphasis: .body.weight(.semibold)
    case .headline: .headline
    case .detail: .footnote
    case .shout: .mono(.title3, weight: .heavy)
    case .action: .mono(.headline, weight: .bold)
    case .status: .mono(.footnote, weight: .semibold)
    case .label: .mono(.caption, weight: .semibold)
    case .labelSmall: .mono(.caption2, weight: .semibold)
    case .figure: .mono(.body, weight: .semibold)
    case .figureSmall: .mono(.caption, weight: .medium)
    case .display: .body  // sized by `TextRoleModifier`
    }
  }

  var isUppercase: Bool {
    switch self {
    case .shout, .action, .status, .label, .labelSmall: true
    default: false
    }
  }

  var tracking: CGFloat {
    switch self {
    case .shout: 4
    case .action, .status, .label, .labelSmall: 1.4
    case .display(.pinLarge): 8
    case .display(.pin): 6
    default: 0
    }
  }
}

extension View {
  /// Styles text as `role`.
  public func textRole(_ role: TextRole) -> some View {
    modifier(TextRoleModifier(role: role))
  }
}

private struct TextRoleModifier: ViewModifier {
  let role: TextRole
  /// Display numerals follow Dynamic Type from their base size, capped: they're
  /// already the biggest thing on screen.
  @ScaledMetric private var scaled: CGFloat

  init(role: TextRole) {
    self.role = role
    let base: CGFloat = if case .display(let display) = role { display.base } else { 17 }
    _scaled = ScaledMetric(wrappedValue: base, relativeTo: .largeTitle)
  }

  func body(content: Content) -> some View {
    content
      .font(font)
      .textCase(role.isUppercase ? .uppercase : nil)
      .tracking(role.tracking)
  }

  private var font: Font {
    guard case .display(let display) = role else { return role.font }
    let size = min(scaled, display.base * 1.35)
    let weight: Font.Weight = display == .cell || display == .points ? .bold : .heavy
    return .system(size: size, weight: weight, design: .monospaced)
  }
}

/// The TV board's type. It's drawn on a fixed 1920×1080 canvas scaled to the
/// display, so sizes are canvas points and Dynamic Type doesn't apply — a TV
/// is read from across the room, not held.
public enum TVRole: Sendable {
  case wordmark, masthead, stepLabel, pin, joinLabel, instruction, name, nameOverflow
  case question(length: Int), questionAtReveal, answerKey, answer, votes, footer, waiting
  case sectionTitle, rank, standingName, standingDelta, standingScore
  case podiumName, podiumScore, podiumPlace, idleLine
  /// Symbols: the answer set on the idle board, the trophy on the podium.
  case answerSet, trophy

  var size: CGFloat {
    switch self {
    case .wordmark: 180
    case .masthead: 40
    case .stepLabel: 36
    case .pin: 250
    case .joinLabel: 36
    case .instruction: 38
    case .name: 32
    case .nameOverflow: 30
    case .question(let length):
      switch length {
      case ...60: 92
      case ...120: 76
      case ...200: 62
      default: 52
      }
    case .questionAtReveal: 52
    case .answerKey: 44
    case .answer: 46
    case .votes: 52
    case .footer: 32
    case .waiting: 56
    case .sectionTitle: 64
    case .rank: 44
    case .standingName: 46
    case .standingDelta: 32
    case .standingScore: 46
    case .podiumName: 56
    case .podiumScore: 38
    case .podiumPlace: 56
    case .idleLine: 44
    case .answerSet: 56
    case .trophy: 88
    }
  }

  var weight: Font.Weight {
    switch self {
    case .wordmark, .masthead, .pin, .sectionTitle, .rank, .votes, .podiumPlace: .heavy
    case .question, .answerKey, .waiting, .podiumName, .standingDelta: .bold
    case .instruction, .idleLine: .medium
    case .answerSet, .trophy: .regular
    default: .semibold
    }
  }

  var isMono: Bool {
    switch self {
    case .question, .questionAtReveal, .answer, .instruction, .name, .standingName, .podiumName, .idleLine, .answerSet, .trophy: false
    default: true
    }
  }

  var isUppercase: Bool {
    switch self {
    case .stepLabel, .joinLabel, .footer, .waiting, .sectionTitle: true
    default: false
    }
  }

  var tracking: CGFloat {
    switch self {
    case .wordmark: 20
    case .pin: 24
    case .sectionTitle: 10
    case .waiting: 6
    case .masthead, .stepLabel, .joinLabel: 4
    case .footer: 3
    default: 0
    }
  }
}

extension View {
  /// Styles text for the TV board.
  public func tvRole(_ role: TVRole) -> some View {
    font(.system(size: role.size, weight: role.weight, design: role.isMono ? .monospaced : .default))
      .textCase(role.isUppercase ? .uppercase : nil)
      .tracking(role.tracking)
  }
}
