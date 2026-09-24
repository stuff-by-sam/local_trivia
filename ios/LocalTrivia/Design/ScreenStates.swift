#if DEBUG
import DesignSystem
import SwiftUI

// Every screen in its main states, from models held in memory: a player's
// store fed the events a host sends, with no socket behind it; the hosting
// engine talking straight to the host's own store; a round that's never
// saved; a shop that never asks the App Store. Nothing here touches the
// network.
//
// The screens' previews show these, and UI tests open one directly with
// `-screen <state>` (and `-theme <theme>`), for screens a test can't hold
// still on its own — a chosen answer, say, which a host playing alone
// answers straight past.

/// A screen, in one of its states.
enum ScreenState: String, CaseIterable {
  case joinSearching = "join.searching"
  case joinFound = "join.found"
  case joinWrongPIN = "join.wrongPIN"
  case joinLeft = "join.left"
  case joinHostEnded = "join.hostEnded"
  case joinRemoved = "join.removed"
  case lobby
  case spectating
  case question
  case questionChosen = "question.chosen"
  case questionTimeUp = "question.timeUp"
  case resultCorrect = "result.correct"
  case resultWrong = "result.wrong"
  case resultMissed = "result.missed"
  case standings
  case final
  case hostLobby = "host.lobby"
  case hostStandings = "host.standings"
  case hostFinal = "host.final"
  case roundEmpty = "round.empty"
  case round
  case editorNew = "editor.new"
  case editorEdit = "editor.edit"
  case drafting
  case drafts
  case scannerOff = "scanner.off"
  case scannerRestricted = "scanner.restricted"
  case players
  case joinCode
  case tvGuide
  case shop
  case tvIdle = "tv.idle"
  case tvLobby = "tv.lobby"
  case tvQuestion = "tv.question"
  case tvReveal = "tv.reveal"
  case tvStandings = "tv.standings"
  case tvFinal = "tv.final"
}

/// A screen state as the app would show it: in its navigation stack, over
/// its backdrop, with the app's models.
struct ScreenPreview: View {
  let state: ScreenState
  let theme: Theme

  @State private var models: PreviewModels
  @Namespace private var glass

  /// `chosen` is the answer a chosen question has picked, 0–3.
  init(_ state: ScreenState, theme: Theme = .phosphor, chosen: Int = 1) {
    self.state = state
    self.theme = theme
    _models = State(initialValue: PreviewModels(state, chosen: chosen))
  }

  /// `-screen question.chosen -theme amber -chosen 3`: that screen, for a UI test.
  static func fromLaunchArguments() -> ScreenPreview? {
    let defaults = UserDefaults.standard
    guard let name = defaults.string(forKey: "screen"), let state = ScreenState(rawValue: name) else { return nil }
    let theme = defaults.string(forKey: "theme").flatMap(Theme.init(rawValue:)) ?? .phosphor
    let chosen = defaults.object(forKey: "chosen") == nil ? 1 : defaults.integer(forKey: "chosen")
    return ScreenPreview(state, theme: theme, chosen: chosen)
  }

  var body: some View {
    content
      .theme(theme)
      .environment(models.store)
      .environment(models.browser)
      .environment(models.host)
      .environment(models.bigScreen)
      .environment(models.shop)
  }

  @ViewBuilder
  private var content: some View {
    switch state {
    case .joinSearching, .joinFound, .joinWrongPIN, .joinLeft, .joinHostEnded, .joinRemoved:
      game(glassContainer: false)
    case .roundEmpty, .round:
      over(HostSetupView())
    case .editorNew:
      over(NavigationStack { QuestionEditorView(question: .blank(), isNew: true, onSave: { _ in }, onDelete: { _ in }) })
    case .editorEdit:
      over(NavigationStack { QuestionEditorView(question: Sample.unfinished, isNew: false, onSave: { _ in }, onDelete: { _ in }) })
    case .drafting:
      over(DraftQuestionsView(round: Sample.round, topic: "the solar system", isDrafting: true) { _ in })
    case .drafts:
      over(DraftQuestionsView(round: Sample.round, topic: "the solar system", drafts: Sample.drafts, leftOut: 3) { _ in })
    case .scannerOff:
      over(QRScannerSheet(access: .denied) { _ in })
    case .scannerRestricted:
      over(QRScannerSheet(access: .restricted) { _ in })
    case .players:
      game(sheet: HostSheetView(sheet: .players))
    case .joinCode:
      game(sheet: HostSheetView(sheet: .joinCode))
    case .tvGuide:
      game(sheet: HostSheetView(sheet: .tv))
    case .shop:
      over(ShopView())
    case .tvIdle, .tvLobby, .tvQuestion, .tvReveal, .tvStandings, .tvFinal:
      BigScreenView()
        .environment(\.backdropFollowsTilt, false)
    default:
      game(glassContainer: true)
    }
  }

