import SwiftUI

/// The answer set, in its colours: the brand mark. Four characters of
/// layered glass, as on the app icon.
public struct AnswerSetMark: View {
  let depth: GlassDepth

  public init(depth: GlassDepth = .figure) {
    self.depth = depth
  }

  public var body: some View {
    HStack(spacing: Space.l) {
      ForEach(AnswerStyle.allCases) { style in
        AnswerGlyph(style: style, depth: depth)
      }
    }
    .accessibilityHidden(true)
  }
}

/// "TRIVIA" in Liquid Glass: each letter a pane of the system's glass, tinted
/// in the accent, over its own phosphor bloom for the glass to bend. A block
/// cursor of the same glass blinks in the next character cell, as tall as the
/// capitals and standing on their baseline; it hangs past the word, so the
/// word itself is what's centred.
///
/// Under Increase Contrast it's solid accent, letters and block alike.
public struct Wordmark: View {
  public enum Scale: Sendable {
    case screen, showcase
    /// The TV's idle board, on its 1920×1080 canvas.
    case tv

    var size: CGFloat {
      switch self {
      case .screen: 46
      case .showcase: 34
      case .tv: TVRole.wordmark.size
      }
    }

    var tracking: CGFloat {
      switch self {
      case .screen, .showcase: size / 8
      case .tv: TVRole.wordmark.tracking
      }
    }

    var glow: Glow {
      switch self {
      case .screen, .showcase: .hero
      case .tv: .tv
      }
    }
  }

  let scale: Scale

  @Environment(\.palette) private var palette

  public init(scale: Scale = .screen) {
    self.scale = scale
  }

  public var body: some View {
    let lettering = Lettering("TRIVIA", size: scale.size, weight: .heavy, tracking: scale.tracking)
    let letters = OutlineShape(path: lettering.letters)
    let cursor = lettering.cursor
    // Square, as a terminal's block is, softened just enough for glass to
    // catch its corners.
    let block = RoundedRectangle(cornerRadius: cursor.width / 24)
    ZStack(alignment: .topLeading) {
      if palette.isHighContrast {
        letters.fill(palette.accent)
      } else {
        letters
          .fill(palette.glow(palette.accent))
          .blur(radius: scale.glow.radius)
        Color.clear
          .glassEffect(glass, in: letters)
      }
      Blinking {
        if palette.isHighContrast {
          block.fill(palette.accent)
        } else {
          ZStack {
            block
              .fill(palette.glow(palette.accent))
              .blur(radius: scale.glow.radius)
            Color.clear
              .glassEffect(glass, in: block)
          }
        }
      }
      .frame(width: cursor.width, height: cursor.height)
      .offset(x: cursor.minX, y: cursor.minY)
    }
    .frame(width: lettering.size.width, height: lettering.size.height)
    // A logo: the cursor follows the word in every language.
    .environment(\.layoutDirection, .leftToRight)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: "Trivia"))
    .accessibilityAddTraits(.isHeader)
  }

  /// The letters' glass: the accent, lit.
  private var glass: Glass {
    .regular.tint(palette.accent.opacity(0.55))
  }
}

/// The big rank, made of glass. Medal-coloured, with the medal's bloom, on
/// the podium places; first place gets a glass trophy that hops as it lands.
public struct RankFigure: View {
  let rank: Int?
  let isCompact: Bool

  @State private var hasLanded = false

  /// `isCompact` steps it down to make room for a table under it.
  public init(rank: Int?, isCompact: Bool = false) {
    self.rank = rank
    self.isCompact = isCompact
  }

  public var body: some View {
    let medal = Medal(rank: rank)
    let tint = medal?.color ?? .primary
    HStack(alignment: .center, spacing: Space.m) {
      if medal == .first {
        GlassSymbol("trophy.fill", color: tint, depth: .hero, glow: .medal)
          .font(.largeTitle)
          .glassBounce(trigger: hasLanded)
          .onAppear { hasLanded = true }
      }
      GlassText(
        verbatim: rank.map { "#\($0)" } ?? "—",
        role: .display(isCompact ? .pinLarge : .hero),
        color: tint,
        depth: .hero,
        glow: medal == nil ? nil : .medal
      )
      .minimumScaleFactor(0.5)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rank.map { Text("Rank \($0)") } ?? Text("Unranked"))
  }
}

