import Foundation
import OSLog

nonisolated enum TransportEvent: Equatable, Sendable {
  /// Dialling. `attempt` counts consecutive failures since the last good link.
  case connecting(attempt: Int)
  /// Attached to the server. Any session state from before this is stale until
  /// the game layer resumes — the server maps players by socket id.
  case connected
  case disconnected
  /// One Socket.IO event: the raw `["name", payload]` JSON array.
  case message(Data)
}

/// What the game needs from a connection. `SocketConnection` is the real one;
/// the tests drive the game through a scripted fake.
nonisolated protocol GameTransport: AnyObject, Sendable {
  var events: AsyncStream<TransportEvent> { get }
  func start() async
  func stop() async
  /// Sends one event if attached. Returns false instead of queueing: an event
  /// sent before `resume` lands on a socket the server doesn't know, so the
  /// game layer re-syncs from the server's snapshot rather than replaying.
  @discardableResult func send(_ event: ClientEvent) async -> Bool
  /// The app is back in the foreground: re-verify the link now.
  func refresh() async
}

/// A Socket.IO client over `URLSessionWebSocketTask`, owning its own recovery.
///
/// Drops are routine at a party — phones lock between questions, walk out of
/// Wi-Fi range, get backgrounded to reply to a text. So the connection never
/// gives up: it retries with short, capped, jittered backoff (this is a LAN;
/// a server that's up answers in milliseconds) and reports `.connected` each
/// time it re-attaches, which is the game layer's cue to resume.
actor SocketConnection: GameTransport {
  nonisolated let events: AsyncStream<TransportEvent>
  private let continuation: AsyncStream<TransportEvent>.Continuation
  private let endpoint: URL
  private let session: URLSession
  private let encoder = JSONEncoder()

  private var socket: URLSessionWebSocketTask?
  private var isAttached = false
  private var lastHeard = ContinuousClock.now
  private var runner: Task<Void, Never>?
  private var backoff: Task<Void, any Error>?
  private var failures = 0

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "socket")

  enum ProtocolError: Error {
    case missingHandshake
    case refused(String)
    case unreadableFrame
  }

  init?(server: URL) {
    guard let endpoint = Wire.endpoint(for: server) else { return nil }
    self.endpoint = endpoint
    let configuration = URLSessionConfiguration.ephemeral
    // Bounds the upgrade against an address that silently drops packets, so a
    // stale IP fails in seconds rather than the default minute.
    configuration.timeoutIntervalForRequest = 4
    configuration.waitsForConnectivity = false
    session = URLSession(configuration: configuration)
    (events, continuation) = AsyncStream.makeStream()
  }

  func start() {
    guard runner == nil else { return }
    runner = Task { await run() }
  }

  func stop() {
    runner?.cancel()
    runner = nil
    backoff?.cancel()
    socket?.cancel(with: .normalClosure, reason: nil)
    session.invalidateAndCancel()
    continuation.finish()
  }

  @discardableResult
  func send(_ event: ClientEvent) async -> Bool {
    guard isAttached, let socket else { return false }
    do {
      try await socket.send(.string(Wire.event(json: encoder.encode(event))))
      return true
    } catch {
      Self.log.error("send failed: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  /// iOS freezes sockets in the background, and the server drops a client that
  /// misses ~45 s of pings. Waiting for the watchdog to notice would leave the
  /// player staring at a dead question, so on foreground: skip any backoff in
  /// progress, and if we believe we're attached, prove it with a ping.
  func refresh() async {
    if let backoff {
      backoff.cancel()
      return
    }
    guard let socket, isAttached else { return }
    let timeout = Task {
      try await Task.sleep(for: .seconds(1.5))
      socket.cancel(with: .goingAway, reason: nil)
    }
    let alive = await withCheckedContinuation { reply in
      socket.sendPing { reply.resume(returning: $0 == nil) }
    }
    timeout.cancel()
    if !alive {
      Self.log.notice("foreground probe failed; reconnecting")
      socket.cancel(with: .goingAway, reason: nil)
    }
  }

  // MARK: - Connection lifecycle

  private func run() async {
    while !Task.isCancelled {
      continuation.yield(.connecting(attempt: failures))
      do {
        try await attach()
      } catch {
        Self.log.info("link ended: \(error.localizedDescription, privacy: .public)")
      }
      continuation.yield(.disconnected)
      guard !Task.isCancelled else { return }
      failures += 1
      await pause(for: Self.retryDelay(after: failures))
    }
  }

  /// 250 ms, 500 ms, 1 s, 2 s, then 3 s — ±20% so a room full of phones waking
  /// together doesn't reconnect in lockstep.
  static func retryDelay(after failures: Int) -> Duration {
    let base = min(0.25 * pow(2, Double(max(0, failures - 1))), 3)
    return .seconds(base * Double.random(in: 0.8...1.2))
  }

  private func pause(for delay: Duration) async {
    let sleeper = Task { try await Task.sleep(for: delay) }
    backoff = sleeper
    _ = await sleeper.result
    backoff = nil
  }

  private func attach() async throws {
    let socket = session.webSocketTask(with: endpoint)
    self.socket = socket
    socket.resume()
    defer {
      socket.cancel(with: .goingAway, reason: nil)
      isAttached = false
      if self.socket === socket { self.socket = nil }
    }

    guard case .open(let handshake) = try Wire.decode(try await receive(from: socket)) else {
      throw ProtocolError.missingHandshake
    }
    try await socket.send(.string(Wire.connectRequest))

    lastHeard = .now
    let watchdog = Task { await watch(socket, silenceLimit: handshake.silenceLimit) }
    defer { watchdog.cancel() }

    while true {
      let frame = try Wire.decode(try await receive(from: socket))
      lastHeard = .now
      switch frame {
      case .ping:
        try await socket.send(.string(Wire.pong))
      case .connected:
        isAttached = true
        failures = 0
        continuation.yield(.connected)
      case .event(let json):
        continuation.yield(.message(json))
      case .close, .disconnected:
        return
      case .connectError(let reason):
        throw ProtocolError.refused(reason)
      case .open, .pong, .noop, .unsupported:
        continue
      }
    }
  }

  /// A half-open TCP link (Wi-Fi dropped without a FIN) never errors on its
  /// own; the only symptom is silence. The server pings on a fixed interval,
  /// so silence past the handshake's limit means the link is gone.
  private func watch(_ socket: URLSessionWebSocketTask, silenceLimit: Duration) async {
    while !Task.isCancelled {
      let deadline = lastHeard + silenceLimit
      if ContinuousClock.now >= deadline {
        Self.log.notice("no ping within \(silenceLimit, privacy: .public); dropping link")
        socket.cancel(with: .goingAway, reason: nil)
        return
      }
      try? await Task.sleep(until: deadline, clock: .continuous)
    }
  }

  private func receive(from socket: URLSessionWebSocketTask) async throws -> String {
    switch try await socket.receive() {
    case .string(let text): return text
    case .data(let data): return String(decoding: data, as: UTF8.self)
    @unknown default: throw ProtocolError.unreadableFrame
    }
  }
}
