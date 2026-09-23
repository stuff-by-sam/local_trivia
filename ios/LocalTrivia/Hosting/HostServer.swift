import Foundation
import Network
import OSLog
import Synchronization

/// The game server a phone-hosted game runs: Socket.IO over WebSocket on the
/// local network — the same wire as the laptop server, so the Node test bots
/// work unchanged — advertised over Bonjour as `GameBrowser.serviceType`,
/// which only phones advertise.
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

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "host-server")

  private final class Link {
    let connection: NWConnection
    let sid: String
    let peer: String
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

  /// After a long suspension the listener may be gone; bring it back on the
  /// same port so every player's saved address still works. And if the
  /// phone's own address has changed — Wi-Fi or Personal Hotspot came up
  /// after hosting started, say — advertise the new one, or no other phone
  /// can find the game.
  func ensureListening(lanAddress: String?) async {
    guard let port else { return }
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
    let parameters = NWParameters.tcp
    let websocket = NWProtocolWebSocket.Options()
    websocket.autoReplyPing = true
    websocket.maximumMessageSize = Self.maxMessageBytes
    parameters.defaultProtocolStack.applicationProtocols.insert(websocket, at: 0)
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
    listener?.cancel()
    listener = nil
    let closing = links.values.map(\.connection)
    for link in links.values {
      link.pump?.cancel()
      link.heartbeat?.cancel()
    }
    links = [:]
    // Frames go out in order, so once this one's taken, so is everything before it.
    await withTaskGroup(of: Void.self) { group in
      for connection in closing {
        group.addTask { await Self.flush(Wire.disconnect, on: connection) }
      }
    }
    for connection in closing { connection.cancel() }
    continuation.finish()
  }

  // MARK: - Connections

  private func accept(_ connection: NWConnection) {
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
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready: sink.yield(.ready)
      case .failed, .cancelled:
        sink.yield(.closed)
        sink.finish()
      default: break
      }
    }
    link.pump = Task { await self.pump(id, frames) }
    connection.start(queue: queue)
    Self.receive(on: connection, into: sink)
  }

  /// One task per connection, draining its frames in order.
  private func pump(_ id: ConnectionID, _ frames: AsyncStream<Frame>) async {
    for await frame in frames {
      guard let link = links[id] else { break }
      switch frame {
      case .ready:
        Self.write(
          Wire.open(sid: link.sid, pingInterval: Self.pingInterval, pingTimeout: Self.pingTimeout, maxPayload: Self.maxMessageBytes),
          on: link.connection)
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

  private nonisolated static func receive(on connection: NWConnection, into sink: AsyncStream<Frame>.Continuation) {
    connection.receiveMessage { data, context, _, error in
      guard error == nil, data != nil || context != nil else {
        sink.yield(.closed)
        sink.finish()
        return
      }
      let metadata = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
      switch metadata?.opcode {
      case .text?:
        if let data { sink.yield(.text(String(decoding: data, as: UTF8.self))) }
      case .close?:
        sink.yield(.closed)
        sink.finish()
        return
      default:
        break
      }
      receive(on: connection, into: sink)
    }
  }

  private nonisolated static func write(_ text: String, on connection: NWConnection, then done: (@Sendable () -> Void)? = nil) {
    let metadata = NWProtocolWebSocket.Metadata(opcode: .text)
    let context = NWConnection.ContentContext(identifier: "frame", metadata: [metadata])
    connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .contentProcessed { _ in done?() })
  }

  /// Writes a frame and waits for the stack to take it — or a second, for a
  /// peer that's stopped reading.
  private nonisolated static func flush(_ text: String, on connection: NWConnection) async {
    let sent = Once<Void>()
    await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
      sent.onFirst { done.resume() }
      write(text, on: connection) { sent.fire(()) }
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
