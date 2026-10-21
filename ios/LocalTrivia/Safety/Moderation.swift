import DesignSystem
import SwiftUI

/// Reporting and blocking, as every screen offers them: each returns the
/// report to show, with what the block did written into it.
@MainActor
enum Moderation {
  /// The question on screen, or the one the room is on.
  static func currentQuestion(_ store: GameStore) -> Question? {
    switch store.phase {
    case .question(let round): return round.question
    case .result(let outcome): return outcome.question
    default:
      switch store.broadcast {
      case .question(let question, _), .reveal(let question, _): return question
      default: return nil
      }
    }
  }

  static func report(_ question: Question, store: GameStore, host: HostController) -> Report {
    Report(
      .question(text: question.text, options: question.options, category: question.category),
      gameName: gameName(store, host), isHost: host.isHosting)
  }

  static func report(player nickname: String, store: GameStore, host: HostController) -> Report {
    Report(.player(nickname: nickname), gameName: gameName(store, host), isHost: host.isHosting)
  }

  static func reportGame(store: GameStore, host: HostController) -> Report? {
    guard let name = gameName(store, host) else { return nil }
    return Report(.host(gameName: name), gameName: name, isHost: host.isHosting)
  }

  /// A host removes the player and keeps them out; a player hides the name.
  static func block(player nickname: String, store: GameStore, host: HostController, safety: Safety) -> Report? {
    if host.isHosting {
      guard let player = host.player(named: nickname) else { return nil }
      return host.block(player)
    }
    safety.hide(name: nickname)
    return Report(
      .player(nickname: nickname), gameName: gameName(store, host), isHost: false,
      blocked: "This player blocked the name: it's hidden on their phone.")
  }

  /// Leaves the game, and hides this host's games from now on.
  static func blockHost(store: GameStore, browser: GameBrowser, safety: Safety) -> Report? {
    guard let server = store.server else { return nil }
    safety.block(host: server, hostID: browser.hostIDs[server.url])
    store.leaveBlockedGame()
    return Report(
      .host(gameName: server.name), gameName: server.name, isHost: false,
      blocked: "This player blocked the host and left the game. The host's games are hidden on their phone.")
  }

  /// Whether the viewer can block `nickname`: not themselves, and as a host,
  /// only someone still in the game.
  static func canBlock(_ nickname: String, store: GameStore, host: HostController, safety: Safety) -> Bool {
    guard nickname.localizedCaseInsensitiveCompare(store.playerName) != .orderedSame else { return false }
    if host.isHosting { return host.player(named: nickname).map { !host.isHost($0) } ?? false }
    return !safety.isHidden(nickname)
  }

  private static func gameName(_ store: GameStore, _ host: HostController) -> String? {
    host.isHosting ? host.gameName : store.server?.name
  }
}

extension View {
  /// Touch and hold a player's name to report it or block them.
  func nameActions(_ nickname: String) -> some View {
    modifier(NameActions(nickname: nickname))
  }

  /// Touch and hold a question to report it — for players: the host wrote it.
  func questionActions(_ question: Question) -> some View {
    modifier(QuestionActions(question: question))
  }
}

private struct QuestionActions: ViewModifier {
  let question: Question

  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host
  @Environment(Safety.self) private var safety

  func body(content: Content) -> some View {
    if host.isHosting {
      content
    } else {
      content.contextMenu {
        Button("Report Question…", systemImage: "exclamationmark.bubble") {
          safety.report = Moderation.report(question, store: store, host: host)
        }
      }
    }
  }
}

private struct NameActions: ViewModifier {
  let nickname: String

  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host
  @Environment(Safety.self) private var safety

  func body(content: Content) -> some View {
    if Moderation.canBlock(nickname, store: store, host: host, safety: safety) {
      content.contextMenu {
        Button("Report \(nickname)…", systemImage: "exclamationmark.bubble") {
          safety.report = Moderation.report(player: nickname, store: store, host: host)
        }
        Button("Block \(nickname)", systemImage: "hand.raised", role: .destructive) {
          safety.report = Moderation.block(player: nickname, store: store, host: host, safety: safety)
        }
      }
    } else {
      content
    }
  }
}

/// A player's menu, in the toolbar of every in-game screen: report what's on
/// screen, block, or leave.
struct PlayerMenu: View {
  @Environment(GameStore.self) private var store
  @Environment(GameBrowser.self) private var browser
  @Environment(HostController.self) private var host
  @Environment(Safety.self) private var safety
  @State private var isConfirmingBlock = false
  @State private var isChoosingPlayer = false

  var body: some View {
    Menu {
      Section {
        if let question = Moderation.currentQuestion(store) {
          Button("Report Question…", systemImage: "exclamationmark.bubble") {
            safety.report = Moderation.report(question, store: store, host: host)
          }
        }
        Button("Report or Block a Player…", systemImage: "person.crop.circle.badge.exclamationmark") { isChoosingPlayer = true }
        Button("Report This Game…", systemImage: "flag") {
          safety.report = Moderation.reportGame(store: store, host: host)
        }
        Button("Block Host…", systemImage: "hand.raised", role: .destructive) { isConfirmingBlock = true }
      }
      Section {
        // Leaves at once: the join screen offers Undo for a few seconds,
        // which takes the seat back, score and all.
        Button("Leave Game", systemImage: "xmark") { store.leave() }
      }
    } label: {
      Label("Game menu", systemImage: "ellipsis")
    }
    .confirmationDialog("Block this game's host?", isPresented: $isConfirmingBlock, titleVisibility: .visible) {
      Button("Block and Report", role: .destructive) {
        safety.report = Moderation.blockHost(store: store, browser: browser, safety: safety)
      }
    } message: {
      Text("You'll leave the game, and this host's games won't be listed on this phone. A report goes to the developer.")
    }
    .sheet(isPresented: $isChoosingPlayer) { PlayerReportList() }
  }
}

/// The names this player has seen — in the standings and on the podium —
/// each to report or block.
private struct PlayerReportList: View {
  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host
  @Environment(Safety.self) private var safety
  @Environment(\.dismiss) private var dismiss
  @State private var report: Report?

  var body: some View {
    NavigationStack {
      List {
        ForEach(names, id: \.self) { name in
          HStack(spacing: Space.m) {
            Text(verbatim: safety.shown(name))
              .textRole(.body)
              .foregroundStyle(safety.isHidden(name) ? .secondary : .primary)
            Spacer(minLength: Space.s)
            Button("Report") { report = Moderation.report(player: name, store: store, host: host) }
              .buttonStyle(.glass)
            if Moderation.canBlock(name, store: store, host: host, safety: safety) {
              Button("Block", role: .destructive) {
                report = Moderation.block(player: name, store: store, host: host, safety: safety)
              }
              .buttonStyle(.glass)
            }
          }
        }
      }
      .overlay {
        if names.isEmpty {
          ContentUnavailableView(
            "No Names Yet", systemImage: "person.2",
            description: Text("Players' names show in the standings after each question."))
        }
      }
      .navigationTitle("Report a Player")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .reportSheet($report)
    }
    .presentationDetents([.medium, .large])
  }

  /// Everyone but this player, in standings order.
  private var names: [String] {
    let seen = (store.leaderboard?.standings.map(\.nickname) ?? []) + podium
    var unique: [String] = []
    for name in seen where name.localizedCaseInsensitiveCompare(store.playerName) != .orderedSame
      && !unique.contains(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame })
    {
      unique.append(name)
    }
    return unique
  }

  private var podium: [String] {
    if case .final(let standing) = store.phase { return standing.podium.map(\.nickname) }
    return []
  }
}
