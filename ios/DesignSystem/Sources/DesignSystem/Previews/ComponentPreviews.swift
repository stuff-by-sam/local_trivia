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

#Preview("PickerRow") {
  PreviewMatrix {
    VStack(spacing: Space.m) {
      PickerRow(title: "Looking for games…", detail: "JOIN THE HOST'S WI-FI") { ProgressView().controlSize(.small) }
      PickerRow(title: "FRIDAY QUIZ", detail: "192.168.1.20 · ONLINE") { StatusDot(.online) }
      PickerRow(title: "FRIDAY QUIZ", detail: "192.168.1.20 · UNREACHABLE") { StatusDot(.failed) }
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
        Badge(symbol: "checkmark", color: Palette.success, isGlass: true)
        Badge(symbol: "hourglass", color: .secondary, isGlass: false)
      }
    }
  }
}

#Preview("UndoToast") {
  PreviewMatrix {
    UndoToast(item: UndoItem("Deleted 3 questions") {}) {}
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
