import SwiftUI

/// The answer set, in its colours: the brand mark.
public struct AnswerSetMark: View {
  public init() {}

  public var body: some View {
    HStack(spacing: Space.l) {
      ForEach(AnswerStyle.allCases) { style in
        Image(systemName: style.symbol)
          .foregroundStyle(style.color)
      }
    }
    .accessibilityHidden(true)
  }
}

/// "TRIVIA", with a block cursor hanging past the word so the word itself is
/// what's centred, and the TV's phosphor bloom.
public struct Wordmark: View {
  public enum Scale: Sendable {
    case screen, showcase

    var size: CGFloat {
      switch self {
      case .screen: 46
      case .showcase: 34
      }
    }
  }

  let scale: Scale

  public init(scale: Scale = .screen) {
    self.scale = scale
  }

  public var body: some View {
    Text(verbatim: "TRIVIA")
      .tracking(scale.size / 8)
      .overlay(alignment: .trailing) {
        BlinkingCursor(glyph: "█")
          .fixedSize()
          .alignmentGuide(.trailing) { $0[.leading] }
      }
      // Evens out tracking's trailing gap.
      .offset(x: scale.size / 16)
      .font(.system(size: scale.size, weight: .heavy, design: .monospaced))
      .foregroundStyle(.themeAccent)
      .glow(.hero)
      // A logo: the cursor follows the word in every language.
      .environment(\.layoutDirection, .leftToRight)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: "Trivia"))
      .accessibilityAddTraits(.isHeader)
  }
}

/// The big rank. Medal-coloured, with the medal's bloom, on the podium places.
public struct RankFigure: View {
  let rank: Int?
  let isCompact: Bool

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
        Image(systemName: "trophy.fill")
          .font(.largeTitle)
          .symbolEffect(.bounce, options: .nonRepeating)
      }
      Text(verbatim: rank.map { "#\($0)" } ?? "—")
        .textRole(.display(isCompact ? .pinLarge : .hero))
        .tracking(0)
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
    .foregroundStyle(tint)
    .glow(.medal, color: medal == nil ? .clear : tint)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rank.map { Text("Rank \($0)") } ?? Text("Unranked"))
  }
}

/// One step of the podium: the name and score on top, the place below.
public struct PodiumStep: View {
  let name: String
  let score: String
  let medal: Medal
  let isPlayer: Bool

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
      Text(medal.label)
        .textRole(.shout)
        .foregroundStyle(medal.color)
        .frame(maxWidth: .infinity, minHeight: Size.podiumStep(medal), alignment: .top)
        .padding(.top, Space.m)
        .background {
          UnevenRoundedRectangle(topLeadingRadius: Radius.minimum * 1.5, topTrailingRadius: Radius.minimum * 1.5)
            .fill(
              LinearGradient(
                colors: [medal.color.opacity(isPlayer ? 0.32 : 0.2), medal.color.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
        }
        .overlay(alignment: .top) {
          // A lit edge along the top of the step.
          Capsule()
            .fill(medal.color.opacity(0.8))
            .frame(height: Space.xxs)
        }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

/// A round badge for a moment: the verdict, or waiting. The verdict's is
/// glass so the chosen answer can flow into it; a plain badge is drawn.
public struct Badge: View {
  let symbol: String
  let color: Color
  let isGlass: Bool

  public init(symbol: String, color: Color, isGlass: Bool) {
    self.symbol = symbol
    self.color = color
    self.isGlass = isGlass
  }

  public var body: some View {
    let icon = Image(systemName: symbol)
      .font(.largeTitle.weight(.bold))
      .foregroundStyle(color)
      .frame(width: Size.badge, height: Size.badge)
    Group {
      if isGlass {
        icon.glassEffect(.regular.tint(color.opacity(0.2)), in: .circle)
      } else {
        icon.panel(radius: Size.badge / 2)
      }
    }
    .accessibilityHidden(true)
  }
}
