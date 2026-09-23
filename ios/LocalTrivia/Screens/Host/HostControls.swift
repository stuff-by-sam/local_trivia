import SwiftUI

/// The host's menu, in the top bar of every in-game screen: players, the join
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
        Image(systemName: "slider.horizontal.3")
          .font(.subheadline.weight(.bold))
          .frame(width: 44, height: 44)
          .glassEffect(.regular.interactive(), in: .circle)
          .accessibilityLabel("Host controls")
      }
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
/// not the menu: the menu sits in the top bar, which holds text to one line
/// and caps Dynamic Type — limits a sheet would otherwise inherit. And the
/// root outlives every screen, so a sheet stays open as the game moves on.
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
  @Environment(\.accent) private var accent

  var body: some View {
    VStack(spacing: 10) {
      if let error = host.actionError {
        Label(error, systemImage: "exclamationmark.triangle.fill")
          .terminalStyle(.caption)
          .foregroundStyle(Color.broadcastRed)
      }
      Button {
        host.perform(action)
      } label: {
        HStack(spacing: 10) {
          Text(title)
          Image(systemName: symbol)
        }
        .terminalStyle(.headline, weight: .bold)
        .foregroundStyle(Color.broadcastInk)
        .frame(maxWidth: .infinity, minHeight: 32)
      }
      .buttonStyle(.glassProminent)
      .tint(accent)
      .controlSize(.large)
      .sensoryFeedback(.impact(weight: .medium), trigger: action)
    }
  }

  private var title: LocalizedStringKey {
    switch action {
    case .start: "Start Game"
    case .showStandings: "Show Standings"
    case .nextQuestion: "Next Question"
    case .finish: "Final Results"
    case .newGame: "Play Again"
    }
  }

  private var symbol: String {
    switch action {
    case .start: "play.fill"
    case .showStandings: "list.number"
    case .nextQuestion: "arrow.right"
    case .finish: "flag.checkered"
    case .newGame: "arrow.counterclockwise"
    }
  }
}

/// PIN and QR code, for the host's lobby — where everyone else is looking.
struct JoinCodeCard: View {
  @Environment(HostController.self) private var host
  @Environment(\.accent) private var accent

  var body: some View {
    if let game = host.game {
      HStack(alignment: .center, spacing: 18) {
        VStack(alignment: .leading, spacing: 8) {
          Text("Join code")
            .terminalStyle(.caption)
            .foregroundStyle(.secondary)
          Text(verbatim: game.pin)
            .font(.mono(size: 44, weight: .heavy))
            .tracking(6)
            .foregroundStyle(accent)
            .shadow(color: accent.opacity(0.4), radius: 10)
            .accessibilityLabel(Text("PIN \(game.pin.map(String.init).joined(separator: " "))"))
          Text(host.lanAddress == nil ? "Turn on Wi-Fi or Personal Hotspot so others can join" : "Scan, or find \(host.gameName) in the app")
            .terminalStyle(.caption2)
            .foregroundStyle(host.lanAddress == nil ? Color.broadcastGold : .secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
        if let link = host.joinLink {
          QRCodeView(payload: link.url.absoluteString)
            .frame(width: 104, height: 104)
        }
      }
      .padding(18)
      .background(.white.opacity(0.035), in: .rect(cornerRadius: 16))
      .overlay {
        RoundedRectangle(cornerRadius: 16).strokeBorder(.white.opacity(0.1), lineWidth: 1)
      }
    }
  }
}

/// The join code at full size, for holding the phone up to the room.
private struct JoinCodeSheet: View {
  @Environment(HostController.self) private var host
  @Environment(\.accent) private var accent

  var body: some View {
    VStack(spacing: 24) {
      Text(verbatim: host.gameName)
        .terminalStyle(.headline, weight: .bold)
        .foregroundStyle(.secondary)
      if let link = host.joinLink {
        QRCodeView(payload: link.url.absoluteString)
          .frame(width: 240, height: 240)
      }
      VStack(spacing: 6) {
        Text("PIN")
          .terminalStyle(.caption)
          .foregroundStyle(.secondary)
        Text(verbatim: host.game?.pin ?? "")
          .font(.mono(size: 64, weight: .heavy))
          .tracking(10)
          .foregroundStyle(accent)
          .shadow(color: accent.opacity(0.4), radius: 14)
      }
      Text("Open Trivia on the same Wi-Fi, or scan with the Camera.")
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
    .padding(28)
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background { Backdrop(mood: .idle, accent: accent) }
    .presentationDetents([.large])
    .presentationDragIndicator(.visible)
    .preferredColorScheme(.dark)
  }
}

/// How to put the game on a TV — and whether it's there yet. iOS keeps
/// screen mirroring in Control Center, out of any app's reach, so this points
/// the way rather than doing it.
private struct BigScreenGuide: View {
  @Environment(BigScreen.self) private var bigScreen
  @Environment(\.accent) private var accent
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack(spacing: 12) {
            StatusDot(color: bigScreen.isConnected ? accent : .secondary, isPulsing: !bigScreen.isConnected)
            Text(bigScreen.isConnected ? "The game is on the TV" : "No TV yet")
              .font(.body.weight(.semibold))
          }
          .animation(.smooth, value: bigScreen.isConnected)
        } footer: {
          Text("The TV shows the join code, each question with its clock and answers, the reveal and the standings. Your phone keeps the controls, and your own answers.")
        }
        .listRowBackground(RowBackground())

        Section {
          Label("Open Control Center and tap Screen Mirroring.", systemImage: "rectangle.on.rectangle")
          Label("Choose your Apple TV, or a TV with AirPlay.", systemImage: "appletv")
          Label("Or connect the phone to a TV with an HDMI adapter.", systemImage: "cable.connector")
        } header: {
          SectionHeader("Connect a TV")
        }
        .listRowBackground(RowBackground())
      }
      .scrollContentBackground(.hidden)
      .background { Backdrop(mood: .idle, accent: accent) }
      .navigationTitle("Show on a TV")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
    }
    .presentationDetents([.medium, .large])
    .preferredColorScheme(.dark)
  }
}

