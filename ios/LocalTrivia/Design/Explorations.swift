#if DEBUG
import DesignSystem
import SwiftUI

// Three directions for the key screens — join, a question, the host's lobby —
// drawn from mock data so they can be compared side by side. Direction A,
// Broadcast, is the one the app is built in; see ios/DESIGN.md for why.
//
// Debug builds only. Launch with `-explore <direction>.<screen>` (for
// example `-explore b.question`) to see one full screen in the simulator.

enum Direction: String, CaseIterable {
  /// The broadcast terminal, disciplined: system chrome, the game's voice in content.
  case broadcast = "a"
  /// System-native and quiet: SF Pro, grouped surfaces, no texture.
  case studio = "b"
  /// A game show: filled answer tiles, rounded type, colour everywhere.
  case gameShow = "c"

  var name: String {
    switch self {
    case .broadcast: "A · Broadcast"
    case .studio: "B · Studio"
    case .gameShow: "C · Game Show"
    }
  }
}

enum ExploredScreen: String, CaseIterable {
  case join, question, lobby
}

private enum Mock {
  static let question = "Which planet has the most moons?"
  static let answers = ["Saturn", "Jupiter", "Uranus", "Neptune"]
  static let players = ["ROBIN", "SAM", "ALEX", "JORDAN", "PRIYA", "MO"]
  static let pin = "4821"
  static let window = Date.now...Date.now.addingTimeInterval(14)
}

/// One direction's version of one screen.
struct ExplorationScreen: View {
  let direction: Direction
  let screen: ExploredScreen

  var body: some View {
    switch (direction, screen) {
    case (.broadcast, .join): BroadcastJoin()
    case (.broadcast, .question): BroadcastQuestion()
    case (.broadcast, .lobby): BroadcastLobby()
    case (.studio, .join): StudioJoin()
    case (.studio, .question): StudioQuestion()
    case (.studio, .lobby): StudioLobby()
    case (.gameShow, .join): GameShowJoin()
    case (.gameShow, .question): GameShowQuestion()
    case (.gameShow, .lobby): GameShowLobby()
    }
  }

  /// `-explore b.question` → that screen; nil when not exploring.
  static func fromLaunchArguments() -> ExplorationScreen? {
    guard let value = UserDefaults.standard.string(forKey: "explore") else { return nil }
    let parts = value.lowercased().split(separator: ".").map(String.init)
    guard parts.count == 2, let direction = Direction(rawValue: parts[0]), let screen = ExploredScreen(rawValue: parts[1])
    else { return nil }
    return ExplorationScreen(direction: direction, screen: screen)
  }
}

// MARK: - A · Broadcast

private struct BroadcastJoin: View {
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 28) {
          VStack(spacing: 14) {
            HStack(spacing: 14) {
              ForEach(AnswerStyle.allCases) { Image(systemName: $0.symbol).foregroundStyle($0.color) }
            }
            .font(.body)
            Text(verbatim: "TRIVIA")
              .font(.system(size: 46, weight: .heavy, design: .monospaced))
              .tracking(6)
              .foregroundStyle(Theme.phosphor.accent)
              .shadow(color: Theme.phosphor.accent.opacity(0.45), radius: 14)
          }
          .padding(.top, 12)

          VStack(alignment: .leading, spacing: 8) {
            Text("Game").textRole(.label).foregroundStyle(.secondary)
            HStack(spacing: 14) {
              StatusDot(.online)
              VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: "FRIDAY QUIZ").font(.headline)
                Text(verbatim: "192.168.1.20 · ONLINE").font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
              }
              Spacer()
              Image(systemName: "chevron.up.chevron.down").foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 64)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("PIN").textRole(.label).foregroundStyle(.secondary)
            HStack(spacing: 8) {
              ForEach(0..<4, id: \.self) { index in
                Text(verbatim: index < 2 ? String(Array(Mock.pin)[index]) : index == 2 ? "_" : " ")
                  .font(.system(size: 34, weight: .bold, design: .monospaced))
                  .foregroundStyle(index == 2 ? Theme.phosphor.accent : .primary)
                  .frame(maxWidth: .infinity, minHeight: 72)
                  .glassEffect(in: .rect(cornerRadius: 20))
              }
            }
            Text("The PIN is on the host's phone").textRole(.label).foregroundStyle(.secondary)
          }

          VStack(alignment: .leading, spacing: 8) {
            Text("Nickname").textRole(.label).foregroundStyle(.secondary)
            HStack(spacing: 12) {
              Text(verbatim: ">").font(.system(.title3, design: .monospaced, weight: .bold)).foregroundStyle(Theme.phosphor.accent)
              Text(verbatim: "robin").font(.system(.title3, design: .monospaced, weight: .semibold))
              Spacer()
            }
            .padding(.horizontal, 16)
            .frame(minHeight: 56)
            .glassEffect(in: .rect(cornerRadius: 20))
          }
        }
        .padding(.horizontal, 16)
      }
      .safeAreaBar(edge: .bottom) {
        VStack(spacing: 8) {
          Button {} label: {
            Label("Join Game", systemImage: "arrow.forward").frame(maxWidth: .infinity)
          }
          .buttonStyle(.glassProminent)
          Button {} label: {
            Label("Host a Game", systemImage: "antenna.radiowaves.left.and.right").frame(maxWidth: .infinity)
          }
          .buttonStyle(.glass)
        }
        .controlSize(.large)
        .textRole(.action)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
      }
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Themes & Icons", systemImage: "paintpalette") {}
        }
      }
      .containerBackground(for: .navigation) { Backdrop(mood: .idle) }
    }
    .tint(Theme.phosphor.accent)
  }
}

