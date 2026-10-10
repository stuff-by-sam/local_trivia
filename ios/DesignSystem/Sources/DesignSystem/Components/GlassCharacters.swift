import SwiftUI

// Characters made of Liquid Glass: display type, SF Symbols and small shapes,
// each the system's glass in its own outline, tinted in its colour over a
// bloom of it — the wordmark's recipe, for every letter and mark the game
// shows. Text is set in the font SwiftUI resolved for it (`Lettering`);
// symbols are traced from the system's own (`SymbolOutlines`).
//
// The real text or symbol still lays each one out, hidden, so it keeps its
// size, baseline, Dynamic Type and shrink-to-fit. Each character's glass has
// a container of its own, so it never melts into the glass it sits on — an
// answer, a card, a badge — inside the screen's. Flat colour under Increase
// Contrast, where the glass's highlights would only soften an edge.
//
// For display type and marks only. Body text, questions, answers and what
// the player types sit on glass; they're never made of it.

/// `shape` in the system's glass, tinted in `color`, over a bloom of it.
struct GlassCharacter<S: Shape>: View {
  let shape: S
  let color: Color
  let depth: GlassDepth
  /// How far the bloom spreads: the glyph's own depth, or a figure's glow.
  var bloom: CGFloat?

  @Environment(\.palette) private var palette

  var body: some View {
    ZStack {
      shape
        .fill(palette.glow(color))
        .blur(radius: bloom ?? depth.shadow)
      // Room past the frame for the glass's own shadow, which the container
      // would otherwise cut off in a hard line.
      GlassEffectContainer {
        Color.clear
          .glassEffect(.regular.tint(color.opacity(depth.tint)), in: InsetShape(base: shape, inset: depth.room))
      }
      .padding(-depth.room)
    }
    .allowsHitTesting(false)
  }
}

/// A line of display type made of Liquid Glass: a figure, a verdict, a place,
/// an answer's letter. Styled by `role` (or `tvRole`), or by the font around
/// it; read by VoiceOver as its text.
public struct GlassText: View {
  let text: String
  let color: Color
  let depth: GlassDepth
  let glow: Glow?
  let style: Style

  enum Style {
    case inherited, role(TextRole), tv(TVRole)

    var tracking: CGFloat {
      switch self {
      case .inherited: 0
      case .role(let role): role.tracking
      case .tv(let role): role.tracking
      }
    }
  }

  /// `text` in `role`, or in the font around it (with no tracking).
  public init(verbatim text: String, role: TextRole? = nil, color: Color, depth: GlassDepth = .figure, glow: Glow? = nil) {
    self.text = text
    self.color = color
    self.depth = depth
    self.glow = glow
    self.style = role.map(Style.role) ?? .inherited
  }

  public init(_ text: LocalizedStringResource, role: TextRole? = nil, color: Color, depth: GlassDepth = .figure, glow: Glow? = nil) {
    self.init(verbatim: String(localized: text), role: role, color: color, depth: depth, glow: glow)
  }

  /// `text` on the TV board, in `tvRole`.
  public init(verbatim text: String, tvRole: TVRole, color: Color, depth: GlassDepth = .tv, glow: Glow? = nil) {
    self.text = text
    self.color = color
    self.depth = depth
    self.glow = glow
    self.style = .tv(tvRole)
  }

  public init(_ text: LocalizedStringResource, tvRole: TVRole, color: Color, depth: GlassDepth = .tv, glow: Glow? = nil) {
    self.init(verbatim: String(localized: text), tvRole: tvRole, color: color, depth: depth, glow: glow)
  }

  public var body: some View {
    let letters = GlassLetters(text: text, color: color, depth: depth, glow: glow, tracking: style.tracking)
    Group {
      switch style {
      case .inherited: letters
      case .role(let role): letters.textRole(role)
      case .tv(let role): letters.tvRole(role)
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: text))
  }
}

/// `GlassText`'s letters, set in the font its role resolved to.
private struct GlassLetters: View {
  let text: String
  let color: Color
  let depth: GlassDepth
  let glow: Glow?
  let tracking: CGFloat

