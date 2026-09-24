import DesignSystem
import SwiftUI

/// The game on a TV, for the whole room: the join code while people arrive,
/// each question with its clock, the reveal with how the room voted, the
/// standings and the podium.
///
/// It follows `GameStore.broadcast` — the game's progress, not the phone's own
/// player — and is drawn on a fixed 1920×1080 canvas scaled to the display, so
/// it reads the same on any TV, from the back of the room.
struct BigScreenView: View {
  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host

  var body: some View {
    GeometryReader { proxy in
      let canvas = TVMetrics.canvas
      let scale = min(proxy.size.width / canvas.width, proxy.size.height / canvas.height)
      board
        .id(boardID)
        .transition(.opacity)
        // TVs crop their edges: keep everything inside the title-safe area.
        .padding(TVMetrics.safeInsets)
        .frame(width: canvas.width, height: canvas.height)
        .scaleEffect(scale)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .background { Backdrop(mood: mood) }
    .motion(.screen, value: boardID)
  }

  @ViewBuilder
  private var board: some View {
    switch store.broadcast {
    case .question(let question, let window):
      QuestionBoard(gameName: gameName, question: question, window: window, answered: store.answered)
    case .reveal(let question, let reveal):
      RevealBoard(gameName: gameName, question: question, reveal: reveal)
    case .standings(let standings):
      StandingsBoard(gameName: gameName, board: standings)
    case .final(let podium):
      FinalBoard(gameName: gameName, podium: podium)
    case .lobby, nil:
      if store.isInGame || host.isHosting {
        LobbyBoard(gameName: gameName)
      } else {
        IdleBoard()
      }
    }
  }

  private var gameName: String {
    host.isHosting ? host.gameName : store.server?.name ?? ""
  }

  /// One identity per board, so each question or reveal cross-fades in.
  private var boardID: String {
    switch store.broadcast {
    case .question(let question, _): "question-\(question.questionId)"
    case .reveal(let question, _): "reveal-\(question.questionId)"
    case .standings(let standings): "standings-\(standings.afterQuestion)"
    case .final: "final"
    case .lobby, nil: store.isInGame || host.isHosting ? "lobby" : "idle"
    }
  }

  private var mood: Backdrop.Mood {
    switch store.broadcast {
    case .question: .question
    case .final: .celebrate
    case .reveal, .standings, .lobby, nil: .idle
    }
  }
}

// MARK: - Boards

/// Before any game: what this screen is for.
private struct IdleBoard: View {

  var body: some View {
    VStack(spacing: TVMetrics.gap) {
      AnswerSetMark()
        .tvRole(.answerSet)

      HStack(spacing: 0) {
        Text(verbatim: "TRIVIA")
        BlinkingCursor(glyph: "█")
      }
      // A logo: the cursor follows the word in every language.
      .environment(\.layoutDirection, .leftToRight)
      .tvRole(.wordmark)
      .foregroundStyle(.themeAccent)
      .glow(.tv)

      Text("Host a game on your phone, and it shows up here.")
        .tvRole(.idleLine)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}

/// People arriving: the join code, big, and who's in.
private struct LobbyBoard: View {
  let gameName: String

  @Environment(GameStore.self) private var store
  @Environment(HostController.self) private var host

  private static let shownNames = 24

  var body: some View {
    VStack(spacing: 0) {
      Masthead(gameName: gameName) {
        Text("^[\(playerCount) player](inflect: true)")
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: TVMetrics.gap)

      if host.isHosting, let game = host.game {
        HStack(alignment: .center, spacing: TVMetrics.wideGap) {
          VStack(alignment: .leading, spacing: TVMetrics.rowGap * 2) {
            Text("Join code")
              .tvRole(.joinLabel)
              .foregroundStyle(.secondary)
            Text(verbatim: game.pin)
              .tvRole(.pin)
              .foregroundStyle(.themeAccent)
              .glow(.tv)
            Text("Open Trivia on this Wi-Fi and type the code, or scan it with the Camera.")
              .tvRole(.instruction)
              .foregroundStyle(.secondary)
              .frame(maxWidth: TVMetrics.instructionWidth, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let link = host.joinLink {
            QRCodeView(payload: link.url.absoluteString)
              .frame(width: TVMetrics.qr, height: TVMetrics.qr)
          }
        }
      } else {
        WaitingLine("Waiting for the host to start")
      }

      Spacer(minLength: TVMetrics.gap)

      names
        .frame(minHeight: TVMetrics.tileHeight, alignment: .top)
    }
  }

  private var playerCount: Int {
    host.game?.connectedPlayers.count ?? store.playerCount
  }

  /// Everyone who's in, as the host's phone knows them. Other phones only
  /// know how many.
  @ViewBuilder
  private var names: some View {
    if let players = host.game?.connectedPlayers, !players.isEmpty {
      let shown = players.prefix(Self.shownNames)
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: TVMetrics.rowGap * 2), count: 6), spacing: TVMetrics.rowGap) {
        ForEach(shown) { player in
          Text(verbatim: player.nickname)
            .tvRole(.name)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, TVMetrics.rowGap * 2)
            .frame(maxWidth: .infinity, minHeight: TVMetrics.nameHeight)
            .background(.panel, in: .capsule)
        }
      }
      if players.count > shown.count {
        Text("and \(players.count - shown.count) more")
          .tvRole(.nameOverflow)
          .foregroundStyle(.secondary)
          .padding(.top, TVMetrics.rowGap)
      }
    }
  }
}

/// A question: its text, the clock, and the four answers as the phones show them.
private struct QuestionBoard: View {
  let gameName: String
  let question: Question
  let window: ClosedRange<Date>
  let answered: AnsweredCount?

