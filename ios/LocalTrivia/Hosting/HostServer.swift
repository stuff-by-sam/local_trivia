import Foundation
import Network
import OSLog
import Synchronization

/// The game server a phone-hosted game runs: Socket.IO over WebSocket on the
/// local network — the same wire as the laptop server, so the Node test bots
/// work unchanged — advertised over Bonjour as `GameBrowser.serviceType`,
/// which only phones advertise.
///
/// The same port serves the web player (`WebPlayer`) over plain HTTP, so the
/// join link in the host's QR code works in any phone's browser: a request
/// that asks to upgrade becomes a game connection, and any other gets a file
/// and a closed connection (`HTTP.swift` has the framing).
///
/// It only moves frames. What they mean is `HostedGame`'s business, and the
/// host's controls never travel over the network at all: there is no admin
/// surface here to reach.
actor HostServer {
  typealias ConnectionID = Int

  enum Event: Sendable {
    /// Joined the Socket.IO namespace. `peer` is the phone's address, which
    /// outlives any one connection.
    case attached(ConnectionID, peer: String)
    case message(ConnectionID, Data)
    case detached(ConnectionID)
    /// The listener stopped accepting (typically after a long suspension).
    case listenerStopped
  }

  enum StartError: Error, Equatable {
    case noFreePort
    case listenerFailed(String)
  }

  // Engine.IO timing, as socket.io's defaults.
  static let pingInterval = 25_000
  static let pingTimeout = 20_000
  /// Frames are small JSON; anything bigger is refused, not buffered.
  static let maxMessageBytes = 64 * 1024
  static let ports: [UInt16] = Array(3000...3019)
  /// How long a connection has to finish its request: a phone that opens
  /// one and says nothing doesn't get to hold it.
  static let requestTimeout: Duration = .seconds(10)

  nonisolated let events: AsyncStream<Event>
  private let continuation: AsyncStream<Event>.Continuation
  private let queue = DispatchQueue(label: "com.stuffbysam.localtrivia.host-server")
  private var listener: NWListener?
  private var links: [ConnectionID: Link] = [:]
  private var nextID = 0
  private(set) var port: UInt16?
  private var serviceName = ""
  private var advertises = true
  private var lanAddress: String?
  /// What the web player is served wearing: the host's accent (`WebPlayer`).
  private var webAccent: String?
  /// Stopped for good. A server is used once: nothing brings it back, so a
  /// game that's over can't linger on the network.
  private var isStopped = false

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "host-server")

  private final class Link {
    let connection: NWConnection
    let sid: String
    let peer: String
    /// A game connection, not a page being fetched.
    var isUpgraded = false
    var isAttached = false
    var lastHeard = ContinuousClock.now
    var pump: Task<Void, Never>?
    var heartbeat: Task<Void, Never>?

    init(connection: NWConnection, sid: String, peer: String) {
      self.connection = connection
      self.sid = sid
      self.peer = peer
    }
  }

  private enum Frame: Sendable {
    /// Upgraded to a WebSocket: a game connection.
    case ready
    case text(String)
    case closed
  }

  init() {
    (events, continuation) = AsyncStream.makeStream()
  }

  // MARK: - Listening

  /// Listens on the first free port from 3000 and advertises `name` with the
  /// join URL other phones should dial. Returns the port.
  func start(name: String, lanAddress: String?, advertises: Bool = true) async throws(StartError) -> UInt16 {
    serviceName = name
    self.advertises = advertises
    self.lanAddress = lanAddress
    for candidate in Self.ports {
      do {
        try await listen(on: candidate)
        port = candidate
        return candidate
      } catch let error as NWError where error == .posix(.EADDRINUSE) {
        continue
      } catch {
        throw .listenerFailed(error.localizedDescription)
      }
    }
    throw .noFreePort
  }

  /// Taking connections, and advertising the game if it advertises.
  var isListening: Bool { listener != nil }

  /// Dresses the web player in the host's theme from the next page served.
  func setWebAccent(_ accent: String?) {
    webAccent = accent
  }

  /// After a long suspension the listener may be gone; bring it back on the
  /// same port so every player's saved address still works. And if the
  /// phone's own address has changed — Wi-Fi or Personal Hotspot came up
  /// after hosting started, say — advertise the new one, or no other phone
  /// can find the game.
  func ensureListening(lanAddress: String?) async {
    guard !isStopped, let port else { return }
    let hasMoved = lanAddress != self.lanAddress
    self.lanAddress = lanAddress
    if listener?.state != .ready {
      listener?.cancel()
      try? await listen(on: port)
    } else if hasMoved {
      listener?.service = service(port: port)
    }
  }

  private func listen(on port: UInt16) async throws {
    let tcp = NWProtocolTCP.Options()
    // Frames are small and a tapped answer is timed: send each at once.
    tcp.noDelay = true
    let parameters = NWParameters(tls: nil, tcp: tcp)
    parameters.includePeerToPeer = false

    guard let endpointPort = NWEndpoint.Port(rawValue: port) else { throw StartError.noFreePort }
    let listener = try NWListener(using: parameters, on: endpointPort)
    listener.service = service(port: port)
    listener.newConnectionHandler = { [weak self] connection in
      Task { await self?.accept(connection) }
    }

    let outcome = Once<Result<Void, NWError>>()
    try await withCheckedThrowingContinuation { (waiter: CheckedContinuation<Void, any Error>) in
      outcome.onFirst { waiter.resume(with: $0) }
      listener.stateUpdateHandler = { [weak self] state in
        switch state {
        case .ready:
          outcome.fire(.success(()))
        case .failed(let error), .waiting(let error):
          if !outcome.fire(.failure(error)) {
            // Failed after it had been running.
            Task { await self?.listenerDied() }
          }
          listener.cancel()
        default:
          break
        }
      }
      listener.start(queue: queue)
    }
    // Stopped while this one was starting up (the actor took other calls
    // while it waited): it mustn't outlive the stop.
    guard !isStopped else {
      listener.cancel()
      throw CancellationError()
    }
    self.listener = listener
  }

  /// The Bonjour advert: the game's name, and the URL other phones dial.
  private func service(port: UInt16) -> NWListener.Service? {
    guard advertises else { return nil }
    var txt: [String: String] = ["v": "1"]
    if let lanAddress { txt["url"] = "http://\(lanAddress):\(port)" }
    return NWListener.Service(name: serviceName, type: GameBrowser.serviceType, txtRecord: NWTXTRecord(txt))
  }

  private func listenerDied() {
    Self.log.notice("listener stopped")
    continuation.yield(.listenerStopped)
  }

  /// Tells every connection the game is over, then closes up — once the
  /// goodbyes are out. Cancelling a connection can drop what's still queued
  /// on it, and a player who misses the goodbye waits on a game that's gone.
  func stop() async {
    isStopped = true
    listener?.cancel()
    listener = nil
    let closing = Array(links.values)
    for link in closing {
      link.pump?.cancel()
      link.heartbeat?.cancel()
    }
    links = [:]
    // Frames go out in order, so once the close is taken, so is everything before it.
    await withTaskGroup(of: Void.self) { group in
      for link in closing where link.isUpgraded {
        group.addTask { [connection = link.connection] in
          Self.write(Wire.disconnect, on: connection)
          await Self.flush(WebSocketFrame.close(WebSocketFrame.goingAway), on: connection)
        }
      }
    }
    for link in closing { link.connection.cancel() }
    continuation.finish()
  }

  // MARK: - Connections

  private func accept(_ connection: NWConnection) {
    // One that arrived as the server stopped.
    guard !isStopped else {
      connection.cancel()
      return
    }
    // Local network only: the same rule the app applies when joining.
    guard case .hostPort(let host, _) = connection.endpoint, Self.isLocal(host) else {
      Self.log.notice("refused a connection from beyond the local network")
      connection.cancel()
      return
    }

    let id = nextID
    nextID += 1
    let link = Link(connection: connection, sid: HostedGame.randomToken(), peer: "\(host)")
    links[id] = link

    let (frames, sink) = AsyncStream.makeStream(of: Frame.self)
    // `.ready` comes from the handshake (`readRequest`), not from TCP.
    connection.stateUpdateHandler = { state in
      switch state {
      case .failed, .cancelled:
        sink.yield(.closed)
        sink.finish()
      default: break
      }
    }
    link.pump = Task { await self.pump(id, frames) }
    link.heartbeat = Task {
      try? await Task.sleep(for: Self.requestTimeout)
      guard !Task.isCancelled else { return }
      self.closeIfIdle(id)
    }
    connection.start(queue: queue)
    Self.readRequest(on: connection, accent: webAccent, into: sink)
  }

  /// One task per connection, draining its frames in order.
  private func pump(_ id: ConnectionID, _ frames: AsyncStream<Frame>) async {
    for await frame in frames {
      guard let link = links[id] else { break }
      switch frame {
      case .ready:
        link.isUpgraded = true
        link.lastHeard = .now
        Self.write(
          Wire.open(sid: link.sid, pingInterval: Self.pingInterval, pingTimeout: Self.pingTimeout, maxPayload: Self.maxMessageBytes),
          on: link.connection)
        link.heartbeat?.cancel()
        link.heartbeat = Task { await self.heartbeat(id) }
      case .text(let text):
        link.lastHeard = .now
        handle(text, from: id, link: link)
      case .closed:
        drop(id)
        return
      }
    }
    drop(id)
  }

  private func handle(_ text: String, from id: ConnectionID, link: Link) {
    guard let frame = try? Wire.decode(text) else { return }
    switch frame {
    case .connected:
      guard !link.isAttached else { return }
      link.isAttached = true
      Self.write(Wire.connectAck(sid: link.sid), on: link.connection)
      continuation.yield(.attached(id, peer: link.peer))
    case .event(let json):
      guard link.isAttached else { return }
      continuation.yield(.message(id, json))
    case .ping:
      Self.write(Wire.pong, on: link.connection)
    case .close, .disconnected:
      close(id)
    case .open, .pong, .noop, .connectError, .unsupported:
      break
    }
  }

  private func closeIfIdle(_ id: ConnectionID) {
    guard let link = links[id], !link.isUpgraded else { return }
    close(id)
  }

  /// The server pings; a client that goes quiet past interval + timeout is gone.
  private func heartbeat(_ id: ConnectionID) async {
    let limit = Duration.milliseconds(Self.pingInterval + Self.pingTimeout)
    while !Task.isCancelled {
      try? await Task.sleep(for: .milliseconds(Self.pingInterval))
      guard !Task.isCancelled, let link = links[id] else { return }
      if ContinuousClock.now - link.lastHeard > limit {
        close(id)
        return
      }
      Self.write(Wire.ping, on: link.connection)
    }
  }

  func send(_ text: String, to id: ConnectionID) {
    guard let link = links[id], link.isAttached else { return }
    Self.write(text, on: link.connection)
  }

  func send(_ text: String, to ids: [ConnectionID]) {
    for id in ids { send(text, to: id) }
  }

  func sendToAll(_ text: String) {
    for (id, link) in links where link.isAttached { send(text, to: id) }
  }

  func close(_ id: ConnectionID) {
    links[id]?.connection.cancel()
    drop(id)
  }

  private func drop(_ id: ConnectionID) {
    guard let link = links.removeValue(forKey: id) else { return }
    link.heartbeat?.cancel()
    link.connection.cancel()
    if link.isAttached { continuation.yield(.detached(id)) }
  }

  // MARK: - I/O

  /// Reads a request's head. An upgrade becomes a game connection
  /// (`readFrames`); anything else is answered from `WebPlayer` and closed.
  private nonisolated static func readRequest(on connection: NWConnection, buffered: Data = Data(), accent: String?, into sink: AsyncStream<Frame>.Continuation) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: HTTPRequest.maxHeadBytes) { data, _, isComplete, error in
      var buffer = buffered
      if let data { buffer.append(data) }
      switch HTTPRequest.parse(buffer) {
      case .incomplete:
        guard error == nil, !isComplete else { return finish(sink) }
        readRequest(on: connection, buffered: buffer, accent: accent, into: sink)
      case .invalid:
        answer(.error(400, "Bad Request"), on: connection, then: sink)
      case .complete(let request, let rest):
        guard request.isWebSocketUpgrade else {
          return answer(WebPlayer.shared.response(to: request, accent: accent), on: connection, then: sink)
        }
        // Socket.IO's path, as the laptop server has it.
        guard request.path.hasPrefix("/socket.io"), let key = request.headers["sec-websocket-key"] else {
          return answer(.error(404, "Not Found"), on: connection, then: sink)
        }
        send(HTTPResponse.switchingToWebSocket(key: key).serialized, on: connection)
        sink.yield(.ready)
        var messages = WebSocketMessages(maxMessageBytes: maxMessageBytes)
        guard deliver(messages.receive(rest), on: connection, into: sink) else { return }
        readFrames(on: connection, messages: messages, into: sink)
      }
    }
  }

  private nonisolated static func readFrames(on connection: NWConnection, messages: WebSocketMessages, into sink: AsyncStream<Frame>.Continuation) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: maxMessageBytes) { data, _, isComplete, error in
      var messages = messages
      guard error == nil else { return finish(sink) }
      if let data, !data.isEmpty {
        guard deliver(messages.receive(data), on: connection, into: sink) else { return }
      }
      guard !isComplete else { return finish(sink) }
      readFrames(on: connection, messages: messages, into: sink)
    }
  }

  /// Hands up what arrived, answering pings and closes. False once the
  /// connection is done.
  private nonisolated static func deliver(_ events: [WebSocketMessages.Event], on connection: NWConnection, into sink: AsyncStream<Frame>.Continuation) -> Bool {
    for event in events {
      switch event {
      case .text(let text):
        sink.yield(.text(text))
      case .ping(let payload):
        send(WebSocketFrame(opcode: .pong, payload: payload).serialized, on: connection)
      case .pong:
        break
      case .close:
        send(WebSocketFrame.close(WebSocketFrame.normalClosure).serialized, on: connection)
        finish(sink)
        return false
      case .invalid(let code):
        send(WebSocketFrame.close(code).serialized, on: connection)
        finish(sink)
        return false
      }
    }
    return true
  }

  /// A whole response, then the connection closes once it's sent.
  private nonisolated static func answer(_ response: HTTPResponse, on connection: NWConnection, then sink: AsyncStream<Frame>.Continuation) {
    connection.send(content: response.serialized, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in
      finish(sink)
    })
  }

  private nonisolated static func finish(_ sink: AsyncStream<Frame>.Continuation) {
    sink.yield(.closed)
    sink.finish()
  }

  private nonisolated static func send(_ data: Data, on connection: NWConnection, then done: (@Sendable () -> Void)? = nil) {
    connection.send(content: data, completion: .contentProcessed { _ in done?() })
  }

  private nonisolated static func write(_ text: String, on connection: NWConnection) {
    send(WebSocketFrame.text(text).serialized, on: connection)
  }

  /// Writes a frame and waits for the stack to take it — or a second, for a
  /// peer that's stopped reading.
  private nonisolated static func flush(_ frame: WebSocketFrame, on connection: NWConnection) async {
    let sent = Once<Void>()
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      sent.onFirst { done.resume() }
      send(frame.serialized, on: connection) { sent.fire(()) }
      Task {
        try? await Task.sleep(for: .seconds(1))
        sent.fire(())
      }
    }
  }

  private nonisolated static func isLocal(_ host: NWEndpoint.Host) -> Bool {
    switch host {
    case .ipv4(let address): return GameServer.isLocal(address)
    case .ipv6(let address): return GameServer.isLocal(address)
    default: return false
    }
  }
}

/// Resumes a continuation exactly once, however many state updates arrive.
private nonisolated final class Once<Value: Sendable>: Sendable {
  private let state = Mutex<(fired: Bool, handler: (@Sendable (Value) -> Void)?)>((false, nil))

  func onFirst(_ handler: @escaping @Sendable (Value) -> Void) {
    state.withLock { $0.handler = handler }
  }

  /// Returns false if something already fired.
  @discardableResult
  func fire(_ value: Value) -> Bool {
    let handler: (@Sendable (Value) -> Void)? = state.withLock { state in
      guard !state.fired else { return nil }
      state.fired = true
      return state.handler
    }
    handler?(value)
    return handler != nil
  }
}
