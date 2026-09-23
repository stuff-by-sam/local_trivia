import DesignSystem
import SwiftUI

/// Joined, waiting for the host to start.
struct LobbyView: View {
  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

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

        if host.isHosting {
          JoinCodeCard()
        }

        Readout {
          if let server = store.server, !host.isHosting {
            ReadoutRow("Host") { Text(verbatim: server.name) }
          }
          ReadoutRow("Players") {
            Text(store.playerCount, format: .number)
              .contentTransition(.numericText(value: Double(store.playerCount)))
              .motion(.snap, value: store.playerCount)
          }
        }
      }

      Spacer()

      FooterStatus("Waiting for host")
    }
    .screenPadding()
    .gameToolbar(.player, controls: .always)
  }
}

/// Joined mid-question: the server scores you from the next one.
struct SpectatingView: View {
  @Environment(GameStore.self) private var store

  var body: some View {
    VStack(spacing: 0) {
      Spacer()

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

      Spacer()

      StatusLine("Scores start next question")
    }
    .screenPadding()
    .gameToolbar(.player, status: .progress)
  }
}