/// The top edge of a step whose top corners are rounded by `radius`: along
/// the top and down around each corner, so a lit edge follows the step's
/// outline. Inset, it keeps a stroke inside the step.
nonisolated public struct StepRim: InsettableShape {
  let radius: CGFloat
  var inset: CGFloat = 0

  public init(radius: CGFloat) {
    self.radius = radius
  }

  public func path(in rect: CGRect) -> Path {
    let rect = rect.insetBy(dx: inset, dy: inset)
    let radius = max(0, min(radius - inset, rect.width / 2, rect.height))
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.minX + radius, y: rect.minY), radius: radius)
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
    path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY + radius), radius: radius)
    return path
  }

  public func inset(by amount: CGFloat) -> StepRim {
    var rim = self
    rim.inset += amount
    return rim
  }
}

/// One step of the podium: the name and score on top, the place below, on a
/// block of glass tinted in its medal's colour.
public struct PodiumStep: View {
  let name: String
  let score: String
  let medal: Medal
  let isPlayer: Bool

  private static let radius = Radius.minimum * 1.5

  public init(name: String, score: String, medal: Medal, isPlayer: Bool) {
    self.name = name
    self.score = score
    self.medal = medal
    self.isPlayer = isPlayer
  }

  public var body: some View {
    VStack(spacing: Space.s) {
      VStack(spacing: Space.xxs) {
        Text(verbatim: name)
          .textRole(.bodyEmphasis)
          .foregroundStyle(isPlayer ? AnyShapeStyle(.themeAccent) : AnyShapeStyle(.primary))
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(verbatim: score)
          .textRole(.figureSmall)
          .foregroundStyle(.secondary)
      }
      GlassText(medal.label, role: .shout, color: medal.color, depth: .figure)
        .frame(maxWidth: .infinity, minHeight: Size.podiumStep(medal), alignment: .top)
        .padding(.top, Space.m)
        .glassEffect(
          .regular.tint(medal.color.opacity(isPlayer ? 0.32 : 0.2)),
          in: UnevenRoundedRectangle(topLeadingRadius: Self.radius, topTrailingRadius: Self.radius)
        )
        .overlay {
          // A lit edge along the top of the step, round at the corners.
          StepRim(radius: Self.radius)
            .strokeBorder(medal.color.opacity(0.8), style: StrokeStyle(lineWidth: Space.xxs, lineCap: .round))
        }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

/// A round badge for a moment: the verdict, or waiting. A disc of glass
/// tinted in its colour — the chosen answer's glass flows into the verdict's —
/// with its symbol made of glass on it. The symbol hops when `bounce` changes,
/// and breathes while `isWaiting`.
public struct Badge<Bounce: Equatable>: View {
  let symbol: String
  let color: Color
  let bounce: Bounce
  let isWaiting: Bool

  public init(symbol: String, color: Color, bounce: Bounce, isWaiting: Bool = false) {
    self.symbol = symbol
    self.color = color
    self.bounce = bounce
    self.isWaiting = isWaiting
  }

  public var body: some View {
    GlassSymbol(symbol, color: color, depth: .hero)
      .font(.largeTitle.weight(.bold))
      .glassBounce(trigger: bounce)
      .glassPulse(isActive: isWaiting)
      .frame(width: Size.badge, height: Size.badge)
      .glassEffect(.regular.tint(color.opacity(0.2)), in: .circle)
      .accessibilityHidden(true)
  }
}

extension Badge where Bounce == Bool {
  /// A badge that doesn't hop.
  public init(symbol: String, color: Color, isWaiting: Bool = false) {
    self.init(symbol: symbol, color: color, bounce: false, isWaiting: isWaiting)
  }
}