  @State private var isRunningLow = false

  /// The phones and the TV presenter turn the clock red for the last ten seconds.
  private static let lowTime: TimeInterval = 10

  var body: some View {
    VStack(spacing: TVMetrics.gap) {
      Masthead(gameName: gameName) {
        HStack(spacing: TVMetrics.gap) {
          QuestionHeading(question: question)
          Label {
            Text(timerInterval: window, countsDown: true, showsHours: false)
          } icon: {
            Image(systemName: "timer")
          }
          .labelStyle(.titleAndIcon)
          .monospacedDigit()
          .foregroundStyle(isRunningLow ? AnyShapeStyle(.danger) : AnyShapeStyle(.primary))
        }
      }

      ProgressView(timerInterval: window, countsDown: true) {
        EmptyView()
      } currentValueLabel: {
        EmptyView()
      }
      .progressViewStyle(.linear)
      .tint(isRunningLow ? AnyShapeStyle(.danger) : AnyShapeStyle(.themeAccent))
      .scaleEffect(x: 1, y: TVMetrics.progressScale)

      Spacer(minLength: 0)

      // Host-authored: verbatim, never a localization key or Markdown.
      Text(verbatim: question.text)
        .tvRole(.question(length: question.text.count))
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: TVMetrics.textWidth)

      Spacer(minLength: 0)

      AnswerGrid(options: question.options)

      Group {
        if let answered, answered.total > 0 {
          Text("\(answered.answered) of \(answered.total) answered")
        } else {
          Text("Answer on your phone")
        }
      }
      .tvRole(.footer)
      .foregroundStyle(.secondary)
      .contentTransition(.numericText())
      .motion(.snap, value: answered)
    }
    .task(id: question.questionId) { await runClock() }
  }

  private func runClock() async {
    let end = window.upperBound
    isRunningLow = end.timeIntervalSinceNow <= Self.lowTime
    guard !isRunningLow else { return }
    try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow - Self.lowTime))
    guard !Task.isCancelled else { return }
    Motion.settle.perform { isRunningLow = true }
  }
}

/// The answer, and how the room voted.
private struct RevealBoard: View {
  let gameName: String
  let question: Question
  let reveal: Reveal

  var body: some View {
    VStack(spacing: TVMetrics.gap) {
      Masthead(gameName: gameName) {
        QuestionHeading(question: question)
      }

      Spacer(minLength: 0)

      Text(verbatim: question.text)
        .tvRole(.questionAtReveal)
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .minimumScaleFactor(0.6)
        .foregroundStyle(.secondary)
        .frame(maxWidth: TVMetrics.textWidth)

      Spacer(minLength: 0)

      AnswerGrid(options: question.options, correctIndex: reveal.correctIndex, votes: reveal.distribution)

      Text(summary)
        .tvRole(.footer)
        .foregroundStyle(.secondary)
    }
  }

  private var summary: LocalizedStringKey {
    let total = reveal.distribution.reduce(0, +)
    let right = reveal.distribution[safe: reveal.correctIndex] ?? 0
    return total == 0 ? "Nobody answered" : "\(right) of \(total) got it right"
  }
}

/// The room's standings between questions.
private struct StandingsBoard: View {
  let gameName: String
  let board: Leaderboard

  private static let shownRows = 8

