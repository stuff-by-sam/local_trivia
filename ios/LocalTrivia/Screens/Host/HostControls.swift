import DesignSystem
import SwiftUI

/// The host's menu, in the toolbar of every in-game screen: players, the join
/// code, the round, and the controls that don't belong on the action bar.
/// Draws nothing for players. Its sheets open from the root (`HostSheetView`).
struct HostMenu: View {
  @Environment(HostController.self) private var host
  @Environment(GameStore.self) private var store
  @Environment(BigScreen.self) private var bigScreen
  @State private var isConfirmingStop = false

  var body: some View {
    if host.isHosting, let game = host.game {
      Menu {
        Section {
          Button("Players (\(game.connectedPlayers.count))", systemImage: "person.2") { host.sheet = .players }
          Button("Show Join Code", systemImage: "qrcode") { host.sheet = .joinCode }
          Button(bigScreen.isConnected ? "On the TV" : "Show on a TV…", systemImage: "tv") { host.sheet = .tv }
          if game.state == .lobby || game.state == .podium {
            Button("Edit Round…", systemImage: "list.bullet.rectangle") { host.sheet = .round }
          }
        }
        if game.state == .questionActive {
          Section {
            Button("End Round Now", systemImage: "forward.end") { host.endRound() }
            Button("Skip Question", systemImage: "forward") { host.skipQuestion() }
          }
        }
        if game.state != .lobby, game.state != .podium {
          Button("End Game", systemImage: "flag.checkered") { host.endGame() }
        }
        Section {
          Button("Stop Hosting", systemImage: "xmark.circle", role: .destructive) { isConfirmingStop = true }
        }
      } label: {
        Label("Host controls", systemImage: "slider.horizontal.3")
      }
      // The one confirmation left in the app: stopping ends the game on every
      // phone, and there's no taking that back.
      .confirmationDialog("Stop hosting?", isPresented: $isConfirmingStop, titleVisibility: .visible) {
        Button("End the Game for Everyone", role: .destructive) {
          Task { await host.stop(leaving: store) }
        }
      } message: {
        Text("Every player goes back to the join screen.")
      }
    }
  }
}

/// What each sheet from the host's menu shows. They open from the root view,
/// not the menu, which lives in the toolbar; and the root outlives every
/// screen, so a sheet stays open as the game moves on.
struct HostSheetView: View {
  let sheet: HostController.Sheet

  var body: some View {
    switch sheet {
    case .players: PlayersSheet()
    case .joinCode: JoinCodeSheet()
    case .tv: BigScreenGuide()
    case .round: HostSetupView(isLive: true)
    }
  }
}

/// The host's next move, where players see what they're waiting for.
struct FooterStatus: View {
  let waiting: LocalizedStringKey

  init(_ waiting: LocalizedStringKey) { self.waiting = waiting }

  @Environment(HostController.self) private var host

  var body: some View {
    if host.isHosting, let action = host.nextAction {
      HostActionBar(action: action)
    } else {
      StatusLine(waiting)
    }
  }
}

private struct HostActionBar: View {
  let action: HostController.Action

  @Environment(HostController.self) private var host

  var body: some View {
    VStack(spacing: Space.s) {
      if let error = host.actionError {
        FieldMessage(Text(error), kind: .error)
      }
      ActionButton(title, systemImage: symbol, tapHaptic: .action) {
        host.perform(action)
      }
    }
    // Pinned to the bottom like any action bar, so it stops growing where one does.
    .dynamicTypeSize(...Size.barTypeLimit)
  }

  private var title: LocalizedStringKey {
    switch action {
    case .start: "Start Game"
    case .nextQuestion: "Next Question"
    case .finish: "Final Results"
    case .newGame: "Play Again"
    }
  }

  private var symbol: String {
    switch action {
    case .start: "play.fill"
    case .nextQuestion: "arrow.forward"
    case .finish: "flag.checkered"
    case .newGame: "arrow.counterclockwise"
    }
  }
}

/// PIN and QR code, for the host's lobby — where everyone else is looking.
struct JoinCodeCard: View {
  /// The lobby's lead: the code at its largest.
  var isHero = false