  /// The phase's screen, as `RootView` shows it.
  private func game(glassContainer: Bool) -> some View {
    NavigationStack {
      Group {
        if glassContainer {
          GlassEffectContainer(spacing: Space.xs) { screen }
        } else {
          screen
        }
      }
      .containerBackground(for: .navigation) { Backdrop(mood: mood) }
    }
  }

  /// A host sheet, over the screen it opens from.
  private func game(sheet: some View) -> some View {
    game(glassContainer: true)
      .sheet(isPresented: .constant(true)) { sheet }
  }

  /// A sheet, over the join screen it opens from.
  private func over(_ sheet: some View) -> some View {
    game(glassContainer: false)
      .sheet(isPresented: .constant(true)) { sheet }
  }

  @ViewBuilder
  private var screen: some View {
    let store = models.store
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
    switch models.store.phase {
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
}

/// The app's models, in memory, put in a screen state.
@MainActor
final class PreviewModels {
  let store: GameStore
  let host: HostController
  let browser = GameBrowser()
  let bigScreen = BigScreen()
  let shop: Shop

  init(_ state: ScreenState, chosen: Int = 1) {
    let defaults = UserDefaults(suiteName: "previews") ?? .standard
    defaults.removePersistentDomain(forName: "previews")
    store = GameStore(defaults: defaults, tokens: PreviewTokens(), makeTransport: { _ in nil })
    store.nickname = Sample.player
    host = HostController(library: HostLibrary(fileURL: nil), advertises: false)
    shop = Shop.preview(defaults: defaults)
    put(in: state, chosen: chosen)
  }

  private func put(in state: ScreenState, chosen: Int) {
    let question = Sample.question(elapsed: 6)
    let reveal = Reveal(correctIndex: 1, distribution: [1, 3, 1, 1])
    switch state {
    case .joinSearching, .tvIdle:
      break
    case .joinFound:
      online()
    case .joinWrongPIN:
      online()
      store.apply(.joinError(Notice(code: "WRONG_PIN", message: "WRONG PIN — CHECK THE HOST'S SCREEN")))
    case .joinLeft:
      online()
      joined()
      store.leave()
      store.handle(.connected)
    case .joinHostEnded:
      online()
      joined()
      store.apply(.kicked(Notice(code: "HOST_ENDED", message: "THE HOST ENDED THE GAME")))
    case .joinRemoved:
      online()
      joined()
      store.apply(.kicked(Notice(code: nil, message: "REMOVED BY THE HOST")))
    case .lobby:
      online()
      joined()
    case .spectating:
      online()
      joined(state: .questionActive)
    case .question, .tvQuestion:
      online()
      joined()
      store.apply(.questionStart(question))
      store.apply(.answeredCount(AnsweredCount(answered: 2, total: 6)))
    case .questionChosen:
      online()
      joined()
      store.apply(.questionStart(question))
      store.choose(chosen)
      store.apply(.answerAck(questionId: question.questionId))
      store.apply(.answeredCount(AnsweredCount(answered: 3, total: 6)))
    case .questionTimeUp:
      online()
      joined()
      store.apply(.questionStart(Sample.question(elapsed: question.timeLimit)))
    case .resultCorrect, .resultWrong, .resultMissed, .tvReveal:
      online()
      joined()
      store.apply(.questionStart(question))
      let chosen = state == .resultWrong ? 2 : 1
      if state != .resultMissed { store.choose(chosen) }
      store.apply(.questionEnd(reveal))
      store.apply(.personalResult(Sample.result(for: state == .resultMissed ? nil : chosen)))
    case .standings, .tvStandings:
      online()
      joined()
      store.apply(.questionStart(question))
      store.apply(.questionEnd(reveal))
      store.apply(.leaderboard(Sample.leaderboard))
      store.apply(.personalRank(RankUpdate(rank: 2, score: 2_450, phase: .leaderboard)))
    case .final, .tvFinal:
      online()
      joined()
      store.apply(.questionStart(question))
      store.apply(.gameOver(GameOver(podium: Sample.podium)))
      store.apply(.personalRank(RankUpdate(rank: 2, score: 5_120, phase: .podium)))
    case .hostLobby, .players, .joinCode, .tvGuide, .tvLobby:
      host.library.gameName = Sample.game.name
      host.startPreview(seating: store, others: Sample.others, round: Sample.round)
    case .hostStandings:
      host.library.gameName = Sample.game.name
      host.startPreview(seating: store, others: Sample.others, round: Sample.round, playing: .standings)
    case .hostFinal:
      host.library.gameName = Sample.game.name
      host.startPreview(seating: store, others: Sample.others, round: Sample.round, playing: .final)
    case .roundEmpty:
      break
    case .round, .editorNew, .editorEdit, .drafting, .drafts:
      host.library.questions = Sample.round
    case .scannerOff, .scannerRestricted, .shop:
      // Over a join screen still looking: the join screen's own sheets keep
      // its keyboard down, but these are presented from outside it.
      break
    }
  }

  /// FRIDAY QUIZ found on this Wi-Fi, and the link up — with no socket.
  private func online() {
    store.connect(to: Sample.game)
    store.handle(.connected)
  }

  private func joined(state: ServerState = .lobby) {
    store.apply(.joined(PlayerSnapshot(
      token: "preview", nickname: Sample.player, state: state, score: 0, rank: nil, playerCount: 6,
      eligibleFrom: state == .lobby ? 0 : 1, question: nil, lockedIndex: nil, lastResult: nil, podium: nil)))
  }
}

/// A resume token that's never kept.
private final class PreviewTokens: TokenStore, @unchecked Sendable {
  private var value: String?
  func load() -> String? { value }
  func save(_ token: String?) { value = token }
}

/// What the previews play with.
enum Sample {
  static let player = "ROBIN"
  static let others = ["SAM", "Alex", "Jordan", "Priya", "Maximilian-Alexander"]
  static let game = GameServer(address: "192.168.1.20:3000", name: "FRIDAY QUIZ")!

  static let round = [
    HostQuestion(text: "Which planet has the most moons?", options: ["Jupiter", "Saturn", "Uranus", "Neptune"], correct: 1, category: "SPACE"),
    HostQuestion(text: "What does LAN stand for?", options: ["Large Area Node", "Local Area Network", "Linked Access Net", "Long Antenna"], correct: 1, category: "TECH", timeLimit: 30),
    HostQuestion(text: "In which year did the Berlin Wall fall?", options: ["1987", "1988", "1989", "1991"], correct: 2, category: "HISTORY"),
    unfinished,
  ]

  /// A question with no right answer picked yet.
  static let unfinished = HostQuestion(text: "Who painted the Mona Lisa?", options: ["Leonardo da Vinci", "Michelangelo", "Raphael", "Donatello"], correct: -1, category: "ART")

  static let drafts = [
    HostQuestion(text: "Which planet is closest to the Sun?", options: ["Venus", "Mercury", "Mars", "Earth"], correct: 1, category: "THE SOLAR SYSTEM"),
    HostQuestion(text: "What is the largest planet in the solar system?", options: ["Saturn", "Neptune", "Jupiter", "Uranus"], correct: 2, category: "THE SOLAR SYSTEM"),
    HostQuestion(text: "Which planet has a day longer than its year?", options: ["Venus", "Mars", "Mercury", "Uranus"], correct: 0, category: "THE SOLAR SYSTEM"),
  ]

  static func question(elapsed seconds: Double) -> Question {
    Question(
      questionId: 3, index: 2, qNum: 3, total: 12, text: "Which planet has the most moons?",
      options: ["Jupiter", "Saturn", "Uranus", "Neptune"], category: "SPACE", timeLimit: 20, elapsedMs: seconds * 1000)
  }

  static func result(for chosen: Int?) -> AnswerResult {
    AnswerResult(
      correct: chosen == 1, points: chosen == 1 ? 870 : 0, totalScore: chosen == 1 ? 2_450 : 1_580,
      rank: chosen == 1 ? 2 : 4, answered: chosen != nil, chosenIndex: chosen ?? -1)
  }

  static let leaderboard = Leaderboard(
    standings: [
      .init(rank: 1, nickname: "SAM", score: 2_610, delta: 0),
      .init(rank: 2, nickname: player, score: 2_450, delta: 2),
      .init(rank: 3, nickname: "Priya", score: 2_300, delta: -1),
      .init(rank: 4, nickname: "Maximilian-Alexander", score: 1_980, delta: -1),
      .init(rank: 5, nickname: "Alex", score: 1_210, delta: 0),
      .init(rank: 6, nickname: "Jordan", score: 400, delta: nil),
    ],
    afterQuestion: 3, totalQuestions: 12, remaining: 9)

  static let podium = [
    Placing(rank: 1, nickname: "SAM", score: 5_380),
    Placing(rank: 2, nickname: player, score: 5_120),
    Placing(rank: 3, nickname: "Priya", score: 4_760),
  ]
}
#endif
