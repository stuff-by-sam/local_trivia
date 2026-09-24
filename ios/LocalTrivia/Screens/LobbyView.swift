import DesignSystem
import SwiftUI

/// Joined, waiting for the host to start. The host's own lobby is about
/// getting everyone in: the join code first, and who's arrived.
struct LobbyView: View {
  @Environment(HostController.self) private var host

  var body: some View {
    Group {
      if host.isHosting {
        HostLobby()
      } else {
        PlayerLobby()
      }
    }
    .screenPadding()
    .gameToolbar(.player, controls: .always)
  }
}

private struct PlayerLobby: View {
  @Environment(GameStore.self) private var store

  var body: some View {
    VStack(spacing: Space.m) {
      VStack(spacing: Space.xl) {
        VStack(spacing: Space.s) {
          Text("You're in")
            .textRole(.label)
            .foregroundStyle(.secondary)
          Text(verbatim: store.playerName)
            .textRole(.title)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityAddTraits(.isHeader)
        }

        Readout {
          if let server = store.server {
            ReadoutRow("Host") { Text(verbatim: server.name) }
          }
          ReadoutRow("Players") {
            Text(store.playerCount, format: .number)
              .contentTransition(.numericText(value: Double(store.playerCount)))
              .motion(.snap, value: store.playerCount)
          }
        }
      }
      .scrollsWhenCrowded()

      StatusLine("Waiting for host")
    }
  }
}

private struct HostLobby: View {
  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host

  var body: some View {
    let names = host.game?.connectedPlayers.map(\.nickname) ?? []
    VStack(spacing: Space.m) {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.xl) {
          JoinCodeCard(isHero: true)
          VStack(alignment: .leading, spacing: Space.s) {
            Text("In the game · \(names.count)")
              .textRole(.label)
              .foregroundStyle(.secondary)
              .accessibilityAddTraits(.isHeader)
            NameChips(names: names, highlighted: store.playerName)
          }
        }
        .padding(.top, Space.l)
      }
      .scrollBounceBehavior(.basedOnSize)

      FooterStatus("Waiting for host")
    }
  }
}

/// Joined mid-question: the server scores you from the next one.
struct SpectatingView: View {
  @Environment(GameStore.self) private var store

  var body: some View {
    VStack(spacing: Space.m) {
      VStack(spacing: Space.xl) {
        VStack(spacing: Space.l) {
          Badge(symbol: "hourglass", color: .secondary, isGlass: false)
            .symbolEffect(.pulse, options: .repeating)

          VStack(spacing: Space.s) {
            Text("Hold tight")
              .textRole(.shout)
              .accessibilityAddTraits(.isHeader)
            Text("You'll jump in on the next question.")
              .textRole(.body)
              .foregroundStyle(.secondary)
              .multilineTextAlignment(.center)
          }
        }

        Readout {
          if let server = store.server {
            ReadoutRow("Host") { Text(verbatim: server.name) }
          }
          ReadoutRow("Players") { Text(store.playerCount, format: .number) }
        }
      }
      .scrollsWhenCrowded()

      StatusLine("Scores start next question")
    }
    .screenPadding()
    .gameToolbar(.player, status: .progress)
  }
}

#if DEBUG
#Preview("Lobby") { ScreenPreview(.lobby) }
#Preview("Host's lobby") { ScreenPreview(.hostLobby) }
#Preview("Spectating") { ScreenPreview(.spectating) }
#endif
