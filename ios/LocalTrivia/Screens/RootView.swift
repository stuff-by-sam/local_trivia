import SwiftUI

/// Routes the game's phase to a screen, over one shared backdrop and one glass
/// container, so elements tagged "hero" flow between screens as the game moves.
struct RootView: View {
  @Environment(GameStore.self) private var store
  @Environment(GameBrowser.self) private var browser
  @Environment(HostController.self) private var host
  @Environment(Shop.self) private var shop
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.accent) private var accent
  @Namespace private var glass
  /// Only once: coming back to the app goes straight to the game.
  @State private var isLaunching = true

  var body: some View {
    @Bindable var host = host
    ZStack {
      Backdrop(mood: mood, accent: accent)
      // Tighter than any gap between controls: the four answers must read as
      // four targets, not melt into one column.
      GlassEffectContainer(spacing: 6) {
        screen
          .id(store.phase.screen)
          .transition(reduceMotion ? AnyTransition.opacity : AnyTransition(.blurReplace))
          // On iPad, keep the phone-sized column the game is designed for.
          .frame(maxWidth: 540)
          .frame(maxWidth: .infinity)
      }
    }
    .overlay {
      if isLaunching {
        LaunchView {
          withAnimation(.easeOut(duration: 0.4)) { isLaunching = false }
        }
        .transition(.opacity)
      }
    }
    .sheet(item: $host.sheet) { HostSheetView(sheet: $0) }
    .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.5), value: store.phase.screen)
    .sensoryFeedback(trigger: store.phase.screen) { _, _ in feedback }
    .tint(accent)
    .preferredColorScheme(.dark)
    .task {
      store.start()
      browser.start()
      shop.start()
    }
    .onChange(of: browser.games) { _, games in store.discovered(games) }
    .onChange(of: store.connection) { _, _ in store.discovered(browser.games) }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        store.sceneDidBecomeActive()
        host.appDidBecomeActive()
      case .background:
        host.appDidEnterBackground()
      default:
        break
      }
    }
    // A host's QR code, scanned with the Camera: straight into their game.
    .onOpenURL { url in
      guard let link = JoinLink(url: url), !host.isHosting, !store.isInGame || store.server == link.server else { return }
      store.join(link.server, pin: link.pin)
    }
    .onChange(of: store.isInGame, initial: true) { _, inGame in
      // A phone that auto-locks between questions misses the next one.
      UIApplication.shared.isIdleTimerDisabled = inGame
    }
  }

  @ViewBuilder
  private var screen: some View {
    switch store.phase {
    case .join: JoinView()
    case .lobby: LobbyView(glass: glass)
    case .spectating: SpectatingView(glass: glass)
    case .question(let round): QuestionView(round: round, glass: glass)
    case .result(let outcome): ResultView(outcome: outcome, glass: glass)
    case .standings(let standing): StandingView(standing: standing, glass: glass)
    case .final(let standing): FinalView(standing: standing, glass: glass)
    }
  }

  private var mood: Backdrop.Mood {
    switch store.phase {
    case .join, .lobby, .spectating, .standings: .idle
    case .question: .question
    case .result(let outcome):
      switch ResultView.Verdict(outcome.result) {
      case .correct: .correct
      case .wrong: .wrong
      case .missed: .missed
      }
    case .final: .celebrate
    }
  }

  private var feedback: SensoryFeedback? {
    switch store.phase {
    case .lobby: .success
    case .question: .start
    case .result(let outcome):
      switch ResultView.Verdict(outcome.result) {
      case .correct: .success
      case .wrong: .error
      case .missed: .warning
      }
    case .final: .success
    case .join, .spectating, .standings: nil
    }
  }
}

/// Glass identities shared across screens: an element with the same identity
/// on the outgoing and incoming screen morphs from one into the other.
nonisolated enum GlassID: Hashable, Sendable {
  /// The top bar's chips, which persist from screen to screen.
  case leadingChip
  case trailingChip
  case answer(Int)
  /// The verdict badge when there was no answer to flow from.
  case hero
}

extension GameStore.Phase {
  /// Which screen is showing. Every question is its own screen, so consecutive
  /// questions transition rather than mutating in place.
  enum Screen: Hashable {
    case join, lobby, spectating, question(Int), result, standings, final
  }

  var screen: Screen {
    switch self {
    case .join: .join
    case .lobby: .lobby
    case .spectating: .spectating
    case .question(let round): .question(round.question.questionId)
    case .result: .result
    case .standings: .standings
    case .final: .final
    }
  }
}