  var body: some View {
    VStack(spacing: TVMetrics.gap) {
      Masthead(gameName: gameName) {
        Text(verbatim: "Q \(board.afterQuestion.twoDigits)/\(board.totalQuestions.twoDigits)")
          .foregroundStyle(.secondary)
      }

      Text("Standings")
        .tvRole(.sectionTitle)
        .foregroundStyle(.themeAccent)

      VStack(spacing: TVMetrics.rowGap) {
        ForEach(board.standings.prefix(Self.shownRows), id: \.nickname) { row in
          StandingRow(row: row)
        }
      }
      .frame(maxWidth: TVMetrics.tableWidth)

      Spacer(minLength: 0)

      Group {
        if board.remaining == 0 {
          Text("Final results next")
        } else {
          Text("^[\(board.remaining) question](inflect: true) to go")
        }
      }
      .tvRole(.footer)
      .foregroundStyle(.secondary)
    }
  }
}

private struct StandingRow: View {
  let row: Leaderboard.Row

  var body: some View {
    HStack(spacing: TVMetrics.gap) {
      Text(verbatim: row.rank.twoDigits)
        .tvRole(.rank)
        .foregroundStyle(Medal(rank: row.rank).map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.secondary))
        .frame(width: TVMetrics.rankWidth, alignment: .leading)
      Text(verbatim: row.nickname)
        .tvRole(.standingName)
        .lineLimit(1)
      if let delta = row.delta, delta != 0 {
        Text(verbatim: delta > 0 ? "▲\(delta)" : "▼\(-delta)")
          .tvRole(.standingDelta)
          .foregroundStyle(delta > 0 ? AnyShapeStyle(.success) : AnyShapeStyle(.danger))
      }
      Spacer(minLength: TVMetrics.gap)
      Text(verbatim: row.score.grouped)
        .tvRole(.standingScore)
        .monospacedDigit()
    }
    .padding(.horizontal, TVMetrics.gap)
    .frame(minHeight: TVMetrics.rowHeight)
    .background(.panel, in: .rect(cornerRadius: TVMetrics.rowRadius))
  }
}

/// Game over: the top three, on the podium.
private struct FinalBoard: View {
  let gameName: String
  let podium: [Placing]

  var body: some View {
    VStack(spacing: 0) {
      Masthead(gameName: gameName) {
        Text("Game over")
          .foregroundStyle(Medal.first.color)
      }

      Spacer(minLength: TVMetrics.gap)

      // 2nd, 1st, 3rd — as on the phones.
      HStack(alignment: .bottom, spacing: TVMetrics.gap) {
        ForEach([Medal.second, .first, .third], id: \.self) { medal in
          if let placing = podium.first(where: { $0.rank == medal.rawValue }) ?? podium[safe: medal.rawValue - 1] {
            TVPodiumStep(placing: placing, medal: medal)
          } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
          }
        }
      }
      .frame(maxWidth: TVMetrics.podiumWidth)
    }
  }
}

private struct TVPodiumStep: View {
  let placing: Placing
  /// Which step, whatever ties did to `placing.rank`.
  let medal: Medal

  var body: some View {
    VStack(spacing: TVMetrics.rowGap * 2) {
      if medal == .first {
        Image(systemName: "trophy.fill")
          .tvRole(.trophy)
          .foregroundStyle(medal.color)
          .glow(.tv, color: medal.color)
      }
      Text(verbatim: placing.nickname)
        .tvRole(.podiumName)
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      Text(verbatim: placing.score.grouped)
        .tvRole(.podiumScore)
        .foregroundStyle(.secondary)
      Text(medal.label)
        .tvRole(.podiumPlace)
        .textCase(.uppercase)
        .foregroundStyle(medal.color)
        .frame(maxWidth: .infinity, minHeight: TVMetrics.podiumStep(medal), alignment: .top)
        .padding(.top, TVMetrics.tileGap)
        .background {
          UnevenRoundedRectangle(topLeadingRadius: TVMetrics.stepRadius, topTrailingRadius: TVMetrics.stepRadius)
            .fill(LinearGradient(colors: [medal.color.opacity(0.3), medal.color.opacity(0.03)], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .top) {
          Rectangle().fill(medal.color.opacity(0.85)).frame(height: Space.xs)
        }
    }
    .frame(maxWidth: .infinity)
  }
}

// MARK: - Parts

/// "TRIVIA//FRIDAY QUIZ" on the left, where the game is on the right.
private struct Masthead<Trailing: View>: View {
  let gameName: String
  @ViewBuilder var trailing: Trailing

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: TVMetrics.gap) {
      HStack(spacing: 0) {
        Text(verbatim: "TRIVIA")
          .foregroundStyle(.themeAccent)
        if !gameName.isEmpty {
          Text(verbatim: "//\(gameName)")
            .foregroundStyle(.secondary)
        }
      }
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      Spacer(minLength: TVMetrics.gap)
      trailing
        .textCase(.uppercase)
    }
    .tvRole(.masthead)
  }
}

/// "Q 03/12 · SCIENCE".
private struct QuestionHeading: View {
  let question: Question

