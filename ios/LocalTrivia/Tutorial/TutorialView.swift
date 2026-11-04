import DesignSystem
import SwiftUI

/// How to play, in seven short pages, each drawn with the game's own pieces:
/// joining, a practice question to answer for points, the standings, hosting,
/// playing nice, and making it yours.
///
/// Shown once after the terms on first launch (`FirstRunView`), where it can
/// be skipped; any time after from How to Play, a page of Settings. Either
/// way it's in a navigation stack of its presenter's.
struct TutorialView: View {
  /// First launch: Skip and Let's Play finish it for good.
  var isFirstRun = false
  /// What Let's Play does, when it's more than closing the tutorial: from
  /// Settings, it closes Settings too, and the game's next.
  var onPlay: (() -> Void)?

  @State private var page: TutorialPage
  @State private var practice = PracticeRound()
  @AppStorage(TutorialPage.seenKey) private var hasSeenTutorial = false
  @Environment(\.dismiss) private var dismiss

  init(isFirstRun: Bool = false, page: TutorialPage = .welcome, onPlay: (() -> Void)? = nil) {
    self.isFirstRun = isFirstRun
    self.onPlay = onPlay
    _page = State(initialValue: page)
  }

  var body: some View {
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
      // Anywhere else it's a page with a way back.
      if isFirstRun {
        ToolbarItem(placement: .cancellationAction) {
          Button("Skip", action: finish)
        }
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
      // Under the words, on a page spread across a big screen.
      .inSpreadsSecondHalf()
    }
    .containerBackground(for: .navigation) { Backdrop(mood: .idle) }
    .interactiveDismissDisabled(isFirstRun)
  }

  private func next() {
    guard let following = TutorialPage(rawValue: page.rawValue + 1) else { return finish() }
    Motion.screen.perform { page = following }
  }

  private func finish() {
    hasSeenTutorial = true
    if let onPlay { onPlay() } else { dismiss() }
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
      "Type the four-digit PIN from the host's screen and your nickname, and Trivia finds the game on your Wi-Fi. Can't find it? Scan the host's QR code instead."
    case .answer:
      "Every answer has a letter, a shape and a colour. Right answers score more the faster they come in. Try one:"
    case .standings:
      "After each question you'll see how the room voted and where you stand. The top three take the podium at the end. Lock your phone or lose Wi-Fi mid-game, and you're back in your seat when you return."
    case .host:
      "Tap Host a Game and build a round: write questions, draft them with Apple Intelligence, import a CSV, or copy a prompt into any AI chat. Then Start Hosting, and everyone joins with your PIN or QR code. You play too."
    case .safety:
      "No objectionable content, no abusive players. In a game, the ••• menu reports a question, a player or the game, or blocks the host; touch and hold a name to block that player. Hosts remove or block anyone from Players."
    case .looks:
      "Pick a theme, answer markers and an app icon, all free, in Settings: the gear on the join screen. How to Play is there too, any time."
    }
  }
}

/// One page: its picture, then what it's saying.
private struct TutorialPageView: View {
  let page: TutorialPage
  /// On screen: the practice question's clock only runs while it is.
  let isShowing: Bool
  let practice: PracticeRound

  @Environment(\.hasRoomToSpread) private var spreads

  var body: some View {
    if spreads {
      // The picture on one half, the words on the other — or, practising,
      // the words and the question on one, and its answers on the other.
      Spread {
        Group {
          if page == .answer {
            VStack(spacing: Space.xl) {
              words
              PracticeQuestion(round: practice, isShowing: isShowing, part: .question)
            }
          } else {
            picture
          }
        }
        .scrollsWhenCrowded()
      } trail: {
        Group {
          if page == .answer { PracticeQuestion(round: practice, isShowing: isShowing, part: .answers) } else { words }
        }
        .scrollsWhenCrowded()
      }
      .padding(.horizontal, Space.screen)
      .padding(.vertical, Space.l)
    } else {
      VStack(spacing: Space.xl) {
        picture
        words
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

  private var picture: some View {
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
  }

  private var words: some View {
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

/// The join screen in miniature: a PIN half typed, and the game it's found.
private struct JoinPicture: View {
  var body: some View {
    VStack(alignment: .leading, spacing: Space.s) {
      PINCells(pin: "48", length: GameStore.pinLength, isFocused: true)
      GameLine { StatusDot(.online) } label: {
        GameLineLabel(Text("Friday Quiz"), detail: Text("Found on your Wi-Fi"), isMenu: false)
      }
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
      Label("Safety, in Settings", systemImage: "gearshape")
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
