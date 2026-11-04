import DesignSystem
import SwiftUI

/// Between questions: where you stand, and the room's standings.
struct StandingView: View {
  let standing: GameStore.Standing

  @Environment(GameStore.self) private var store
  @Environment(\.hasRoomToSpread) private var spreads

  var body: some View {
    Group {
      if spreads {
        // Your place on one half, at full size; the room's table on the other.
        Spread {
          place(isCompact: false)
            .scrollsWhenCrowded()
        } trail: {
          VStack(spacing: Space.m) {
            if let board = store.leaderboard {
              LeaderboardTable(board: board, playerName: store.playerName)
                .scrollsWhenCrowded()
            }
            FooterStatus("Next question soon")
          }
        }
      } else {
        VStack(spacing: Space.m) {
          VStack(spacing: Space.m) {
            // With the whole table below it (a phone-hosted game), the big
            // number steps down to make room.
            place(isCompact: store.leaderboard != nil)
            if let board = store.leaderboard {
              LeaderboardTable(board: board, playerName: store.playerName)
                .padding(.top, Space.l)
            }
          }
          .scrollsWhenCrowded()

          FooterStatus("Next question soon")
        }
      }
    }
    .screenPadding()
    .gameToolbar(.player, status: .progress)
  }

  private func place(isCompact: Bool) -> some View {
    VStack(spacing: Space.m) {
      Text("Your position")
        .textRole(.label)
        .foregroundStyle(.secondary)
      RankFigure(rank: standing.rank, isCompact: isCompact)
      Text("of \(ranked) · \(standing.score.grouped) pts")
        .textRole(.status)
        .foregroundStyle(.secondary)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(position)
  }

  /// "Your position: 2 of 6, 1,450 points."
  private var position: Text {
    guard let rank = standing.rank else { return Text("Your position: unranked, \(standing.score) points") }
    return Text("Your position: \(rank) of \(ranked), \(standing.score) points")
  }

  /// How many the rank is out of: everyone in the standings it came with —
  /// not whoever's connected now, or a room that empties out reads "#6 of 2".
  private var ranked: Int {
    store.leaderboard?.standings.count ?? store.playerCount
  }
}

/// Game over: where you finished, and who took the podium.
struct FinalView: View {
  let standing: GameStore.Standing

  @Environment(GameStore.self) private var store
  @Environment(\.hasRoomToSpread) private var spreads

  var body: some View {
    Group {
      if spreads {
        // Where you finished on one half; the podium on the other.
        Spread {
          finish
            .scrollsWhenCrowded()
        } trail: {
          VStack(spacing: Space.m) {
            if !standing.podium.isEmpty {
              Podium(placings: standing.podium, playerName: store.playerName)
                .scrollsWhenCrowded()
            }
            FooterStatus("Waiting for the next game")
          }
        }
      } else {
        VStack(spacing: Space.m) {
          VStack(spacing: 0) {
            finish

            if !standing.podium.isEmpty {
              Podium(placings: standing.podium, playerName: store.playerName)
                .padding(.top, Space.xxl)
            }
          }
          .padding(.vertical, Space.l)
          .scrollsWhenCrowded()

          FooterStatus("Waiting for the next game")
        }
      }
    }
    .screenPadding()
    .gameToolbar(.player)
  }

  private var finish: some View {
    VStack(spacing: Space.m) {
      Text("Game over")
        .textRole(.label)
        .foregroundStyle(.secondary)
      RankFigure(rank: standing.rank)
      Text("\(standing.score.grouped) pts")
        .textRole(.status)
        .foregroundStyle(.secondary)
    }
  }
}

/// 2nd, 1st, 3rd — the same arrangement as the TV.
private struct Podium: View {
  let placings: [Placing]
  let playerName: String

  @Environment(Safety.self) private var safety

  var body: some View {
    HStack(alignment: .bottom, spacing: Space.s) {
      ForEach([Medal.second, .first, .third], id: \.self) { medal in
        if let placing = placings.first(where: { $0.rank == medal.rawValue }) ?? placings[safe: medal.rawValue - 1] {
          PodiumStep(
            name: safety.shown(placing.nickname),
            score: placing.score.grouped,
            medal: medal,
            isPlayer: placing.nickname.localizedCaseInsensitiveCompare(playerName) == .orderedSame
          )
          .nameActions(placing.nickname)
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
