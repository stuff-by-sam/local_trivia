#if DEBUG
import SwiftUI

// Every component, in every state, across the settings that change how it
// draws: text size from xSmall to AX5, Increase Contrast, Reduce
// Transparency, Reduce Motion, right-to-left, and long or empty content.
// The underscored environment keys are the preview-only setters for values
// the system otherwise owns.

/// One way the reader's device can be set up.
struct PreviewVariant: Identifiable {
  let name: String
  var typeSize: DynamicTypeSize = .large
  var contrast: ColorSchemeContrast = .standard
  var reduceTransparency = false
  var reduceMotion = false
  var direction: LayoutDirection = .leftToRight

  var id: String { name }

  static let all: [PreviewVariant] = [
    PreviewVariant(name: "Default"),
    PreviewVariant(name: "xSmall", typeSize: .xSmall),
    PreviewVariant(name: "AX5", typeSize: .accessibility5),
    PreviewVariant(name: "Increase Contrast", contrast: .increased),
    PreviewVariant(name: "Reduce Transparency", reduceTransparency: true),
    PreviewVariant(name: "Reduce Motion", reduceMotion: true),
    PreviewVariant(name: "Right to Left", direction: .rightToLeft),
  ]
}

/// `content` once per variant, each over the backdrop, labelled.
struct PreviewMatrix<Content: View>: View {
  var theme: Theme = .phosphor
  @ViewBuilder var content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Space.xl) {
        ForEach(PreviewVariant.all) { variant in
          VStack(alignment: .leading, spacing: Space.s) {
            Text(verbatim: variant.name)
              .textRole(.label)
              .foregroundStyle(.secondary)
            content()
              .padding(Space.l)
              .frame(maxWidth: .infinity)
              .background { Backdrop(mood: .idle) }
              .clipShape(.rect(cornerRadius: Radius.panel))
              .dynamicTypeSize(variant.typeSize)
              .environment(\._colorSchemeContrast, variant.contrast)
              .environment(\._accessibilityReduceTransparency, variant.reduceTransparency)
              .environment(\._accessibilityReduceMotion, variant.reduceMotion)
              .environment(\.layoutDirection, variant.direction)
          }
        }
      }
      .padding(Space.l)
    }
    .theme(theme)
    .background(theme.ink)
    .preferredColorScheme(.dark)
  }
}

private enum Sample {
  static let longAnswer = "The Democratic Republic of São Tomé and Príncipe, off the west coast of Africa"
  static let longName = "Maximilian-Alexander"
}

#Preview("ActionButton") {
  PreviewMatrix {
    VStack(spacing: Space.s) {
      ActionButton("Join Game", systemImage: "arrow.forward") {}
      ActionButton("Join Game", systemImage: "arrow.forward") {}.disabled(true)
      ActionButton("Start Hosting", isLoading: true) {}
      ActionButton("Host a Game", systemImage: "antenna.radiowaves.left.and.right", prominence: .secondary) {}
    }
  }
}

#Preview("AnswerButton") {
  PreviewMatrix {
    VStack(spacing: Space.s) {
      AnswerButton(style: .a, text: "Saturn", longestOption: 7, state: .open) {}
      AnswerButton(style: .b, text: "Jupiter", longestOption: 7, state: .chosen) {}
      AnswerButton(style: .c, text: "Uranus", longestOption: 7, state: .dimmed) {}
      AnswerButton(style: .d, text: Sample.longAnswer, longestOption: Sample.longAnswer.count, state: .open) {}
      AnswerButton(style: .a, text: "", longestOption: 0, state: .open) {}
    }
  }
}

#Preview("AnswerKey") {
  PreviewMatrix {
    HStack(spacing: Space.s) {
      ForEach(AnswerStyle.allCases) { AnswerKey(style: $0) }
      AnswerKey(style: .b, isInverted: true)
        .padding(Space.xs)
        .background(AnswerStyle.b.color, in: .rect(cornerRadius: Radius.minimum))
    }
  }
}

#Preview("PINCells") {
  PreviewMatrix {
    VStack(spacing: Space.m) {
      PINCells(pin: "", length: 4, isFocused: false)
      PINCells(pin: "48", length: 4, isFocused: true)
      PINCells(pin: "4821", length: 4, isFocused: false)
    }
  }
}

