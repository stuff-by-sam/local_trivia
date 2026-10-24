import DesignSystem
import SwiftUI

/// How to play, in seven short pages, each drawn with the game's own pieces:
/// joining, a practice question to answer for points, the standings, hosting,
/// playing nice, and making it yours.
///
/// Shown once after the terms on first launch (`FirstRunView`), where it can
/// be skipped; any time after from How to Play on the join screen.
struct TutorialView: View {
  /// First launch: Skip and Let's Play finish it for good.
  var isFirstRun = false

  @State private var page: TutorialPage
  @State private var practice = PracticeRound()
  @AppStorage(TutorialPage.seenKey) private var hasSeenTutorial = false
  @Environment(\.dismiss) private var dismiss

  init(isFirstRun: Bool = false, page: TutorialPage = .welcome) {
    self.isFirstRun = isFirstRun
    _page = State(initialValue: page)
  }

  var body: some View {
    NavigationStack {
      TabView(selection: $page) {
        ForEach(TutorialPage.allCases) { page in
          TutorialPageView(page: page, isShowing: self.page == page, practice: practice)
            .tag(page)
        }
      }
      .tabViewStyle(.page(indexDisplayMode: .never))
      .navigationTitle(Text("How to Play"))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(isFirstRun ? "Skip" : "Done", action: finish)
        }
      }
      .safeAreaBar(edge: .bottom) {
        ActionBar {
          PageDots(current: page)
          if page.isLast {
            ActionButton("Let's Play", systemImage: "play.fill", action: finish)
          } else {
            ActionButton("Next", systemImage: "arrow.forward", prominence: page == .welcome ? .primary : .secondary, action: next)
          }
        }
        .dynamicTypeSize(...Size.barTypeLimit)
      }
      .containerBackground(for: .navigation) { Backdrop(mood: .idle) }
    }
    .interactiveDismissDisabled(isFirstRun)
  }

  private func next() {
    guard let following = TutorialPage(rawValue: page.rawValue + 1) else { return finish() }
    Motion.screen.perform { page = following }
  }

  private func finish() {
    hasSeenTutorial = true
    dismiss()
  }
}

/// The pages, in order.
enum TutorialPage: Int, CaseIterable, Identifiable {
  case welcome, join, answer, standings, host, safety, looks

  var id: Int { rawValue }
  var isLast: Bool { self == Self.allCases.last }

  /// Whether this phone has been through the tutorial (or skipped it).
  static let seenKey = "tutorialSeen"

  var title: LocalizedStringResource {
    switch self {
    case .welcome: "Welcome to Trivia"
    case .join: "Join a game"
    case .answer: "Answer fast"
    case .standings: "Standings and the podium"
    case .host: "Host your own"
    case .safety: "Play nice"
    case .looks: "Make it yours"
    }
  }

  var message: LocalizedStringResource {
    switch self {
    case .welcome:
      "Quiz night for the room you're in. One phone hosts, and everyone else joins on the same Wi-Fi, with the app or any phone's browser. Here's how it works: it takes a minute."
    case .join:
      "Games on your Wi-Fi show up by themselves. Type the four-digit PIN from the host's screen, add your nickname, and you're in. Nothing listed? Scan the host's QR code instead."
    case .answer:
      "Every answer has a letter, a shape and a colour. Right answers score more the faster they come in. Try one:"
    case .standings:
      "After each question you'll see how the room voted and where you stand. The top three take the podium at the end. Lock your phone or lose Wi-Fi mid-game, and you're back in your seat when you return."
    case .host:
      "Tap Host a Game and build a round: write questions, draft them with Apple Intelligence, import a CSV, or copy a prompt into any AI chat. Then Start Hosting, and everyone joins with your PIN or QR code. You play too."
    case .safety:
      "No objectionable content, no abusive players. In a game, the ••• menu reports a question, a player or the game, or blocks the host; touch and hold a name to block that player. Hosts remove or block anyone from Players."
    case .looks:
      "Pick a theme, answer markers and an app icon in Themes & Icons, all free. See this again any time with How to Play, on the join screen."
    }
  }
}

/// One page: its picture, then what it's saying.
private struct TutorialPageView: View {
  let page: TutorialPage
  /// On screen: the practice question's clock only runs while it is.
  let isShowing: Bool
  let practice: PracticeRound

