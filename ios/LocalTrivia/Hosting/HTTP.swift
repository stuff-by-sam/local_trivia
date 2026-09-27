import CryptoKit
import Foundation

// What a hosting phone's server speaks below Socket.IO: just enough HTTP/1.1
// to serve the web player to a phone without the app, and to upgrade a
// connection to a WebSocket (RFC 6455) for the game itself — both on the one
// port the join link names. Pure and free of I/O, so the tests can hold it to
// the RFCs byte for byte; `HostServer` does the reading and writing.

/// A request's head: the request line and headers, nothing after.
nonisolated struct HTTPRequest: Equatable, Sendable {
  let method: String
  /// Percent-decoded, without the query.
  let path: String
  /// Header names lower-cased; a repeated header keeps its last value.
  let headers: [String: String]

  /// A head bigger than this is refused, not buffered.
  static let maxHeadBytes = 8 * 1024

  enum Parsed: Equatable, Sendable {
    /// No blank line yet: read more.
    case incomplete
    case invalid
    /// The head, and whatever arrived after it.
    case complete(HTTPRequest, rest: Data)
  }

  static func parse(_ data: Data) -> Parsed {
    guard let end = data.firstRange(of: Data("\r\n\r\n".utf8)) else {
      return data.count > maxHeadBytes ? .invalid : .incomplete
    }
    guard end.lowerBound <= maxHeadBytes,
      let head = String(data: data[data.startIndex..<end.lowerBound], encoding: .utf8)
    else { return .invalid }
    var lines = head.components(separatedBy: "\r\n")
    let requestLine = lines.removeFirst().split(separator: " ", omittingEmptySubsequences: true)
    guard requestLine.count == 3, requestLine[2].hasPrefix("HTTP/1."),
      let target = URLComponents(string: String(requestLine[1])), requestLine[1].hasPrefix("/")
    else { return .invalid }
    var headers: [String: String] = [:]
    for line in lines {
      guard let colon = line.firstIndex(of: ":") else { return .invalid }
      let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
      guard !name.isEmpty else { return .invalid }
      headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
    }
    let request = HTTPRequest(method: String(requestLine[0]), path: target.path, headers: headers)
    return .complete(request, rest: Data(data[end.upperBound...]))
  }

  /// A well-formed request to turn this connection into a WebSocket.
  var isWebSocketUpgrade: Bool {
    method == "GET"
      && headers["upgrade"]?.lowercased() == "websocket"
      && headers["connection"]?.lowercased().split(separator: ",").contains { $0.trimmingCharacters(in: .whitespaces) == "upgrade" } == true
      && headers["sec-websocket-version"] == "13"
      && headers["sec-websocket-key"]?.isEmpty == false
  }
}

nonisolated struct HTTPResponse: Equatable, Sendable {
  let status: Int
  let reason: String
  var headers: [(String, String)]
  var body: Data

  static func == (a: HTTPResponse, b: HTTPResponse) -> Bool {
    a.status == b.status && a.body == b.body && a.headers.map { "\($0): \($1)" } == b.headers.map { "\($0): \($1)" }
  }

  /// A complete response, closing the connection after: the page is a
  /// handful of small files, so keep-alive buys nothing worth the bookkeeping.
  static func content(_ body: Data, type: String, includingBody: Bool = true) -> HTTPResponse {
    HTTPResponse(
      status: 200, reason: "OK",
      headers: [
        ("Content-Type", type),
        ("Content-Length", String(body.count)),
        // A new game is a new PIN, not a new page; still, never keep a stale one.
        ("Cache-Control", "no-cache"),
        ("X-Content-Type-Options", "nosniff"),
        ("Referrer-Policy", "no-referrer"),
        ("Connection", "close"),
      ],
      body: includingBody ? body : Data())
  }

  static func error(_ status: Int, _ reason: String) -> HTTPResponse {
    let body = Data("\(status) \(reason)\n".utf8)
    return HTTPResponse(
      status: status, reason: reason,
      headers: [
        ("Content-Type", "text/plain; charset=utf-8"),
        ("Content-Length", String(body.count)),
        ("Connection", "close"),
      ],
      body: body)
  }

  /// The handshake's answer (RFC 6455 §4.2.2). No subprotocol, no extensions:
  /// a client offering compression gets plain frames, as the RFC allows.
  static func switchingToWebSocket(key: String) -> HTTPResponse {
    HTTPResponse(
      status: 101, reason: "Switching Protocols",
      headers: [
        ("Upgrade", "websocket"),
        ("Connection", "Upgrade"),
        ("Sec-WebSocket-Accept", WebSocketFrame.acceptKey(for: key)),
      ],
      body: Data())
  }

  var serialized: Data {
    var head = "HTTP/1.1 \(status) \(reason)\r\n"
    for (name, value) in headers { head += "\(name): \(value)\r\n" }
    head += "\r\n"
    return Data(head.utf8) + body
  }
}