private struct BroadcastQuestion: View {
  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        ProgressView(timerInterval: Mock.window, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
        Spacer()
        Text(verbatim: Mock.question)
          .font(.largeTitle.bold())
          .multilineTextAlignment(.center)
        Spacer()
        VStack(spacing: 8) {
          ForEach(AnswerStyle.allCases) { style in
            HStack(spacing: 14) {
              AnswerKey(style: style, isInverted: style == .b)
              Text(verbatim: Mock.answers[style.rawValue]).font(.title3.weight(style == .b ? .bold : .semibold))
              Spacer()
              if style == .b { Image(systemName: "checkmark").fontWeight(.bold) }
            }
            .foregroundStyle(style == .b ? Palette.onAccentInk : .primary)
            .padding(.horizontal, 14)
            .frame(minHeight: 60)
            .glassEffect(.regular.tint(style.color.opacity(style == .b ? 0.8 : 0.09)), in: .rect(cornerRadius: 20))
            .opacity(style == .b ? 1 : 0.4)
          }
        }
        StatusLine("Locked in · 3 of 6 answered")
      }
      .padding(.horizontal, 16)
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Text(verbatim: "Q 03/12 · SCIENCE").font(.system(.footnote, design: .monospaced, weight: .semibold)).fixedSize()
        }
        ToolbarItem(placement: .topBarTrailing) {
          Label { Text(timerInterval: Mock.window, countsDown: true) } icon: { Image(systemName: "timer") }
            .labelStyle(.titleAndIcon)
            .font(.system(.footnote, design: .monospaced, weight: .semibold))
            .monospacedDigit()
        }
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
        ToolbarItem(placement: .topBarTrailing) {
          Button("Host controls", systemImage: "slider.horizontal.3") {}
        }
      }
      .containerBackground(for: .navigation) { Backdrop(mood: .question) }
    }
    .tint(Theme.phosphor.accent)
  }
}

private struct BroadcastLobby: View {
  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 24) {
          HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
              Text("Join code").textRole(.label).foregroundStyle(.secondary)
              Text(verbatim: Mock.pin)
                .font(.system(size: 64, weight: .heavy, design: .monospaced))
                .tracking(8)
                .foregroundStyle(Theme.phosphor.accent)
                .shadow(color: Theme.phosphor.accent.opacity(0.4), radius: 12)
              Text("Scan, or find FRIDAY QUIZ in the app").textRole(.labelSmall).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            RoundedRectangle(cornerRadius: 12).fill(.white).frame(width: 112, height: 112)
              .overlay { Image(systemName: "qrcode").font(.system(size: 88)).foregroundStyle(.black) }
          }
          .padding(16)
          .background(.white.opacity(0.04), in: .rect(cornerRadius: 24))
          .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(0.14)) }

          VStack(alignment: .leading, spacing: 10) {
            Text("In the game · \(Mock.players.count)").textRole(.label).foregroundStyle(.secondary)
            FlowChips(names: Mock.players)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
      }
      .safeAreaBar(edge: .bottom) {
        Button {} label: { Label("Start Game", systemImage: "play.fill").frame(maxWidth: .infinity) }
          .buttonStyle(.glassProminent)
          .controlSize(.large)
          .textRole(.action)
          .padding(.horizontal, 16)
          .padding(.bottom, 8)
      }
      .toolbar {
        ToolbarItem(placement: .topBarLeading) {
          Text(verbatim: "FRIDAY QUIZ").font(.system(.footnote, design: .monospaced, weight: .semibold)).fixedSize()
        }
        ToolbarItem(placement: .topBarTrailing) {
          Button("Host controls", systemImage: "slider.horizontal.3") {}
        }
      }
      .containerBackground(for: .navigation) { Backdrop(mood: .idle) }
    }
    .tint(Theme.phosphor.accent)
  }
}

