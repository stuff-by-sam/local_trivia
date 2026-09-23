import Foundation
import Observation
import OSLog
import UIKit

/// Runs a game from this phone, with the host playing in it.
///
/// It owns the round (`library`), and while hosting, the engine (`game`) and
/// the server that carries it (`HostServer`). The host plays like anyone else:
/// their `GameStore` joins this server over loopback, so the host's player
/// screens are exactly everyone else's. The host's controls act on the engine
/// directly — they never cross the network, so nothing on the Wi-Fi can reach
/// them.
@Observable
final class HostController {
  enum Status: Equatable {
    case idle
    case starting
    case live(port: UInt16)
    /// Saying goodbye to every phone; a new game can start once it's done.
    case stopping
    case failed(String)
  }

  /// The one thing to do next, for the host's action bar.
  enum Action: Equatable {
    case start, showStandings, nextQuestion, finish, newGame
  }

  /// A sheet opened from the host's menu (see `HostSheetView`).
  enum Sheet: String, Identifiable {
    case players, joinCode, tv, round
    var id: String { rawValue }
  }

  let library: HostLibrary
  private(set) var status: Status = .idle
  private(set) var game: HostedGame?
  /// What the game is advertised as. Fixed when hosting starts: it's the name
  /// other phones list it under, so editing the round can't change it.
  private(set) var gameName = ""
  /// Where other phones reach this one; nil with no Wi-Fi or hotspot.
  private(set) var lanAddress: String?
  private(set) var actionError: String?
  var sheet: Sheet?

  var isHosting: Bool {
    if case .live = status { true } else { false }
  }

  /// Free to start a game: nothing running, starting or winding down.
  var canStart: Bool {
    switch status {
    case .idle, .failed: true
    case .starting, .live, .stopping: false
    }
  }

  @ObservationIgnored private var server: HostServer?
  @ObservationIgnored private var outbox: AsyncStream<(String, Recipients)>.Continuation?
  @ObservationIgnored private var pump: Task<Void, Never>?
  @ObservationIgnored private var sender: Task<Void, Never>?
  /// The host's own player, seated in this game like everyone else.
  @ObservationIgnored private weak var seat: GameStore?
  @ObservationIgnored private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  @ObservationIgnored private let encoder = JSONEncoder()
  @ObservationIgnored private let decoder = JSONDecoder()

