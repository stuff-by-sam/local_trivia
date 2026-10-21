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
    // Nobody hosts or joins before agreeing to the terms.
    .fullScreenCover(isPresented: Binding { !safety.hasAcceptedTerms } set: { _ in }) {
      TermsView(isAgreeing: true)
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
    .onChange(of: browser.games) { _, _ in store.discovered(listedGames, isComplete: browser.hasSettled) }
    .onChange(of: store.connection) { _, _ in store.discovered(listedGames, isComplete: browser.hasSettled) }
    .onChange(of: browser.hasSettled) { _, settled in store.discovered(listedGames, isComplete: settled) }
    .onChange(of: safety.blockedHosts) { _, _ in store.discovered(listedGames, isComplete: browser.hasSettled) }
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
      guard safety.hasAcceptedTerms, let link = JoinLink(url: url), !host.isHosting, !store.isInGame || store.server == link.server
      else { return }
      guard !safety.isBlocked(link.server, hostID: browser.hostIDs[link.server.url]) else {
        store.noteBlockedHost()
        return
      }
      store.join(link.server, pin: link.pin)
    }
    .onChange(of: store.isInGame, initial: true) { _, inGame in
      // A phone that auto-locks between questions misses the next one.
      UIApplication.shared.isIdleTimerDisabled = inGame
      // Nothing in a game uses the list of games, so stop looking for them
      // until the player's back at the join screen.
      if inGame { browser.stop() } else { browser.start() }
    }
  }

  /// The games on the network, less those of hosts this phone has blocked.
  private var listedGames: [GameServer] {
    browser.games.filter { !safety.isBlocked($0, hostID: browser.hostIDs[$0.url]) }
  }

  private var column: some View {
    screen
      .id(store.phase.screen)
      .screenTransition()
      .gameColumn()
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
  /// On iPad, keeps the phone-sized column the game is designed for, centred.
  func gameColumn() -> some View {
    frame(maxWidth: Size.column)
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