private struct FlowChips: View {
  let names: [String]
  var body: some View {
    HStack(spacing: 8) {
      ForEach(names.prefix(4), id: \.self) { name in
        Text(verbatim: name).font(.system(.subheadline, design: .monospaced, weight: .semibold))
          .padding(.horizontal, 12).frame(minHeight: 36)
          .background(.white.opacity(0.08), in: .capsule)
      }
      Text(verbatim: "+\(names.count - 4)").font(.system(.subheadline, design: .monospaced)).foregroundStyle(.secondary)
    }
  }
}

// MARK: - B · Studio

private struct StudioJoin: View {
  var body: some View {
    NavigationStack {
      Form {
        Section("Game") {
          LabeledContent("Friday Quiz") { Text("Online").foregroundStyle(.green) }
        }
        Section {
          Text(verbatim: "48 _ _").font(.largeTitle.weight(.semibold).monospacedDigit())
        } header: { Text("PIN") } footer: { Text("The PIN is on the host's phone.") }
        Section("Nickname") { Text(verbatim: "Robin") }
      }
      .navigationTitle("Trivia")
      .safeAreaBar(edge: .bottom) {
        VStack(spacing: 8) {
          Button {} label: { Text("Join Game").frame(maxWidth: .infinity) }.buttonStyle(.glassProminent)
          Button {} label: { Text("Host a Game").frame(maxWidth: .infinity) }.buttonStyle(.glass)
        }
        .controlSize(.large).padding(.horizontal, 16).padding(.bottom, 8)
      }
      .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Themes", systemImage: "paintpalette") {} } }
    }
    .tint(.blue)
  }
}

private struct StudioQuestion: View {
  var body: some View {
    NavigationStack {
      VStack(spacing: 16) {
        ProgressView(timerInterval: Mock.window, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
        Spacer()
        Text(verbatim: Mock.question).font(.largeTitle.bold()).multilineTextAlignment(.center)
        Spacer()
        ForEach(AnswerStyle.allCases) { style in
          Button {} label: {
            HStack {
              Image(systemName: style.symbol).foregroundStyle(style.color)
              Text(verbatim: Mock.answers[style.rawValue])
              Spacer()
            }
            .font(.title3)
            .frame(maxWidth: .infinity, minHeight: 44)
          }
          .buttonStyle(.glass)
        }
        Text("3 of 6 answered").font(.footnote).foregroundStyle(.secondary)
      }
      .padding(.horizontal, 16)
      .navigationTitle("Question 3 of 12")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { Text(timerInterval: Mock.window, countsDown: true).monospacedDigit() }
      }
    }
  }
}

private struct StudioLobby: View {
  var body: some View {
    NavigationStack {
      List {
        Section {
          VStack(spacing: 4) {
            Text("Join Code").font(.subheadline).foregroundStyle(.secondary)
            Text(verbatim: Mock.pin).font(.system(size: 64, weight: .bold).monospacedDigit())
          }
          .frame(maxWidth: .infinity)
        }
        Section("Players") { ForEach(Mock.players, id: \.self) { Text($0.capitalized) } }
      }
      .navigationTitle("Friday Quiz")
      .safeAreaBar(edge: .bottom) {
        Button {} label: { Text("Start Game").frame(maxWidth: .infinity) }
          .buttonStyle(.glassProminent).controlSize(.large).padding(.horizontal, 16).padding(.bottom, 8)
      }
    }
    .tint(.blue)
  }
}

// MARK: - C · Game Show