  private enum Recipients: Sendable {
    case connections([HostServer.ConnectionID])
    case everyone
  }

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "hosting")

  /// `advertises: false` keeps the game off Bonjour (tests).
  @ObservationIgnored private let advertises: Bool

  init(library: HostLibrary = HostLibrary(), advertises: Bool = true) {
    self.library = library
    self.advertises = advertises
  }

  // MARK: - Hosting

  /// Opens the game on the network and seats the host in it.
  func start(joining store: GameStore) async {
    guard canStart else { return }
    status = .starting
    actionError = nil
    lanAddress = LocalAddress.current()
    gameName = library.advertisedName

    let server = HostServer()
    let port: UInt16
    do {
      port = try await server.start(name: gameName, lanAddress: lanAddress, advertises: advertises)
    } catch {
      status = .failed(Self.describe(error))
      return
    }
    self.server = server

    let (outgoing, outbox) = AsyncStream.makeStream(of: (String, Recipients).self)
    self.outbox = outbox
    sender = Task {
      for await (text, recipients) in outgoing {
        switch recipients {
        case .connections(let ids): await server.send(text, to: ids)
        case .everyone: await server.sendToAll(text)
        }
      }
    }

    let game = HostedGame(deliver: { [weak self] event, audience in self?.deliver(event, to: audience) })
    self.game = game

    pump = Task { [weak self] in
      for await event in server.events {
        guard let self else { return }
        self.handle(event)
      }
    }

    status = .live(port: port)
    seat = store
    // The host plays too: join our own game like any other phone would.
    if let seat = GameServer(address: "127.0.0.1:\(port)", name: gameName) {
      store.join(seat, pin: game.pin)
    }
  }

  /// Ends the game for everyone and closes the server.
  func stop(leaving store: GameStore) async {
    guard isHosting, let server else { return }
    let advertised = joinLink?.server.url
    status = .stopping
    game?.close()
    store.forgetGame(endedAt: advertised)
    // Let the goodbyes go out before the connections close.
    outbox?.finish()
    await sender?.value
    await server.stop()
    pump?.cancel()
    self.server = nil
    game = nil
    seat = nil
    sheet = nil
    status = .idle
    endBackgroundTask()
  }

  /// What other phones scan or follow to join.
  var joinLink: JoinLink? {
    guard case .live(let port) = status, let lanAddress, let game,
      let server = GameServer(address: "\(lanAddress):\(port)", name: gameName)
    else { return nil }
    return JoinLink(server: server, pin: game.pin)
  }

  // MARK: - Controls

  var nextAction: Action? {
    guard let game else { return nil }
    switch game.state {
    case .lobby: return .start
    case .questionActive: return nil
    case .reveal: return .showStandings
    case .leaderboard: return game.isLastQuestion ? .finish : .nextQuestion
    case .podium: return .newGame
    }
  }

  func perform(_ action: Action) {
    guard let game else { return }
    actionError = nil
    switch action {
    case .start:
      do throws(HostedGame.StartProblem) {
        try game.start(questions: library.playable, rules: library.rules)
      } catch {
        switch error {
        case .noQuestions: actionError = String(localized: "Add a question to the round first.")
        case .noPlayers: actionError = String(localized: "Nobody's in the game yet.")
        }
      }
    case .showStandings: game.showLeaderboard()
    case .nextQuestion, .finish: game.next()
    case .newGame: game.newGame()
    }
  }

  func endRound() { game?.endRound() }
  func skipQuestion() { game?.skip() }
  func endGame() { game?.endGame() }
  func kick(_ player: HostedGame.Player) { game?.kick(token: player.token) }

  /// The host's own seat — known by its token, not guessed from the network.
  func isHost(_ player: HostedGame.Player) -> Bool {
    guard let token = seat?.sessionToken else { return false }
    return player.token == token
  }

  // MARK: - Lifecycle

  /// iOS suspends a backgrounded app, and a suspended host is a game that
  /// stops. Ask for time on the way out so a quick app switch doesn't end it,
  /// and re-open the listener on the way back if it was torn down.
  func appDidEnterBackground() {
    guard isHosting, backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Hosting a game") { [weak self] in
      self?.endBackgroundTask()
    }
  }

  func appDidBecomeActive() {
    endBackgroundTask()
    guard isHosting, let server else { return }
    // Wi-Fi or Personal Hotspot may have come up while the app was away —
    // often because the join card asked for it.
    lanAddress = LocalAddress.current()
    Task { [lanAddress] in await server.ensureListening(lanAddress: lanAddress) }
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  // MARK: - Wire

  private func handle(_ event: HostServer.Event) {
    guard let game else { return }
    switch event {
    case .attached(let id, let peer):
      game.attach(id, from: peer)
    case .message(let id, let json):
      // Whatever arrives is untrusted: malformed or unknown events are dropped.
      guard let event = try? decoder.decode(ClientEvent.self, from: json) else { return }
      game.receive(event, from: id)
    case .detached(let id):
      game.detach(id)
    case .listenerStopped:
      if let server { Task { await server.ensureListening(lanAddress: lanAddress) } }
    }
  }

  /// Engine → wire. Recipients are resolved now, in order, and sent by one
  /// task, so every phone sees events in the order the game produced them.
  private func deliver(_ event: ServerEvent, to audience: HostedGame.Audience) {
    guard let json = try? encoder.encode(event) else { return }
    let text = Wire.event(json: json)
    switch audience {
    case .connection(let id): outbox?.yield((text, .connections([id])))
    case .players: outbox?.yield((text, .connections(game?.connectedPlayers.compactMap(\.connection) ?? [])))
    case .everyone: outbox?.yield((text, .everyone))
    }
  }

  private static func describe(_ error: HostServer.StartError) -> String {
    switch error {
    case .noFreePort: String(localized: "Couldn't find a free port to host on.")
    case .listenerFailed(let reason): String(localized: "Couldn't start hosting: \(reason)")
    }
  }
}