#Preview("PromptField") {
  PreviewMatrix {
    VStack(spacing: Space.m) {
      PromptField { TextField("Nickname", text: .constant(""), prompt: Text(verbatim: "your name")) }
      PromptField { TextField("Nickname", text: .constant(Sample.longName)) }
      FieldMessage(Text(verbatim: "Nickname taken. Pick another."), kind: .error)
      FieldMessage(Text(verbatim: "Removed by the host."), kind: .notice)
      FieldMessage(Text(verbatim: "The PIN is on the host's phone"), kind: .hint)
    }
  }
}

#Preview("GameLine") {
  PreviewMatrix {
    VStack(alignment: .leading, spacing: Space.xs) {
      GameLine { StatusDot(.online) } label: {
        GameLineLabel(Text(verbatim: "Friday Quiz"), detail: Text(verbatim: "Online"))
      }
      GameLine { StatusDot(.connecting) } label: {
        GameLineLabel(Text(verbatim: "Friday Quiz"), detail: Text(verbatim: "Connecting"), isMenu: false)
      }
      GameLine { StatusDot(.failed) } label: {
        GameLineLabel(Text(verbatim: Sample.longName), detail: Text(verbatim: "Unreachable"))
      }
      GameLine { Image(systemName: "list.bullet").foregroundStyle(.themeAccent) } label: {
        GameLineLabel(Text(verbatim: "Pick your game"), detail: Text(verbatim: "3 on this Wi-Fi"))
      }
      GameLine { ProgressView().controlSize(.mini) } label: {
        GameLineLabel(Text(verbatim: "Looking for the game"), isMenu: false)
      }
    }
  }
}

#Preview("Readout") {
  PreviewMatrix {
    VStack(spacing: Space.m) {
      Readout {
        ReadoutRow("Answer") {
          HStack(spacing: Space.s) {
            AnswerKey(style: .a)
            Text(verbatim: Sample.longAnswer)
          }
        }
        ReadoutRow("Total") { Text(verbatim: "12,450") }
        ReadoutRow("Rank") { Text(verbatim: "#3") }
      }
      Readout { ReadoutRow("Players") { Text(verbatim: "0") } }
    }
  }
}

#Preview("Status") {
  PreviewMatrix {
    VStack(alignment: .leading, spacing: Space.m) {
      StatusLine("Waiting for host")
      StatusLine("Faster answers score more", isWaiting: false)
      HStack(spacing: Space.m) {
        StatusDot(.online)
        StatusDot(.connecting)
        StatusDot(.failed)
        StatusDot(.idle)
      }
      DividerLabel("or")
    }
  }
}

#Preview("Figures") {
  PreviewMatrix {
    VStack(spacing: Space.l) {
      Wordmark()
      AnswerSetMark()
      RankFigure(rank: 1)
      RankFigure(rank: 7, isCompact: true)
      RankFigure(rank: nil)
      HStack(alignment: .bottom, spacing: Space.s) {
        PodiumStep(name: "SAM", score: "8,120", medal: .second, isPlayer: false)
        PodiumStep(name: Sample.longName, score: "9,400", medal: .first, isPlayer: true)
        PodiumStep(name: "ALEX", score: "7,010", medal: .third, isPlayer: false)
      }
      HStack(spacing: Space.l) {
        Badge(symbol: "checkmark", color: Palette.success)
        Badge(symbol: "hourglass", color: .secondary)
      }
    }
  }
}

#Preview("Glass") {
  PreviewMatrix {
    VStack(spacing: Space.l) {
      // Glass characters: symbols, marks and display type, at every depth.
      HStack(alignment: .firstTextBaseline, spacing: Space.l) {
        ForEach(AnswerStyle.allCases) { AnswerGlyph(style: $0) }
        GlassText(verbatim: "4821", role: .display(.pin), color: Palette.success, depth: .figure, glow: .figure)
        GlassText(verbatim: "#1", role: .display(.points), color: Medal.first.color, depth: .hero, glow: .medal)
      }
      HStack(spacing: Space.l) {
        GlassSymbol("trophy.fill", color: Medal.first.color, depth: .hero).font(.largeTitle)
        GlassSymbol("arrowtriangle.up.fill", color: Palette.success).imageScale(.small)
        GlassCounter(870, prefix: "+", role: .display(.points), color: .primary)
        GlassText(verbatim: "Correct", role: .shout, color: Palette.success)
        StatusDot(.online)
        StatusDot(.failed)
      }
      AnswerSetMark(depth: .hero).font(.largeTitle)
      // Content glass, clear (menus) and tinted (game screens).
      HStack(spacing: Space.s) {
        Text(verbatim: "Clear").textRole(.status).padding(Space.inset).panel().glassClarity(.clear)
        Text(verbatim: "Tinted").textRole(.status).padding(Space.inset).panel().glassClarity(.tinted)
        Text(verbatim: "Gold").textRole(.status).padding(Space.inset).glassCard(in: .capsule, tint: Medal.first.color)
      }
      StatusLine("Locked in · 3 of 6 answered")
      StatusLine(verbatim: Sample.longAnswer, isWaiting: false)
    }
  }
}