private struct GameShowBackground: View {
  var body: some View {
    ZStack {
      LinearGradient(colors: [Color(hex: 0x2A0B5E), Color(hex: 0x0B0620)], startPoint: .top, endPoint: .bottom)
      Circle().fill(Color(hex: 0xFF6AD5).opacity(0.35)).frame(width: 360).blur(radius: 90).offset(x: -120, y: -260)
      Circle().fill(Color(hex: 0x55E6FF).opacity(0.3)).frame(width: 320).blur(radius: 90).offset(x: 140, y: 260)
    }
    .ignoresSafeArea()
  }
}

private struct GameShowJoin: View {
  var body: some View {
    ZStack {
      GameShowBackground()
      VStack(spacing: 24) {
        Text(verbatim: "TRIVIA!").font(.system(size: 56, weight: .black, design: .rounded))
        HStack(spacing: 10) {
          ForEach(0..<4, id: \.self) { index in
            Text(verbatim: index < 2 ? String(Array(Mock.pin)[index]) : "")
              .font(.system(size: 40, weight: .black, design: .rounded))
              .frame(maxWidth: .infinity, minHeight: 84)
              .background(.white.opacity(0.14), in: .rect(cornerRadius: 22))
          }
        }
        Text(verbatim: "Robin").font(.system(.title2, design: .rounded).weight(.bold))
          .frame(maxWidth: .infinity, minHeight: 60).background(.white.opacity(0.14), in: .capsule)
        Spacer()
        Text("Let's Go!").font(.system(.title2, design: .rounded).weight(.black))
          .foregroundStyle(Color(hex: 0x2A0B5E))
          .frame(maxWidth: .infinity, minHeight: 64).background(Color(hex: 0xFFB347), in: .capsule)
      }
      .padding(20)
    }
  }
}

private struct GameShowQuestion: View {
  var body: some View {
    ZStack {
      GameShowBackground()
      VStack(spacing: 16) {
        HStack {
          Text(verbatim: "3/12").font(.system(.headline, design: .rounded).weight(.heavy))
          Spacer()
          Text(timerInterval: Mock.window, countsDown: true).font(.system(.title, design: .rounded).weight(.black)).monospacedDigit()
        }
        Text(verbatim: Mock.question)
          .font(.system(.title, design: .rounded).weight(.heavy))
          .multilineTextAlignment(.center)
          .padding(20)
          .frame(maxWidth: .infinity)
          .background(.white.opacity(0.12), in: .rect(cornerRadius: 28))
        Spacer()
        Grid(horizontalSpacing: 10, verticalSpacing: 10) {
          ForEach([0, 2], id: \.self) { row in
            GridRow {
              ForEach(AnswerStyle.allCases[row..<row + 2]) { style in
                VStack(spacing: 10) {
                  Image(systemName: style.symbol).font(.system(size: 34))
                  Text(verbatim: Mock.answers[style.rawValue]).font(.system(.title3, design: .rounded).weight(.heavy))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 150)
                .background(style.color, in: .rect(cornerRadius: 26))
              }
            }
          }
        }
      }
      .padding(20)
    }
  }
}

private struct GameShowLobby: View {
  var body: some View {
    ZStack {
      GameShowBackground()
      VStack(spacing: 24) {
        VStack(spacing: 6) {
          Text("Game PIN").font(.system(.headline, design: .rounded).weight(.bold))
          Text(verbatim: Mock.pin).font(.system(size: 80, weight: .black, design: .rounded))
        }
        .frame(maxWidth: .infinity).padding(.vertical, 24)
        .background(.white.opacity(0.12), in: .rect(cornerRadius: 32))
        HStack(spacing: 8) {
          ForEach(Array(Mock.players.prefix(4).enumerated()), id: \.offset) { index, name in
            Text(verbatim: name.capitalized).font(.system(.subheadline, design: .rounded).weight(.heavy))
              .padding(.horizontal, 14).frame(minHeight: 40)
              .background(AnswerStyle.allCases[index].color.opacity(0.85), in: .capsule)
          }
        }
        Spacer()
        Text("Start!").font(.system(.title2, design: .rounded).weight(.black))
          .foregroundStyle(Color(hex: 0x2A0B5E))
          .frame(maxWidth: .infinity, minHeight: 64).background(Color(hex: 0x56FF8A), in: .capsule)
      }
      .padding(20)
    }
  }
}

