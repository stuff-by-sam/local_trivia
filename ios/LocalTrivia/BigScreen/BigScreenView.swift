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
  @Environment(\.accent) private var accent

  static let canvas = CGSize(width: 1920, height: 1080)

  var body: some View {
    GeometryReader { proxy in
      let scale = min(proxy.size.width / Self.canvas.width, proxy.size.height / Self.canvas.height)
      board
        .id(boardID)
        .transition(.opacity)
        // TVs crop their edges: keep everything inside the title-safe area.
        .padding(.horizontal, 110)
        .padding(.vertical, 64)
        .frame(width: Self.canvas.width, height: Self.canvas.height)
        .scaleEffect(scale)
        .frame(width: proxy.size.width, height: proxy.size.height)
    }
    .background { Backdrop(mood: mood, accent: accent) }
    .animation(.smooth(duration: 0.6), value: boardID)
    // Set outright, not requested: a TV's window is nobody's to ask.
    .environment(\.colorScheme, .dark)
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
  @Environment(\.accent) private var accent

  var body: some View {
    VStack(spacing: 44) {
      HStack(spacing: 36) {
        ForEach(AnswerStyle.allCases) { style in
          Image(systemName: style.symbol)
            .foregroundStyle(style.color)
        }
      }
      .font(.system(size: 56))

      HStack(spacing: 0) {
        Text(verbatim: "TRIVIA")
          .tracking(20)
        BlinkingCursor(glyph: "█")
      }
      .font(.mono(size: 180, weight: .heavy))
      .foregroundStyle(accent)
      .shadow(color: accent.opacity(0.45), radius: 30)

      Text("Host a game on your phone, and it shows up here.")
        .font(.system(size: 44, weight: .medium))
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
  @Environment(\.accent) private var accent

  private static let shownNames = 24

  var body: some View {
    VStack(spacing: 0) {
      Masthead(gameName: gameName) {
        Text("^[\(playerCount) player](inflect: true)")
          .foregroundStyle(.secondary)
      }

      Spacer(minLength: 40)

      if host.isHosting, let game = host.game {
        HStack(alignment: .center, spacing: 110) {
          VStack(alignment: .leading, spacing: 20) {
            Text("Join code")
              .font(.mono(size: 36, weight: .semibold))
              .textCase(.uppercase)
              .tracking(4)
              .foregroundStyle(.secondary)
            Text(verbatim: game.pin)
              .font(.mono(size: 250, weight: .heavy))
              .tracking(24)
              .foregroundStyle(accent)
              .shadow(color: accent.opacity(0.45), radius: 30)
            Text("Open Trivia on this Wi-Fi and type the code, or scan it with the Camera.")
              .font(.system(size: 38, weight: .medium))
              .foregroundStyle(.secondary)
              .frame(maxWidth: 900, alignment: .leading)
              .fixedSize(horizontal: false, vertical: true)
          }
          if let link = host.joinLink {
            QRCodeView(payload: link.url.absoluteString)
              .frame(width: 400, height: 400)
          }
        }
      } else {
        WaitingLine("Waiting for the host to start")
      }

      Spacer(minLength: 40)

      names
        .frame(minHeight: 150, alignment: .top)
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
      LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 20), count: 6), spacing: 16) {
        ForEach(shown) { player in
          Text(verbatim: player.nickname)
            .font(.system(size: 32, weight: .semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 20)
            .frame(maxWidth: .infinity, minHeight: 64)
            .background(.white.opacity(0.07), in: .capsule)
        }
      }
      if players.count > shown.count {
        Text("and \(players.count - shown.count) more")
          .font(.mono(size: 30, weight: .semibold))
          .foregroundStyle(.secondary)
          .padding(.top, 16)
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

  @Environment(\.accent) private var accent
  @State private var isRunningLow = false

  /// The phones and the TV presenter turn the clock red for the last ten seconds.
  private static let lowTime: TimeInterval = 10

  var body: some View {
    VStack(spacing: 36) {
      Masthead(gameName: gameName) {
        HStack(spacing: 36) {
          QuestionNumber(question: question)
          HStack(spacing: 14) {
            Image(systemName: "timer")
            Text(timerInterval: window, countsDown: true, showsHours: false)
          }
          .monospacedDigit()
          .foregroundStyle(isRunningLow ? Color.broadcastRed : .primary)
        }
      }

      ProgressView(timerInterval: window, countsDown: true) {
        EmptyView()
      } currentValueLabel: {
        EmptyView()
      }
      .progressViewStyle(.linear)
      .tint(isRunningLow ? Color.broadcastRed : accent)
      .scaleEffect(x: 1, y: 2.5)

      Spacer(minLength: 0)

      // Host-authored: verbatim, never a localization key or Markdown.
      Text(verbatim: question.text)
        .font(.system(size: questionSize, weight: .bold))
        .multilineTextAlignment(.center)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: 1540)

      Spacer(minLength: 0)

      AnswerGrid(options: question.options)

      Group {
        if let answered, answered.total > 0 {
          Text("\(answered.answered) of \(answered.total) answered")
        } else {
          Text("Answer on your phone")
        }
      }
      .font(.mono(size: 32, weight: .semibold))
      .textCase(.uppercase)
      .tracking(3)
      .foregroundStyle(.secondary)
      .contentTransition(.numericText())
      .animation(.snappy, value: answered)
    }
    .task(id: question.questionId) { await runClock() }
  }

  /// Short questions go big; long ones step down so the answers keep their room.
  private var questionSize: CGFloat {
    switch question.text.count {
    case ...60: 92
    case ...120: 76
    case ...200: 62
    default: 52
    }
  }

  private func runClock() async {
    let end = window.upperBound
    isRunningLow = end.timeIntervalSinceNow <= Self.lowTime
    guard !isRunningLow else { return }
    try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow - Self.lowTime))
    guard !Task.isCancelled else { return }
    withAnimation(.smooth) { isRunningLow = true }
  }
}

