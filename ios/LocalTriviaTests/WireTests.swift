import Foundation
import Testing

@testable import LocalTrivia

/// Frames here are copied from a live socket.io 4.8 server, not written from
/// the spec — the point is to match what actually comes over the wire.
@Suite struct WireTests {
  @Test func decodesTheEngineHandshake() throws {
    let frame = try Wire.decode(
      #"0{"sid":"lN4bXk0p9Dq1AAAB","upgrades":[],"pingInterval":25000,"pingTimeout":20000,"maxPayload":1000000}"#)
    #expect(frame == .open(Wire.Handshake(pingInterval: 25_000, pingTimeout: 20_000)))
    if case .open(let handshake) = frame {
      #expect(handshake.silenceLimit == .seconds(45))
    }
  }

  @Test(arguments: [
    ("1", Wire.Frame.close),
    ("2", .ping),
    ("3", .pong),
    ("6", .noop),
    ("40", .connected),
    (#"40{"sid":"u8Qp1fX2AAAD"}"#, .connected),
    ("41", .disconnected),
    ("5", .unsupported),
  ])
  func decodesControlFrames(text: String, expected: Wire.Frame) throws {
    #expect(try Wire.decode(text) == expected)
  }

  @Test func passesEventBodiesThroughUntouched() throws {
    let body = #"["questionStart",{"questionId":7,"text":"Où est le 42?"}]"#
    #expect(try Wire.decode("42" + body) == .event(Data(body.utf8)))
  }

  @Test func skipsAckIDsAndNamespaces() throws {
    let body = #"["answerAck",{"questionId":3}]"#
    #expect(try Wire.decode("4217" + body) == .event(Data(body.utf8)))
    #expect(try Wire.decode("42/admin," + body) == .event(Data(body.utf8)))
    #expect(try Wire.decode("42/admin,9" + body) == .event(Data(body.utf8)))
  }

  @Test func surfacesConnectErrors() throws {
    #expect(try Wire.decode(#"44{"message":"Invalid namespace"}"#) == .connectError(#"{"message":"Invalid namespace"}"#))
  }

  @Test func rejectsAnEmptyFrame() {
    #expect(throws: Wire.DecodingError.emptyFrame) { try Wire.decode("") }
  }

  @Test func framesOutgoingEvents() throws {
    let json = try JSONEncoder().encode(ClientEvent.resume(token: "abc"))
    #expect(Wire.event(json: json) == #"42["resume",{"token":"abc"}]"#)
  }

  @Test func buildsTheWebSocketEndpoint() {
    #expect(
      Wire.endpoint(for: URL(string: "http://192.168.1.20:3000")!)?.absoluteString
        == "ws://192.168.1.20:3000/socket.io/?EIO=4&transport=websocket")
    #expect(
      Wire.endpoint(for: URL(string: "https://trivia.example")!)?.absoluteString
        == "wss://trivia.example/socket.io/?EIO=4&transport=websocket")
  }

  @Test func backsOffQuicklyThenCaps() {
    for _ in 0..<50 {
      #expect((Duration.milliseconds(200)...Duration.milliseconds(300)).contains(SocketConnection.retryDelay(after: 1)))
      #expect((Duration.milliseconds(400)...Duration.milliseconds(600)).contains(SocketConnection.retryDelay(after: 2)))
      #expect(SocketConnection.retryDelay(after: 40) <= Duration.milliseconds(3_600))
    }
  }
}