// MARK: - Motion tuning

/// A temporary panel for tuning the signature motion — the chosen answer's
/// glass flowing into the verdict — on a device, by feel. Launch with
/// `-explore tune.motion`; copy the values it prints into `Motion`.
struct MotionTuner: View {
  static var isRequested: Bool { UserDefaults.standard.string(forKey: "explore") == "tune.motion" }

  @Namespace private var glass
  @State private var isRevealed = false
  @State private var morphDuration = 0.5
  @State private var morphBounce = 0.0
  @State private var popDuration = 0.35
  @State private var popBounce = 0.45

  var body: some View {
    NavigationStack {
      VStack(spacing: Space.xl) {
        GlassEffectContainer(spacing: Space.xs) {
          ZStack {
            if isRevealed {
              Badge(symbol: "checkmark", color: Palette.success, isGlass: true)
                .glassEffectID("answer", in: glass)
                .transition(.scale(scale: 0.6).combined(with: .opacity).animation(.spring(duration: popDuration, bounce: popBounce)))
            } else {
              AnswerButton(style: .b, text: "Jupiter", longestOption: 7, state: .chosen) {}
                .glassEffectID("answer", in: glass)
            }
          }
          .frame(maxWidth: .infinity, minHeight: Size.qrFull)
        }

        VStack(spacing: Space.m) {
          tuning("Morph duration", value: $morphDuration, in: 0.2...1.2)
          tuning("Morph bounce", value: $morphBounce, in: 0...0.6)
          tuning("Pop duration", value: $popDuration, in: 0.15...0.8)
          tuning("Pop bounce", value: $popBounce, in: 0...0.7)
        }
        .panel()

        VStack(alignment: .leading, spacing: Space.xs) {
          Text(verbatim: "Motion.screen = .spring(duration: \(morphDuration.formatted(.number.precision(.fractionLength(2)))), bounce: \(morphBounce.formatted(.number.precision(.fractionLength(2)))))")
          Text(verbatim: "Motion.pop = .spring(duration: \(popDuration.formatted(.number.precision(.fractionLength(2)))), bounce: \(popBounce.formatted(.number.precision(.fractionLength(2)))))")
        }
        .textRole(.figureSmall)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)

        Spacer()
      }
      .padding(Space.l)
      .safeAreaBar(edge: .bottom) {
        ActionBar {
          ActionButton(isRevealed ? "Back to the Answer" : "Reveal", systemImage: "play.fill") {
            withAnimation(.spring(duration: morphDuration, bounce: morphBounce)) { isRevealed.toggle() }
          }
        }
      }
      .navigationTitle("Tune Motion")
      .navigationBarTitleDisplayMode(.inline)
      .containerBackground(for: .navigation) { Backdrop(mood: isRevealed ? .correct : .question) }
    }
  }

  private func tuning(_ name: String, value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
    VStack(alignment: .leading, spacing: Space.xs) {
      HStack {
        Text(verbatim: name).textRole(.label).foregroundStyle(.secondary)
        Spacer()
        Text(verbatim: value.wrappedValue.formatted(.number.precision(.fractionLength(2)))).textRole(.figure)
      }
      Slider(value: value, in: range)
    }
    .padding(.horizontal, Space.l)
    .padding(.vertical, Space.s)
  }
}

// MARK: - Previews

#Preview("Motion tuner") { MotionTuner() }

#Preview("A · Broadcast — Join") { ExplorationScreen(direction: .broadcast, screen: .join) }
#Preview("A · Broadcast — Question") { ExplorationScreen(direction: .broadcast, screen: .question) }
#Preview("A · Broadcast — Lobby") { ExplorationScreen(direction: .broadcast, screen: .lobby) }
#Preview("B · Studio — Join") { ExplorationScreen(direction: .studio, screen: .join) }
#Preview("B · Studio — Question") { ExplorationScreen(direction: .studio, screen: .question) }
#Preview("B · Studio — Lobby") { ExplorationScreen(direction: .studio, screen: .lobby) }
#Preview("C · Game Show — Join") { ExplorationScreen(direction: .gameShow, screen: .join) }
#Preview("C · Game Show — Question") { ExplorationScreen(direction: .gameShow, screen: .question) }
#Preview("C · Game Show — Lobby") { ExplorationScreen(direction: .gameShow, screen: .lobby) }
#endif