  var body: some View {
    VStack(spacing: Space.xl) {
      Group {
        switch page {
        case .welcome: WelcomePicture()
        case .join: JoinPicture()
        case .answer: EmptyView()
        case .standings: PodiumPicture()
        case .host: HostPicture()
        case .safety: SafetyPicture()
        case .looks: LooksPicture()
        }
      }
      .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: Space.s) {
        Text(page.title)
          .textRole(.title)
          .accessibilityAddTraits(.isHeader)
        Text(page.message)
          .textRole(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if page == .answer {
        PracticeQuestion(round: practice, isShowing: isShowing)
      }
    }
    .padding(.horizontal, Space.screen)
    .padding(.vertical, Space.l)
    .gameColumn()
    .scrollsWhenCrowded()
  }
}

// MARK: - Pictures

private struct WelcomePicture: View {
  var body: some View {
    VStack(spacing: Space.l) {
      AnswerSetMark()
      Wordmark(scale: .showcase)
    }
    .padding(.vertical, Space.xl)
  }
}

/// The join screen in miniature: a game found on the Wi-Fi, a PIN half typed.
private struct JoinPicture: View {
  var body: some View {
    VStack(spacing: Space.l) {
      PickerRow(title: String(localized: "Friday Quiz"), detail: String(localized: "FOUND ON YOUR WI-FI · ONLINE")) {
        StatusDot(.online)
      }
      PINCells(pin: "48", length: GameStore.pinLength, isFocused: true)
    }
  }
}

/// Three friends on the podium, you on top.
private struct PodiumPicture: View {
  var body: some View {
    HStack(alignment: .bottom, spacing: Space.s) {
      PodiumStep(name: String(localized: "Ada"), score: 4_210.grouped, medal: .second, isPlayer: false)
      PodiumStep(name: String(localized: "You"), score: 4_870.grouped, medal: .first, isPlayer: true)
      PodiumStep(name: String(localized: "Sam"), score: 3_950.grouped, medal: .third, isPlayer: false)
    }
  }
}

/// The host's join code, as the room sees it.
private struct HostPicture: View {
  @Environment(\.palette) private var palette

  var body: some View {
    HStack(alignment: .center, spacing: Space.l) {
      VStack(alignment: .leading, spacing: Space.s) {
        Text("Join code")
          .textRole(.label)
          .foregroundStyle(.secondary)
        GlassText(verbatim: "4821", role: .display(.pin), color: palette.accent, depth: .figure, glow: .figure)
          .minimumScaleFactor(0.6)
        Text("Or scan the code")
          .textRole(.labelSmall)
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 0)
      QRCodeView(payload: "http://192.168.1.20:3000/?pin=4821")
        .frame(width: Size.qrCard, height: Size.qrCard)
    }
    .padding(Space.inset)
    .panel()
  }
}

/// What the ••• menu offers in a game.
private struct SafetyPicture: View {
  var body: some View {
    VStack(alignment: .leading, spacing: Space.m) {
      Label("Report Question…", systemImage: "exclamationmark.bubble")
      Label("Report or Block a Player…", systemImage: "person.crop.circle.badge.exclamationmark")
      Label("Block Host…", systemImage: "hand.raised")
        .foregroundStyle(.danger)
      Divider()
      Label("Safety, on the join screen", systemImage: "hand.raised")
        .foregroundStyle(.secondary)
    }
    .textRole(.body)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(Space.inset)
    .panel()
  }
}

/// Every set of answer markers, the one you wear lit.
private struct LooksPicture: View {
  @Environment(\.answerMarkers) private var markers

  var body: some View {
    HStack(spacing: Space.s) {
      ForEach(AnswerMarkers.allCases) { set in
        MarkerSwatch(markers: set, isShown: set == markers)
      }
    }
    .padding(.vertical, Space.l)
  }
}

/// Bottom of the screen: which page of how many.
private struct PageDots: View {
  let current: TutorialPage

  var body: some View {
    HStack(spacing: Space.s) {
      ForEach(TutorialPage.allCases) { page in
        Circle()
          .fill(page == current ? AnyShapeStyle(.themeAccent) : AnyShapeStyle(.secondary))
          .frame(width: Size.dot, height: Size.dot)
      }
    }
    .motion(.settle, value: current)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Page \(current.rawValue + 1) of \(TutorialPage.allCases.count)"))
  }
}

#if DEBUG
#Preview("First run") { ScreenPreview(.tutorial) }
#Preview("Practice") { ScreenPreview(.tutorial, page: TutorialPage.answer.rawValue) }
#endif