#Preview("UndoToast") {
  PreviewMatrix {
    UndoToast(item: UndoItem("Deleted 3 questions") {}) {}
  }
}

#Preview("NameChips") {
  PreviewMatrix {
    VStack(alignment: .leading, spacing: Space.m) {
      NameChips(names: ["ROBIN", "Sam", "Alex", "Jordan", Sample.longName, "Mo"], highlighted: "Sam")
      NameChips(names: ["Sam"], highlighted: "Sam")
    }
  }
}

#Preview("Scrolls when crowded") {
  PreviewMatrix {
    VStack(spacing: Space.m) {
      RankFigure(rank: 2)
      Text(verbatim: Sample.longAnswer).textRole(.body)
    }
    .scrollsWhenCrowded()
    .frame(height: Size.qrFull)
  }
}

/// A question as a spread: side by side when it's wider than tall, stacked
/// when it's taller — and stacked with the first half handed over, as a form
/// does while its keyboard's up. The rule is where the fold falls.
#Preview("Spread") {
  PreviewMatrix {
    VStack(spacing: Space.l) {
      SpreadSample()
        .frame(height: Size.qrFull)
      SpreadSample()
        .frame(height: Size.column)
      SpreadSample(hidesStackedLead: true)
        .frame(height: Size.column)
    }
  }
}

private struct SpreadSample: View {
  var hidesStackedLead = false

  var body: some View {
    Spread(hidesStackedLead: hidesStackedLead) {
      Text(verbatim: "Which planet has the most moons?")
        .textRole(.question(length: 32))
        .multilineTextAlignment(.center)
        .padding(Space.inset)
        .panel()
    } trail: {
      VStack(spacing: Space.s) {
        AnswerButton(style: .a, text: "Saturn", longestOption: 7, state: .open) {}
        AnswerButton(style: .b, text: "Jupiter", longestOption: 7, state: .chosen) {}
      }
    }
    .overlay { SpreadFold() }
  }
}

/// Where a spread's fold falls: its middle, with nothing else in the window.
private struct SpreadFold: View {
  var body: some View {
    GeometryReader { proxy in
      let isSideBySide = proxy.size.width >= proxy.size.height
      Rectangle()
        .fill(.danger)
        .frame(width: isSideBySide ? 1 : nil, height: isSideBySide ? nil : 1)
        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
    }
    .allowsHitTesting(false)
  }
}

#Preview("Backdrop moods") {
  ScrollView {
    VStack(spacing: Space.s) {
      ForEach([Backdrop.Mood.idle, .question, .correct, .wrong, .missed, .celebrate], id: \.self) { mood in
        Backdrop(mood: mood)
          .frame(height: Size.qrFull)
          .overlay { Text(verbatim: "\(mood)").textRole(.status) }
          .clipShape(.rect(cornerRadius: Radius.panel))
      }
    }
    .padding(Space.l)
  }
  .preferredColorScheme(.dark)
}

#Preview("Answer markers") {
  ScrollView {
    VStack(alignment: .leading, spacing: Space.l) {
      ForEach(AnswerMarkers.allCases) { markers in
        HStack(spacing: Space.m) {
          MarkerSwatch(markers: markers, isShown: markers == .classic)
          VStack(alignment: .leading, spacing: Space.s) {
            AnswerSetMark()
            HStack(spacing: Space.s) {
              ForEach(AnswerStyle.allCases) { AnswerKey(style: $0) }
            }
            Text(markers.name).textRole(.labelSmall)
          }
        }
        .environment(\.answerMarkers, markers)
      }
    }
    .padding(Space.l)
  }
  .preferredColorScheme(.dark)
}

#Preview("Themes") {
  ScrollView {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.qrCard))], spacing: Space.m) {
      ForEach(Theme.allCases) { theme in
        VStack(spacing: Space.s) {
          ThemeSwatch(theme: theme, isShown: theme == .phosphor)
          IconArtwork(IconDesign(rawValue: theme == .phosphor ? "classic" : theme.rawValue) ?? .classic)
          Text(theme.name).textRole(.labelSmall)
        }
      }
    }
    .padding(Space.l)
  }
  .preferredColorScheme(.dark)
}
#endif
