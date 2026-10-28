import DesignSystem
import SwiftUI

/// Routes the game's phase to a screen, in one navigation stack over one
/// shared backdrop and one glass container, so the answer you chose flows
/// into its verdict as the game moves.
struct RootView: View {
  @Environment(GameStore.self) private var store
  @Environment(GameBrowser.self) private var browser
  @Environment(HostController.self) private var host
  @Environment(Looks.self) private var looks
  @Environment(Safety.self) private var safety
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.hasRoomToSpread) private var spreads
  @AppStorage(TutorialPage.seenKey) private var hasSeenTutorial = false
  @Namespace private var glass

  var body: some View {
    @Bindable var host = host
    NavigationStack {
      Group {
        if store.phase == .join {
          // Outside the glass container: on iOS 27.0, glass buttons in a
          // safe-area bar inside one don't receive taps, and the join screen's
          // actions live in one. Nothing on it morphs anyway.
          column
        } else {
          // Tighter than any gap between controls: the four answers must read
          // as four targets, not melt into one column.
          GlassEffectContainer(spacing: Space.xs) { column }
        }
      }
      .containerBackground(for: .navigation) { Backdrop(mood: mood) }
    }
    .sheet(item: $host.sheet) { HostSheetView(sheet: $0) }
    // Over whatever's on screen: a block can end the game under it.
    .reportSheet(Binding { safety.report } set: { safety.report = $0 })
    // Nobody hosts or joins before agreeing to the terms; then how to play.
    .fullScreenCover(isPresented: Binding { !safety.hasAcceptedTerms || !hasSeenTutorial } set: { _ in }) {
      FirstRunView()
    }
    .motion(.screen, value: store.phase.screen)
    .haptic(trigger: store.phase.screen) { _, _ in haptic }
    .task {
      store.start()
      looks.start()
    }
    // Every symbol the game makes of glass, traced in the background before
    // it's needed — the worn markers first, then the reveal's — so none shows
    // as a stand-in first. After the first launch they're all kept already.
    .task(priority: .utility) {
      let markers = AnswerMarkers.allSymbols(first: looks.markers)
      let game = ResultView.Verdict.allCases.map(\.symbol) + ["trophy.fill", "arrowtriangle.up.fill", "arrowtriangle.down.fill", "hourglass"]
      await GlassSymbol.prepare(Array(markers.prefix(AnswerStyle.allCases.count)) + game + markers.dropFirst(AnswerStyle.allCases.count))
    }
    .onChange(of: looks.theme, initial: true) { _, theme in host.theme = theme }
    .onChange(of: browser.games) { _, _ in noteGamesFound() }
    .onChange(of: store.connection) { _, _ in noteGamesFound() }
    .onChange(of: browser.hasSettled) { _, _ in noteGamesFound() }
    .onChange(of: safety.blockedHosts) { _, _ in noteGamesFound() }
    .onChange(of: scenePhase) { _, phase in
      switch phase {
      case .active:
        store.sceneDidBecomeActive()
        host.appDidBecomeActive()
        // Back, perhaps from switching Local Network on: look again.
        if browser.hasFailed { browser.start() }
      case .background:
        host.appDidEnterBackground()
      default:
        break
      }
    }
    // A host's QR code, scanned with the Camera: straight into their game.
    .onOpenURL { url in
      guard safety.hasAcceptedTerms, let link = JoinLink(url: url), !host.isHosting, !store.isInGame || store.server == link.server
      else { return }
      store.join(link, safety: safety, browser: browser)
    }
    .onChange(of: store.isInGame, initial: true) { _, inGame in
      // A phone that auto-locks between questions misses the next one.
      UIApplication.shared.isIdleTimerDisabled = inGame
      // Nothing in a game uses the list of games. The join screen looks
      // again once the player sets out to join another.
      if inGame { browser.stop() }
    }
    // Relaunched with a seat in a game: look for it too, so one whose host
    // has stopped hosting is let go rather than retried for good.
    .onChange(of: store.isRejoining, initial: true) { _, rejoining in
      if rejoining { browser.start() }
    }
    // Where a spread finds the middle of the window — on iPhone Duo, the
    // hinge. Outermost, so the first run's cover and every sheet know it too.
    .measuresWindow()
  }

  /// What the browser's found, for the store to pick a game from — only while
  /// it's looking: a list from before is no news about the network.
  private func noteGamesFound() {
    guard browser.isLooking else { return }
    store.discovered(browser.games(shownBy: safety), isComplete: browser.hasSettled)
  }

  private var column: some View {
    screen
      .id(store.phase.screen)
      .screenTransition()
      // With room for a spread, each screen lays out its own halves.
      .gameColumn(unless: spreads)
      .glassClarity(store.phase.glassClarity)
  }

  @ViewBuilder
  private var screen: some View {
    switch store.phase {
    case .join: JoinView()
    case .lobby: LobbyView()
    case .spectating: SpectatingView()
    case .question(let round): QuestionView(round: round, glass: glass)
    case .result(let outcome): ResultView(outcome: outcome, glass: glass)
    case .standings(let standing): StandingView(standing: standing)
    case .final(let standing): FinalView(standing: standing)
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

  private var haptic: Haptic? {
    switch store.phase {
    case .lobby: .joined
    case .question: .questionStart
    case .result(let outcome):
      switch ResultView.Verdict(outcome.result) {
      case .correct: .correct
      case .wrong: .wrong
      case .missed: .missed
      }
    case .final: .correct
    case .join, .spectating, .standings: nil
    }
  }
}

extension View {
  /// On a big screen, keeps the phone-sized column the game is designed for,
  /// centred — `unless` the screen lays itself out as a `Spread` instead.
  func gameColumn(unless spreads: Bool = false) -> some View {
    frame(maxWidth: spreads ? .infinity : Size.column)
      .frame(maxWidth: .infinity)
  }
}

/// Glass identities shared across screens: an element with the same identity
/// on the outgoing and incoming screen morphs from one into the other.
nonisolated enum GlassID: Hashable, Sendable {
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

  /// Clear glass on the menus, where content is short and high-contrast;
  /// tinted once the game is on, where it has to be read at a glance.
  var glassClarity: GlassClarity {
    switch self {
    case .join, .lobby: .clear
    case .spectating, .question, .result, .standings, .final: .tinted
    }
  }
}
