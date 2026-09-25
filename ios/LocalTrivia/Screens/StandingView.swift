import DesignSystem
import SwiftUI

/// Between questions: where you stand, and the room's standings.
struct StandingView: View {
  let standing: GameStore.Standing

  @Environment(GameStore.self) private var store

  var body: some View {
    VStack(spacing: Space.m) {
      VStack(spacing: Space.m) {
        VStack(spacing: Space.m) {
          Text("Your position")
            .textRole(.label)
            .foregroundStyle(.secondary)
          // With the whole table below it (a phone-hosted game), the big
          // number steps down to make room.
          RankFigure(rank: standing.rank, isCompact: store.leaderboard != nil)
          Text("of \(store.playerCount) · \(standing.score.grouped) pts")
            .textRole(.status)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position)
        if let board = store.leaderboard {
          LeaderboardTable(board: board, playerName: store.playerName)
            .padding(.top, Space.l)
        }
      }
      .scrollsWhenCrowded()

      FooterStatus("Next question soon")
    }
    .screenPadding()
    .gameToolbar(.player, status: .progress)
  }

  /// "Your position: 2 of 6, 1,450 points."
  private var position: Text {
    guard let rank = standing.rank else { return Text("Your position: unranked, \(standing.score) points") }
    return Text("Your position: \(rank) of \(store.playerCount), \(standing.score) points")
  }
}

/// Game over: where you finished, and who took the podium.
struct FinalView: View {
  let standing: GameStore.Standing

  @Environment(GameStore.self) private var store

  var body: some View {
    VStack(spacing: Space.m) {
      VStack(spacing: 0) {
        VStack(spacing: Space.m) {
          Text("Game over")
            .textRole(.label)
            .foregroundStyle(.secondary)
          RankFigure(rank: standing.rank)
          Text("\(standing.score.grouped) pts")
            .textRole(.status)
            .foregroundStyle(.secondary)
        }

        if !standing.podium.isEmpty {
          Podium(placings: standing.podium, playerName: store.playerName)
            .padding(.top, Space.xxl)
        }
      }
      .padding(.vertical, Space.l)
      .scrollsWhenCrowded()

      FooterStatus("Waiting for the next game")
    }
    .screenPadding()
    .gameToolbar(.player, controls: .always)
  }
}

/// 2nd, 1st, 3rd — the same arrangement as the TV.
private struct Podium: View {
  let placings: [Placing]
  let playerName: String

  var body: some View {
    HStack(alignment: .bottom, spacing: Space.s) {
      ForEach([Medal.second, .first, .third], id: \.self) { medal in
        if let placing = placings.first(where: { $0.rank == medal.rawValue }) ?? placings[safe: medal.rawValue - 1] {
          PodiumStep(
            name: placing.nickname,
            score: placing.score.grouped,
            medal: medal,
            isPlayer: placing.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame
          )
        } else {
          // An empty place still holds its slot, so a one- or two-player
          // podium keeps its proportions instead of stretching.
          Color.clear
            .frame(maxWidth: .infinity, maxHeight: 0)
            .accessibilityHidden(true)
        }
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel("Podium")
  }
}

extension Array {
  subscript(safe index: Int) -> Element? {
    indices.contains(index) ? self[index] : nil
  }
}

#if DEBUG
#Preview("Standings") { ScreenPreview(.standings) }
#Preview("Host's standings") { ScreenPreview(.hostStandings) }
#Preview("Final") { ScreenPreview(.final) }
#Preview("Host's final") { ScreenPreview(.hostFinal) }
#endif