/// The answer, and how the room voted.
private struct RevealBoard: View {
  let gameName: String
  let question: Question
  let reveal: Reveal

  var body: some View {
    VStack(spacing: 36) {
      Masthead(gameName: gameName) {
        QuestionNumber(question: question)
      }

      Spacer(minLength: 0)

      Text(verbatim: question.text)
        .font(.system(size: 52, weight: .semibold))
        .multilineTextAlignment(.center)
        .lineLimit(3)
        .minimumScaleFactor(0.6)
        .foregroundStyle(.secondary)
        .frame(maxWidth: 1540)

      Spacer(minLength: 0)

      AnswerGrid(options: question.options, correctIndex: reveal.correctIndex, votes: reveal.distribution)

      Text(summary)
        .font(.mono(size: 32, weight: .semibold))
        .textCase(.uppercase)
        .tracking(3)
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

  @Environment(\.accent) private var accent

  private static let shownRows = 8

  var body: some View {
    VStack(spacing: 36) {
      Masthead(gameName: gameName) {
        Text(verbatim: "Q \(board.afterQuestion.twoDigits)/\(board.totalQuestions.twoDigits)")
          .foregroundStyle(.secondary)
      }

      Text("Standings")
        .font(.mono(size: 64, weight: .heavy))
        .textCase(.uppercase)
        .tracking(10)
        .foregroundStyle(accent)

      VStack(spacing: 12) {
        ForEach(board.standings.prefix(Self.shownRows), id: \.self) { row in
          StandingRow(row: row)
        }
      }
      .frame(maxWidth: 1400)

      Spacer(minLength: 0)

      Group {
        if board.remaining == 0 {
          Text("Final results next")
        } else {
          Text("^[\(board.remaining) question](inflect: true) to go")
        }
      }
      .font(.mono(size: 32, weight: .semibold))
      .textCase(.uppercase)
      .tracking(3)
      .foregroundStyle(.secondary)
    }
  }
}

private struct StandingRow: View {
  let row: Leaderboard.Row

  var body: some View {
    HStack(spacing: 32) {
      Text(verbatim: row.rank.twoDigits)
        .font(.mono(size: 44, weight: .heavy))
        .foregroundStyle(LeaderboardTable.medal(row.rank) ?? .secondary)
        .frame(width: 90, alignment: .leading)
      Text(verbatim: row.nickname)
        .font(.system(size: 46, weight: .semibold))
        .lineLimit(1)
      if let delta = row.delta, delta != 0 {
        Text(verbatim: delta > 0 ? "▲\(delta)" : "▼\(-delta)")
          .font(.mono(size: 32, weight: .bold))
          .foregroundStyle(delta > 0 ? Color.broadcastGreen : Color.broadcastRed)
      }
      Spacer(minLength: 32)
      Text(verbatim: row.score.grouped)
        .font(.mono(size: 46, weight: .bold))
        .monospacedDigit()
    }
    .padding(.horizontal, 36)
    .frame(minHeight: 76)
    .background(.white.opacity(row.rank <= 3 ? 0.08 : 0.04), in: .rect(cornerRadius: 18))
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
          .foregroundStyle(Color.broadcastGold)
      }

      Spacer(minLength: 40)

      // 2nd, 1st, 3rd — as on the phones.
      HStack(alignment: .bottom, spacing: 48) {
        ForEach([2, 1, 3], id: \.self) { rank in
          if let placing = podium.first(where: { $0.rank == rank }) ?? podium[safe: rank - 1] {
            PodiumStep(placing: placing, place: rank)
          } else {
            Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
          }
        }
      }
      .frame(maxWidth: 1500)
    }
  }
}

