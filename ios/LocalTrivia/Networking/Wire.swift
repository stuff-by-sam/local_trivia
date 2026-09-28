import Foundation

/// The Engine.IO v4 / Socket.IO v5 wire format — exactly the subset the trivia
/// server speaks, and nothing more.
///
/// socket.io 4.x frames every message as one WebSocket text frame whose leading
/// digits say what it is:
///
///     0{"sid":…,"pingInterval":25000,"pingTimeout":20000}   engine: open
///     2  /  3                                                 engine: ping / pong
///     40{"sid":…}                                             socket: connected
///     42["questionStart",{…}]                                 socket: event
///
/// Kept free of I/O so it can be tested byte-for-byte against real frames. Event
/// bodies are handed up as raw JSON: the game layer decodes them in one pass,
/// straight into typed payloads.
nonisolated enum Wire {
  struct Handshake: Decodable, Equatable, Sendable {
    /// Milliseconds between server pings.
    let pingInterval: Int
    /// Milliseconds the server waits for our pong before dropping us.
    let pingTimeout: Int

    /// How long silence can last before the link is presumed dead. The server
    /// pings every `pingInterval`, so anything past interval + timeout means
    /// the server has already given up on us too.
    var silenceLimit: Duration { .milliseconds(pingInterval + pingTimeout) }
  }

  enum Frame: Equatable, Sendable {
    case open(Handshake)
    case close
    case ping
    case pong
    case noop
    case connected
    case disconnected
    case connectError(String)
    /// A JSON array: `["eventName", payload]`.
    case event(Data)
    case unsupported
  }

  enum DecodingError: Error, Equatable {
    case emptyFrame
  }

  /// Asks the server to attach us to the default namespace.
  static let connectRequest = "40"
  static let ping = "2"
  static let pong = "3"
  /// Server side: "you're detached from the namespace".
  static let disconnect = "41"

  // MARK: Server side — what a phone-hosted game sends (see HostServer).

  /// The Engine.IO handshake a server opens every connection with.
  static func open(sid: String, pingInterval: Int, pingTimeout: Int, maxPayload: Int) -> String {
    #"0{"sid":"\#(sid)","upgrades":[],"pingInterval":\#(pingInterval),"pingTimeout":\#(pingTimeout),"maxPayload":\#(maxPayload)}"#
  }

  /// Attaches the client to the default namespace.
  static func connectAck(sid: String) -> String {
    #"40{"sid":"\#(sid)"}"#
  }

  static func event(json: Data) -> String {
    "42" + String(decoding: json, as: UTF8.self)
  }

  /// `http://host:port` → `ws://host:port/socket.io/?EIO=4&transport=websocket`.
  ///
  /// Straight to WebSocket, skipping the long-polling handshake the browser
  /// client opens with: one round trip fewer to join, and one transport to
  /// reason about.
  static func endpoint(for server: URL) -> URL? {
    guard var parts = URLComponents(url: server, resolvingAgainstBaseURL: false) else { return nil }
    parts.scheme = parts.scheme == "https" ? "wss" : "ws"
    parts.path = "/socket.io/"
    parts.queryItems = [
      URLQueryItem(name: "EIO", value: "4"),
      URLQueryItem(name: "transport", value: "websocket"),
    ]
    return parts.url
  }

  static func decode(_ text: String) throws -> Frame {
    var bytes = text.utf8[...]
    guard let type = bytes.popFirst() else { throw DecodingError.emptyFrame }
    switch type {
    case UInt8(ascii: "0"):
      return .open(try JSONDecoder().decode(Handshake.self, from: Data(bytes)))
    case UInt8(ascii: "1"): return .close
    case UInt8(ascii: "2"): return .ping
    case UInt8(ascii: "3"): return .pong
    case UInt8(ascii: "4"): return decodeSocketPacket(bytes)
    case UInt8(ascii: "6"): return .noop
    default: return .unsupported
    }
  }

  private static func decodeSocketPacket(_ packet: Substring.UTF8View) -> Frame {
    var bytes = packet
    guard let type = bytes.popFirst() else { return .unsupported }
    // A non-default namespace prefixes "/name," — this server only uses "/",
    // but skipping it keeps a future namespace from being misread as JSON.
    if bytes.first == UInt8(ascii: "/") {
      let comma = bytes.firstIndex(of: UInt8(ascii: ",")) ?? bytes.endIndex
      bytes = bytes[comma...].dropFirst()
    }
    // Then an optional numeric ack id, which we never request.
    while let digit = bytes.first, (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(digit) {
      bytes.removeFirst()
    }
    switch type {
    case UInt8(ascii: "0"): return .connected
    case UInt8(ascii: "1"): return .disconnected
    case UInt8(ascii: "2"): return .event(Data(bytes))
    case UInt8(ascii: "4"): return .connectError(String(decoding: bytes, as: UTF8.self))
    default: return .unsupported
    }
  }
}