  var body: some View {
    HStack(spacing: TVMetrics.rowGap) {
      Text(verbatim: "Q \(question.qNum.twoDigits)/\(question.total.twoDigits)")
      if let category = question.category {
        Text(verbatim: "·")
          .foregroundStyle(.secondary)
        Text(verbatim: category)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
    }
  }
}

/// A status line in the game's voice, at TV size: `WAITING FOR THE HOST_`.
private struct WaitingLine: View {
  let text: LocalizedStringKey

  init(_ text: LocalizedStringKey) { self.text = text }

  var body: some View {
    HStack(spacing: Space.xxs) {
      Text(text)
      BlinkingCursor()
    }
    .tvRole(.waiting)
    .foregroundStyle(.secondary)
  }
}

/// The four answers, two by two. At the reveal the right one lights up in its
/// colour, the rest dim, and each shows how many chose it.
private struct AnswerGrid: View {
  let options: [String]
  var correctIndex: Int?
  var votes: [Int]?

  var body: some View {
    let styles = Array(AnswerStyle.allCases.prefix(options.count))
    Grid(horizontalSpacing: TVMetrics.tileGap, verticalSpacing: TVMetrics.tileGap) {
      ForEach(Array(stride(from: 0, to: styles.count, by: 2)), id: \.self) { start in
        GridRow {
          ForEach(styles[start..<min(start + 2, styles.count)]) { style in
            AnswerTile(
              style: style,
              text: options[style.rawValue],
              state: state(of: style.rawValue),
              votes: votes?[safe: style.rawValue],
              share: share(of: style.rawValue)
            )
          }
        }
      }
    }
  }

  private func state(of index: Int) -> AnswerTile.State {
    guard let correctIndex else { return .open }
    return index == correctIndex ? .correct : .wrong
  }

  private func share(of index: Int) -> Double? {
    guard let votes, let most = votes.max(), most > 0 else { return nil }
    return Double(votes[safe: index] ?? 0) / Double(most)
  }
}

private struct AnswerTile: View {
  enum State { case open, correct, wrong }

  let style: AnswerStyle
  let text: String
  let state: State
  var votes: Int?
  /// This answer's votes against the most any answer got, for its bar.
  var share: Double?

  var body: some View {
    let ink = state == .correct ? Palette.onAccentInk : style.color
    let shape = RoundedRectangle(cornerRadius: TVMetrics.tileRadius)
    HStack(spacing: TVMetrics.tileGap) {
      HStack(spacing: TVMetrics.rowGap) {
        Image(systemName: style.symbol)
          .imageScale(.small)
        Text(verbatim: style.letter)
      }
      .tvRole(.answerKey)
      .foregroundStyle(ink)
      .frame(width: TVMetrics.keyWidth, alignment: .leading)

      Text(verbatim: text)
        .tvRole(.answer)
        .lineLimit(2)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)

      if let votes {
        Text(votes, format: .number)
          .tvRole(.votes)
          .monospacedDigit()
      }
      if state == .correct {
        Image(systemName: "checkmark")
          .tvRole(.answerKey)
      }
    }
    .foregroundStyle(state == .correct ? AnyShapeStyle(.onAccent) : AnyShapeStyle(.primary))
    .padding(.horizontal, TVMetrics.gap)
    .frame(maxWidth: .infinity, minHeight: TVMetrics.tileHeight)
    .background {
      shape.fill(state == .correct ? style.color : style.color.opacity(0.12))
    }
    .overlay {
      shape.strokeBorder(style.color.opacity(state == .correct ? 0 : 0.5), lineWidth: 3)
    }
    .overlay(alignment: .bottomLeading) {
      if let share, share > 0 {
        GeometryReader { proxy in
          Capsule()
            .fill(state == .correct ? Palette.onAccentInk.opacity(0.35) : style.color)
            .frame(width: proxy.size.width * share, height: TVMetrics.voteBar)
        }
        .frame(height: TVMetrics.voteBar)
        .padding(.horizontal, TVMetrics.gap)
        .padding(.bottom, TVMetrics.rowGap)
      }
    }
    .opacity(state == .wrong ? 0.4 : 1)
  }
}

#if DEBUG
#Preview("Idle", traits: .landscapeLeft) { ScreenPreview(.tvIdle) }
#Preview("Lobby", traits: .landscapeLeft) { ScreenPreview(.tvLobby) }
#Preview("Question", traits: .landscapeLeft) { ScreenPreview(.tvQuestion) }
#Preview("Reveal", traits: .landscapeLeft) { ScreenPreview(.tvReveal) }
#Preview("Standings", traits: .landscapeLeft) { ScreenPreview(.tvStandings) }
#Preview("Final", traits: .landscapeLeft) { ScreenPreview(.tvFinal) }
#endif