/// One WebSocket frame (RFC 6455 §5.2).
nonisolated struct WebSocketFrame: Equatable, Sendable {
  enum Opcode: UInt8, Sendable {
    case continuation = 0x0
    case text = 0x1
    case binary = 0x2
    case close = 0x8
    case ping = 0x9
    case pong = 0xA

    var isControl: Bool { rawValue & 0x8 != 0 }
  }

  var isFinal = true
  let opcode: Opcode
  let payload: Data

  enum Parsed: Equatable, Sendable {
    case incomplete
    /// Broken or unacceptable; close with this status code.
    case invalid(UInt16)
    /// A frame, and how many bytes of the buffer it took.
    case frame(WebSocketFrame, length: Int)
  }

  /// Close codes this server sends.
  static let normalClosure: UInt16 = 1000
  static let goingAway: UInt16 = 1001
  static let protocolError: UInt16 = 1002
  static let tooBig: UInt16 = 1009

  /// The first frame in `data`, as a client sends it: masked, as every
  /// client frame must be.
  static func parse(_ data: Data, maxPayload: Int) -> Parsed {
    let bytes = [UInt8](data.prefix(14))
    guard bytes.count >= 2 else { return .incomplete }
    // RSV bits are for extensions, and none were agreed.
    guard bytes[0] & 0x70 == 0, let opcode = Opcode(rawValue: bytes[0] & 0x0F) else { return .invalid(protocolError) }
    let isFinal = bytes[0] & 0x80 != 0
    guard bytes[1] & 0x80 != 0 else { return .invalid(protocolError) }
    var length = UInt64(bytes[1] & 0x7F)
    var offset = 2
    if length == 126 {
      guard bytes.count >= 4 else { return .incomplete }
      length = UInt64(bytes[2]) << 8 | UInt64(bytes[3])
      offset = 4
    } else if length == 127 {
      guard bytes.count >= 10 else { return .incomplete }
      length = bytes[2..<10].reduce(0) { $0 << 8 | UInt64($1) }
      offset = 10
    }
    if opcode.isControl, !isFinal || length > 125 { return .invalid(protocolError) }
    guard length <= UInt64(maxPayload) else { return .invalid(tooBig) }
    guard bytes.count >= offset + 4 else { return .incomplete }
    let mask = Array(bytes[offset..<offset + 4])
    offset += 4
    let total = offset + Int(length)
    guard data.count >= total else { return .incomplete }
    var payload = [UInt8](data[data.startIndex + offset..<data.startIndex + total])
    for index in payload.indices { payload[index] ^= mask[index & 3] }
    return .frame(WebSocketFrame(isFinal: isFinal, opcode: opcode, payload: Data(payload)), length: total)
  }

  /// As a server sends it: final, unmasked.
  var serialized: Data {
    var head: [UInt8] = [(isFinal ? 0x80 : 0) | opcode.rawValue]
    switch payload.count {
    case ..<126:
      head.append(UInt8(payload.count))
    case ...0xFFFF:
      head += [126, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
    default:
      head.append(127)
      head += (0..<8).reversed().map { UInt8(UInt64(payload.count) >> ($0 * 8) & 0xFF) }
    }
    return Data(head) + payload
  }

  static func text(_ text: String) -> WebSocketFrame {
    WebSocketFrame(opcode: .text, payload: Data(text.utf8))
  }

  static func close(_ code: UInt16) -> WebSocketFrame {
    WebSocketFrame(opcode: .close, payload: Data([UInt8(code >> 8), UInt8(code & 0xFF)]))
  }

  /// `Sec-WebSocket-Accept` for a client's `Sec-WebSocket-Key`.
  static func acceptKey(for key: String) -> String {
    Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8))).base64EncodedString()
  }
}

/// A WebSocket message arriving in pieces: a text or binary frame, then any
/// continuations up to the final one. Control frames may come in between.
nonisolated struct WebSocketMessages: Sendable {
  enum Event: Equatable, Sendable {
    case text(String)
    case ping(Data)
    case pong
    case close
    /// Broken or unacceptable; close with this status code.
    case invalid(UInt16)
  }

  let maxMessageBytes: Int
  private var buffer = Data()
  private var partial: (opcode: WebSocketFrame.Opcode, payload: Data)?

  init(maxMessageBytes: Int) {
    self.maxMessageBytes = maxMessageBytes
  }

  /// Adds what arrived, and returns every event it completes, in order.
  /// After `.close` or `.invalid`, nothing more is read.
  mutating func receive(_ data: Data) -> [Event] {
    buffer.append(data)
    var events: [Event] = []
    while true {
      switch WebSocketFrame.parse(buffer, maxPayload: maxMessageBytes) {
      case .incomplete:
        return events
      case .invalid(let code):
        return events + [.invalid(code)]
      case .frame(let frame, let length):
        buffer.removeFirst(length)
        guard let event = take(frame) else { continue }
        events.append(event)
        switch event {
        case .close, .invalid: return events
        default: continue
        }
      }
    }
  }

  private mutating func take(_ frame: WebSocketFrame) -> Event? {
    switch frame.opcode {
    case .ping: return .ping(frame.payload)
    case .pong: return .pong
    case .close: return .close
    case .text, .binary:
      guard partial == nil else { return .invalid(WebSocketFrame.protocolError) }
      partial = (frame.opcode, frame.payload)
    case .continuation:
      guard partial != nil else { return .invalid(WebSocketFrame.protocolError) }
      partial?.payload.append(frame.payload)
    }
    guard let message = partial else { return nil }
    guard message.payload.count <= maxMessageBytes else { return .invalid(WebSocketFrame.tooBig) }
    guard frame.isFinal else { return nil }
    partial = nil
    // Binary isn't part of this game's wire.
    guard message.opcode == .text else { return nil }
    guard let text = String(data: message.payload, encoding: .utf8) else { return .invalid(1007) }
    return .text(text)
  }
}