  @Environment(HostController.self) private var host
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    if let game = host.game {
      // The QR code goes under the code at accessibility sizes, rather than
      // squeezing it into a column beside.
      let layout = typeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.l))
        : AnyLayout(HStackLayout(alignment: .center, spacing: Space.l))
      layout {
        VStack(alignment: .leading, spacing: Space.s) {
          Text("Join code")
            .textRole(.label)
            .foregroundStyle(.secondary)
          Text(verbatim: game.pin)
            .textRole(.display(isHero ? .pinLarge : .pin))
            .foregroundStyle(.themeAccent)
            .glow(isHero ? .hero : .figure)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .accessibilityLabel(Text("PIN \(game.pin.map(String.init).joined(separator: " "))"))
          Text(host.lanAddress == nil ? "Turn on Wi-Fi or Personal Hotspot so others can join" : "Scan, or find \(host.gameName) in the app")
            .textRole(.labelSmall)
            .foregroundStyle(host.lanAddress == nil ? AnyShapeStyle(.warning) : AnyShapeStyle(.secondary))
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if let link = host.joinLink {
          QRCodeView(payload: link.url.absoluteString)
            .frame(width: Size.qrCard, height: Size.qrCard)
        }
      }
      .padding(Space.l)
      .panel()
    }
  }
}

/// The join code at full size, for holding the phone up to the room.
private struct JoinCodeSheet: View {
  @Environment(HostController.self) private var host

  var body: some View {
    VStack(spacing: Space.xl) {
      Text(verbatim: host.gameName)
        .textRole(.action)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
      if let link = host.joinLink {
        QRCodeView(payload: link.url.absoluteString)
          .frame(width: Size.qrFull, height: Size.qrFull)
      }
      VStack(spacing: Space.xs) {
        Text("PIN")
          .textRole(.label)
          .foregroundStyle(.secondary)
        Text(verbatim: host.game?.pin ?? "")
          .textRole(.display(.pinLarge))
          .foregroundStyle(.themeAccent)
          .glow(.hero)
      }
      Text("Open Trivia on the same Wi-Fi, or scan with the Camera.")
        .textRole(.detail)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(Space.xxl)
    .frame(maxWidth: .infinity)
    .scrollsWhenCrowded()
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
  }
}

/// How to put the game on a TV — and whether it's there yet. iOS keeps
/// screen mirroring in Control Center, out of any app's reach, so this points
/// the way rather than doing it.
private struct BigScreenGuide: View {
  @Environment(BigScreen.self) private var bigScreen
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          Label {
            Text(bigScreen.isConnected ? "The game is on the TV" : "No TV yet")
              .textRole(.bodyEmphasis)
          } icon: {
            StatusDot(bigScreen.isConnected ? .online : .connecting)
          }
          .motion(.settle, value: bigScreen.isConnected)
        } footer: {
          Text("The TV shows the join code, each question with its clock and answers, the reveal and the standings. Your phone keeps the controls, and your own answers.")
        }

        Section {
          Label("Open Control Center and tap Screen Mirroring.", systemImage: "rectangle.on.rectangle")
          Label("Choose your Apple TV, or a TV with AirPlay.", systemImage: "appletv")
          Label("Or connect the phone to a TV with an HDMI adapter.", systemImage: "cable.connector")
        } header: {
          SectionHeader("Connect a TV")
        }
      }
      .navigationTitle("Show on a TV")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
  }
}

/// Everyone in the game, with the host's power to remove them.
private struct PlayersSheet: View {
  @Environment(HostController.self) private var host
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if let game = host.game {
          ForEach(game.players) { player in
            PlayerRow(player: player, isHost: host.isHost(player))
              .swipeActions {
                if !host.isHost(player) {
                  Button("Remove", systemImage: "person.fill.xmark", role: .destructive) { host.kick(player) }
                }
              }
          }
        }
      }
      .overlay {
        if host.game?.players.isEmpty ?? true {
          ContentUnavailableView("Nobody Yet", systemImage: "person.2", description: Text("Players appear here as they join."))
        }
      }
      .navigationTitle("Players")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
  }
}

/// A player in a list: who, whether they're here, and their score.
struct PlayerRow: View {
  let player: HostedGame.Player
  let isHost: Bool