private struct PodiumStep: View {
  let placing: Placing
  /// 1, 2 or 3: which step, whatever ties did to `placing.rank`.
  let place: Int

  var body: some View {
    let color = LeaderboardTable.medal(place) ?? .secondary
    VStack(spacing: 20) {
      if place == 1 {
        Image(systemName: "trophy.fill")
          .font(.system(size: 88))
          .foregroundStyle(Color.broadcastGold)
          .shadow(color: Color.broadcastGold.opacity(0.5), radius: 24)
      }
      Text(verbatim: placing.nickname)
        .font(.system(size: 56, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
      Text(verbatim: placing.score.grouped)
        .font(.mono(size: 38, weight: .semibold))
        .foregroundStyle(.secondary)
      Text(verbatim: ["1ST", "2ND", "3RD"][place - 1])
        .font(.mono(size: 56, weight: .heavy))
        .foregroundStyle(color)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
        .padding(.top, 28)
        .background {
          UnevenRoundedRectangle(topLeadingRadius: 24, topTrailingRadius: 24)
            .fill(LinearGradient(colors: [color.opacity(0.3), color.opacity(0.03)], startPoint: .top, endPoint: .bottom))
        }
        .overlay(alignment: .top) {
          Rectangle().fill(color.opacity(0.85)).frame(height: 4)
        }
    }
    .frame(maxWidth: .infinity)
  }

  private var height: CGFloat {
    switch place {
    case 1: 360
    case 2: 270
    default: 200
    }
  }
}

// MARK: - Parts

/// "TRIVIA//FRIDAY QUIZ" on the left, where the game is on the right.
private struct Masthead<Trailing: View>: View {
  let gameName: String
  @ViewBuilder var trailing: Trailing

  @Environment(\.accent) private var accent

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 40) {
      HStack(spacing: 0) {
        Text(verbatim: "TRIVIA")
          .foregroundStyle(accent)
        if !gameName.isEmpty {
          Text(verbatim: "//\(gameName)")
            .foregroundStyle(.secondary)
        }
      }
      .tracking(4)
      .lineLimit(1)
      .minimumScaleFactor(0.6)
      Spacer(minLength: 40)
      trailing
        .textCase(.uppercase)
    }
    .font(.mono(size: 40, weight: .heavy))
  }
}

/// "Q 03/12 · SCIENCE".
private struct QuestionNumber: View {
  let question: Question

  var body: some View {
    HStack(spacing: 16) {
      Text(verbatim: "Q \(question.qNum.twoDigits)/\(question.total.twoDigits)")
      if let category = question.category {
        Text(verbatim: "·")
          .foregroundStyle(.tertiary)
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
    HStack(spacing: 2) {
      Text(text)
      BlinkingCursor()
    }
    .font(.mono(size: 56, weight: .bold))
    .textCase(.uppercase)
    .tracking(6)
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
    Grid(horizontalSpacing: 28, verticalSpacing: 28) {
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
    let ink = state == .correct ? Color.broadcastInk : style.color
    HStack(spacing: 28) {
      HStack(spacing: 12) {
        Image(systemName: style.symbol)
          .imageScale(.small)
        Text(verbatim: style.letter)
      }
      .font(.mono(size: 44, weight: .bold))
      .foregroundStyle(ink)
      .frame(width: 110, alignment: .leading)

      Text(verbatim: text)
        .font(.system(size: 46, weight: .semibold))
        .lineLimit(2)
        .minimumScaleFactor(0.6)
        .frame(maxWidth: .infinity, alignment: .leading)

      if let votes {
        Text(votes, format: .number)
          .font(.mono(size: 52, weight: .heavy))
          .monospacedDigit()
      }
      if state == .correct {
        Image(systemName: "checkmark")
          .font(.system(size: 44, weight: .heavy))
      }
    }
    .foregroundStyle(state == .correct ? Color.broadcastInk : .primary)
    .padding(.horizontal, 36)
    .frame(maxWidth: .infinity, minHeight: 150)
    .background {
      RoundedRectangle(cornerRadius: 28)
        .fill(state == .correct ? style.color : style.color.opacity(0.12))
    }
    .overlay {
      RoundedRectangle(cornerRadius: 28)
        .strokeBorder(style.color.opacity(state == .correct ? 0 : 0.5), lineWidth: 3)
    }
    .overlay(alignment: .bottomLeading) {
      if let share, share > 0 {
        GeometryReader { proxy in
          Capsule()
            .fill(state == .correct ? Color.broadcastInk.opacity(0.35) : style.color)
            .frame(width: proxy.size.width * share, height: 10)
        }
        .frame(height: 10)
        .padding(.horizontal, 36)
        .padding(.bottom, 16)
      }
    }
    .opacity(state == .wrong ? 0.4 : 1)
  }
}