/// Everyone in the game, with the host's power to remove them.
private struct PlayersSheet: View {
  @Environment(HostController.self) private var host
  @Environment(\.accent) private var accent
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      List {
        if let game = host.game {
          ForEach(game.players) { player in
            let isHost = host.isHost(player)
            HStack(spacing: 12) {
              StatusDot(color: player.isConnected ? accent : .secondary)
              Text(verbatim: player.nickname)
                .font(.body.weight(isHost ? .bold : .regular))
              if isHost {
                Text("You")
                  .terminalStyle(.caption2, weight: .bold)
                  .foregroundStyle(accent)
              }
              if !player.isConnected {
                Text("Away")
                  .terminalStyle(.caption2)
                  .foregroundStyle(.tertiary)
              }
              Spacer()
              Text(verbatim: "\(player.score.grouped)")
                .font(.mono(.body, weight: .semibold))
                .foregroundStyle(.secondary)
            }
            .listRowBackground(RowBackground())
            .swipeActions {
              if !isHost {
                Button("Remove", systemImage: "person.fill.xmark", role: .destructive) { host.kick(player) }
                  .tint(Color.broadcastRed)  // not the accent: this is destructive
              }
            }
          }
        }
      }
      .scrollContentBackground(.hidden)
      .background { Backdrop(mood: .idle, accent: accent) }
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
    .preferredColorScheme(.dark)
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
        .padding(8)
        .background(.white, in: .rect(cornerRadius: 12))
        .accessibilityLabel("QR code to join this game")
    }
  }
}

/// Everyone's standings, in games with no TV to show them.
struct LeaderboardTable: View {
  let board: Leaderboard
  let playerName: String

  @Environment(\.accent) private var accent

  private static let visibleRows = 5

  var body: some View {
    Readout {
      ForEach(rows, id: \.self) { row in
        let isPlayer = row.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame
        HStack(spacing: 12) {
          Text(verbatim: row.rank.twoDigits)
            .font(.mono(.subheadline, weight: .bold))
            .foregroundStyle(Self.medal(row.rank) ?? .secondary)
          Text(verbatim: row.nickname)
            .font(.body.weight(isPlayer ? .bold : .regular))
            .foregroundStyle(isPlayer ? accent : .primary)
            .lineLimit(1)
          if let delta = row.delta, delta != 0 {
            Text(verbatim: delta > 0 ? "▲\(delta)" : "▼\(-delta)")
              .font(.mono(.caption, weight: .bold))
              .foregroundStyle(delta > 0 ? Color.broadcastGreen : Color.broadcastRed)
          }
          Spacer(minLength: 8)
          Text(verbatim: row.score.grouped)
            .font(.mono(.body, weight: .semibold))
        }
        .accessibilityElement(children: .combine)
      }
    }
  }

  /// The top five, plus the player if they're further down.
  private var rows: [Leaderboard.Row] {
    let top = Array(board.standings.prefix(Self.visibleRows))
    guard !top.contains(where: { $0.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame }),
      let mine = board.standings.first(where: { $0.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame })
    else { return top }
    return top + [mine]
  }

  static func medal(_ rank: Int) -> Color? {
    switch rank {
    case 1: .broadcastGold
    case 2: .broadcastGreen
    case 3: AnswerStyle.b.color
    default: nil
    }
  }
}