  @Environment(\.font) private var font
  @Environment(\.fontResolutionContext) private var fontContext
  @Environment(\.textCase) private var textCase
  @Environment(\.locale) private var locale
  @Environment(\.palette) private var palette

  var body: some View {
    let label = Text(verbatim: text).lineLimit(1)
    if palette.isHighContrast {
      label.foregroundStyle(color)
    } else {
      let lettering = Lettering(cased, font: (font ?? .body).resolve(in: fontContext).ctFont, tracking: tracking)
      label
        .hidden()
        .overlay {
          GlassCharacter(
            shape: FittedOutline(path: lettering.letters, box: lettering.box),
            color: color,
            depth: depth,
            bloom: glow?.radius
          )
        }
    }
  }

  /// As SwiftUI will draw it: the role may set it in capitals.
  private var cased: String {
    switch textCase {
    case .uppercase: text.uppercased(with: locale)
    case .lowercase: text.lowercased(with: locale)
    default: text
    }
  }
}

/// A number made of Liquid Glass that counts to its value: animate a change
/// to `value` (`Motion.count`) and every figure on the way is glass.
public struct GlassCounter: View, Animatable {
  var value: Double
  let prefix: String
  let role: TextRole
  let color: Color
  let depth: GlassDepth

  public init(_ value: Int, prefix: String = "", role: TextRole, color: Color, depth: GlassDepth = .hero) {
    self.value = Double(value)
    self.prefix = prefix
    self.role = role
    self.color = color
    self.depth = depth
  }

  public nonisolated var animatableData: Double {
    get { MainActor.assumeIsolated { value } }
    set { MainActor.assumeIsolated { value = newValue } }
  }

  public var body: some View {
    GlassText(verbatim: prefix + Int(value.rounded()).formatted(.number), role: role, color: color, depth: depth)
  }
}

/// An SF Symbol made of Liquid Glass, traced from the system's own
/// (`SymbolOutlines`). Sized by the font and image scale around it. If it's
/// shown before its trace is in — the first launch, before `prepare(_:)` has
/// reached it — it's drawn glass until then, and cross-fades.
public struct GlassSymbol: View {
  let name: String
  let color: Color
  let depth: GlassDepth
  let glow: Glow?

  @Environment(\.palette) private var palette
  /// The last trace this symbol waited for: what redraws it once it's in.
  @State private var traced: (name: String, path: Path)?

  public init(_ name: String, color: Color, depth: GlassDepth = .mark, glow: Glow? = nil) {
    self.name = name
    self.color = color
    self.depth = depth
    self.glow = glow
  }

  public var body: some View {
    let image = Image(systemName: name)
    Group {
      if palette.isHighContrast {
        image.foregroundStyle(color)
      } else if let outline = SymbolOutlines.cached(name) ?? (traced?.name == name ? traced?.path : nil) {
        image
          .hidden()
          .overlay {
            GlassCharacter(shape: UnitOutlineShape(path: outline), color: color, depth: depth, bloom: glow?.radius)
          }
      } else {
        image.glassSymbol(color, depth: depth)
      }
    }
    .task(id: name) {
      guard SymbolOutlines.cached(name) == nil, let path = await SymbolOutlines.outline(name) else { return }
      // Not a pop: the stand-in gives way to the glass.
      Motion.settle.perform { traced = (name, path) }
    }
    .accessibilityHidden(true)
  }

  /// Traces `names` for their glass ahead of time, off the main actor, so
  /// none has to be drawn glass first: every symbol the app makes of glass,
  /// at launch. Traces are kept on the device, so after the first launch this
  /// finds them all done.
  public static func prepare(_ names: [String]) async {
    await SymbolOutlines.prepare(names)
  }
}

/// An answer's marker in Liquid Glass: the SF Symbol from the player's set,
/// in its answer's colour.
public struct AnswerGlyph: View {
  let style: AnswerStyle
  let depth: GlassDepth

  @Environment(\.answerMarkers) private var markers

  public init(style: AnswerStyle, depth: GlassDepth = .mark) {
    self.style = style
    self.depth = depth
  }

  public var body: some View {
    GlassSymbol(markers.symbol(for: style), color: style.color, depth: depth)
  }
}