  var body: some View {
    HStack(spacing: Space.m) {
      StatusDot(player.isConnected ? .online : .idle)
      Text(verbatim: player.nickname)
        .textRole(isHost ? .bodyEmphasis : .body)
      if isHost {
        Text("You")
          .textRole(.labelSmall)
          .foregroundStyle(.themeAccent)
      }
      if !player.isConnected {
        Text("Away")
          .textRole(.labelSmall)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Text(verbatim: player.score.grouped)
        .textRole(.figure)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .combine)
  }
}

/// Black on white with a quiet zone: what every scanner reads first time.
struct QRCodeView: View {
  let payload: String

  var body: some View {
    if let image = QRCode.image(for: payload) {
      Image(uiImage: image)
        .interpolation(.none)
        .resizable()
        .scaledToFit()
        .padding(Space.s)
        .background(.white, in: .rect(cornerRadius: Radius.concentric(in: Radius.panel, inset: Space.l)))
        .accessibilityLabel("QR code to join this game")
    }
  }
}

/// Everyone's standings, in games with no TV to show them.
struct LeaderboardTable: View {
  let board: Leaderboard
  let playerName: String

  @Environment(\.dynamicTypeSize) private var typeSize

  private static let visibleRows = 5

  var body: some View {
    Readout {
      // By name — unique in a game — so a row keeps its identity as its rank
      // and score change.
      ForEach(rows, id: \.nickname) { row in
        let isPlayer = row.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame
        Group {
          if typeSize.isAccessibilitySize {
            // No room for four things on a line: the name wraps, and the
            // score goes under it.
            VStack(alignment: .leading, spacing: Space.xs) {
              HStack(alignment: .firstTextBaseline, spacing: Space.m) {
                rank(row)
                name(row, isPlayer: isPlayer)
              }
              HStack(spacing: Space.m) {
                delta(row)
                Spacer(minLength: Space.s)
                score(row)
              }
            }
          } else {
            HStack(spacing: Space.m) {
              rank(row)
              name(row, isPlayer: isPlayer)
                .lineLimit(1)
              delta(row)
              Spacer(minLength: Space.s)
              score(row)
            }
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(row, isPlayer: isPlayer))
      }
    }
  }

  private func spoken(_ row: Leaderboard.Row, isPlayer: Bool) -> Text {
    let name = isPlayer ? String(localized: "\(row.nickname) (you)") : row.nickname
    let standing = String(localized: "\(row.rank), \(name), \(row.score) points")
    guard let delta = row.delta, delta != 0 else { return Text(verbatim: standing) }
    return Text(verbatim: standing + ", " + (delta > 0 ? String(localized: "up \(delta)") : String(localized: "down \(-delta)")))
  }

  private func rank(_ row: Leaderboard.Row) -> some View {
    Text(verbatim: row.rank.twoDigits)
      .textRole(.figure)
      .foregroundStyle(Medal(rank: row.rank).map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
  }

  private func name(_ row: Leaderboard.Row, isPlayer: Bool) -> some View {
    Text(verbatim: row.nickname)
      .textRole(isPlayer ? .bodyEmphasis : .body)
      .foregroundStyle(isPlayer ? AnyShapeStyle(.themeAccent) : AnyShapeStyle(.primary))
  }

  @ViewBuilder
  private func delta(_ row: Leaderboard.Row) -> some View {
    if let delta = row.delta, delta != 0 {
      Text(verbatim: delta > 0 ? "▲\(delta)" : "▼\(-delta)")
        .textRole(.figureSmall)
        .foregroundStyle(delta > 0 ? AnyShapeStyle(.success) : AnyShapeStyle(.danger))
    }
  }

  private func score(_ row: Leaderboard.Row) -> some View {
    Text(verbatim: row.score.grouped)
      .textRole(.figure)
  }

  /// The top five, plus the player if they're further down.
  private var rows: [Leaderboard.Row] {
    let top = Array(board.standings.prefix(Self.visibleRows))
    guard !top.contains(where: { $0.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame }),
      let mine = board.standings.first(where: { $0.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame })
    else { return top }
    return top + [mine]
  }
}
