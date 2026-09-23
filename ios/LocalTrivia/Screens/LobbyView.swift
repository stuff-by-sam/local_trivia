import SwiftUI

/// Joined, waiting for the host to start.
struct LobbyView: View {
  let glass: Namespace.ID

  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host

  var body: some View {
    VStack(spacing: 0) {
      TopBar(glass: glass) {
        PlayerChip()
      } trailing: {
        if host.isHosting { HostMenu() } else { LeaveButton() }
      }

      Spacer()

      VStack(spacing: 26) {
        VStack(spacing: 10) {
          Text("You're in")
            .terminalStyle(.caption)
            .foregroundStyle(.secondary)
          Text(verbatim: store.playerName)
            .font(.system(size: 44, weight: .bold))
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
              .animation(.snappy, value: store.playerCount)
          }
        }
      }

      Spacer()

      FooterStatus("Waiting for host")
    }
    .screenPadding()
  }
}

/// Joined mid-question: the server scores you from the next one.
struct SpectatingView: View {
  let glass: Namespace.ID

  @Environment(GameStore.self) private var store

  var body: some View {
    VStack(spacing: 0) {
      TopBar(glass: glass) {
        PlayerChip()
      } trailing: {
        HStack(spacing: 8) {
          ProgressChip(glass: glass)
          GameControls()
        }
      }

      Spacer()

      VStack(spacing: 28) {
        VStack(spacing: 18) {
          Image(systemName: "hourglass")
            .font(.system(size: 36, weight: .semibold))
            .foregroundStyle(.secondary)
            .symbolEffect(.pulse, options: .repeating)
            .frame(width: 92, height: 92)
            .glassEffect(in: .circle)
            .accessibilityHidden(true)

          VStack(spacing: 8) {
            Text("Hold tight")
              .font(.mono(.title3, weight: .heavy))
              .textCase(.uppercase)
              .tracking(4)
              .accessibilityAddTraits(.isHeader)
            Text("You'll jump in on the next question.")
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
  }
}
