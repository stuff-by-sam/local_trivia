import SwiftUI

/// Between questions: where you stand, and the room's standings.
struct StandingView: View {
  let standing: GameStore.Standing
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

      VStack(spacing: 12) {
        Text("Your position")
          .terminalStyle(.caption)
          .foregroundStyle(.secondary)
        // With the whole table below it (a phone-hosted game), the big
        // number steps down to make room.
        RankFigure(rank: standing.rank, size: store.leaderboard == nil ? 100 : 72)
        Text("of \(store.playerCount) · \(standing.score.grouped) pts")
          .terminalStyle(.subheadline)
          .foregroundStyle(.secondary)
        if let board = store.leaderboard {
          LeaderboardTable(board: board, playerName: store.playerName)
            .padding(.top, 20)
        }
      }

      Spacer()

      FooterStatus("Next question soon")
    }
    .screenPadding()
  }
}

/// Game over: where you finished, and who took the podium.
struct FinalView: View {
  let standing: GameStore.Standing
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

      Spacer(minLength: 16)

      VStack(spacing: 12) {
        Text("Game over")
          .terminalStyle(.caption)
          .foregroundStyle(.secondary)
        RankFigure(rank: standing.rank)
        Text("\(standing.score.grouped) pts")
          .terminalStyle(.subheadline)
          .foregroundStyle(.secondary)
      }

      if !standing.podium.isEmpty {
        Podium(placings: standing.podium, playerName: store.playerName)
          .padding(.top, 36)
      }

      Spacer(minLength: 16)

      FooterStatus("Waiting for the next game")
    }
    .screenPadding()
  }
}

/// Gold, green, cyan — the TV's podium colours (`PODIUM_STEPS` in present.js).
private enum Medal {
  case first, second, third

  init?(rank: Int?) {
    switch rank {
    case 1: self = .first
    case 2: self = .second
    case 3: self = .third
    default: return nil
    }
  }

  var color: Color {
    switch self {
    case .first: .broadcastGold
    case .second: .broadcastGreen
    case .third: AnswerStyle.b.color
    }
  }

  var height: CGFloat {
    switch self {
    case .first: 112
    case .second: 84
    case .third: 64
    }
  }

  var label: LocalizedStringKey {
    switch self {
    case .first: "1st"
    case .second: "2nd"
    case .third: "3rd"
    }
  }
}

/// The big number. Medal-coloured, with phosphor bloom, on the podium places.
private struct RankFigure: View {
  let rank: Int?
  var size: CGFloat = 100

  var body: some View {
    let tint = Medal(rank: rank)?.color ?? .primary
    HStack(alignment: .center, spacing: 12) {
      if rank == 1 {
        Image(systemName: "trophy.fill")
          .font(.system(size: size * 0.38))
          .symbolEffect(.bounce, options: .nonRepeating)
      }
      Text(verbatim: rank.map { "#\($0)" } ?? "—")
        .font(.mono(size: size, weight: .heavy))
        .minimumScaleFactor(0.5)
        .lineLimit(1)
    }
    .foregroundStyle(tint)
    .shadow(color: Medal(rank: rank) == nil ? .clear : tint.opacity(0.4), radius: 18)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rank.map { Text("Rank \($0)") } ?? Text("Unranked"))
  }
}

/// 2nd, 1st, 3rd — the same arrangement as the TV.
private struct Podium: View {
  let placings: [Placing]
  let playerName: String

  @Environment(\.accent) private var accent

  var body: some View {
    HStack(alignment: .bottom, spacing: 10) {
      ForEach([2, 1, 3], id: \.self) { rank in
        if let placing = placings.first(where: { $0.rank == rank }) ?? placings[safe: rank - 1],
          let medal = Medal(rank: rank)
        {
          column(placing, medal: medal)
        } else {
          // An empty place still holds its slot, so a one- or two-player
          // podium keeps its proportions instead of stretching.
          Color.clear
            .frame(maxWidth: .infinity, maxHeight: 1)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Podium")
  }

  private func column(_ placing: Placing, medal: Medal) -> some View {
    let isPlayer = placing.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame
    return VStack(spacing: 8) {
      VStack(spacing: 2) {
        Text(verbatim: placing.nickname)
          .font(.subheadline.weight(.semibold))
          .foregroundStyle(isPlayer ? accent : .primary)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
        Text(verbatim: placing.score.grouped)
          .font(.mono(.caption, weight: .medium))
          .foregroundStyle(.secondary)
      }
      Text(medal.label)
        .terminalStyle(.subheadline, weight: .heavy)
        .foregroundStyle(medal.color)
        .frame(maxWidth: .infinity, minHeight: medal.height, alignment: .top)
        .padding(.top, 12)
        .background {
          UnevenRoundedRectangle(topLeadingRadius: 12, topTrailingRadius: 12)
            .fill(
              LinearGradient(
                colors: [medal.color.opacity(isPlayer ? 0.32 : 0.2), medal.color.opacity(0.02)],
                startPoint: .top,
                endPoint: .bottom
              )
            )
        }
        .overlay(alignment: .top) {
          // A lit edge along the top of each step.
          Rectangle()
            .fill(medal.color.opacity(0.8))
            .frame(height: 2)
            .clipShape(.capsule)
        }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
  }
}

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}
