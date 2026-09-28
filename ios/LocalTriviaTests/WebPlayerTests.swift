import CoreImage
import Foundation
import Testing
import UIKit

@testable import LocalTrivia

/// What a hosting phone's server speaks below Socket.IO — HTTP for the web
/// player, WebSocket for the game — held to the RFCs, and the join link that
/// points a camera at it.
struct HTTPFramingTests {
  /// RFC 6455 §1.3's worked example.
  @Test func answersTheHandshakeAsTheRFCDoes() {
    #expect(WebSocketFrame.acceptKey(for: "dGhlIHNhbXBsZSBub25jZQ==") == "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=")
  }

  @Test func readsAnUpgradeRequest() throws {
    let head = """
      GET /socket.io/?EIO=4&transport=websocket HTTP/1.1\r
      Host: 192.168.1.20:3000\r
      Upgrade: websocket\r
      Connection: keep-alive, Upgrade\r
      Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r
      Sec-WebSocket-Version: 13\r
      Sec-WebSocket-Extensions: permessage-deflate\r
      \r

      """
    guard case .complete(let request, let rest) = HTTPRequest.parse(Data(head.utf8) + Data([0x81])) else {
      Issue.record("didn't parse")
      return
    }
    #expect(request.method == "GET")
    #expect(request.path == "/socket.io/")
    #expect(request.isWebSocketUpgrade)
    #expect(request.headers["sec-websocket-key"] == "dGhlIHNhbXBsZSBub25jZQ==")
    #expect(rest == Data([0x81]), "a frame sent straight after the head isn't lost")

    let response = String(decoding: HTTPResponse.switchingToWebSocket(key: "dGhlIHNhbXBsZSBub25jZQ==").serialized, as: UTF8.self)
    #expect(response.hasPrefix("HTTP/1.1 101 Switching Protocols\r\n"))
    #expect(response.contains("Sec-WebSocket-Accept: s3pPLMBiTxaQ9kYGzzhZRbK+xOo=\r\n"))
    #expect(!response.contains("Sec-WebSocket-Extensions"), "no compression was agreed")
    #expect(response.hasSuffix("\r\n\r\n"))
  }

  @Test func waitsForTheWholeHeadAndRefusesJunk() {
    #expect(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nHost: x\r\n".utf8)) == .incomplete)
    #expect(HTTPRequest.parse(Data("HELLO\r\n\r\n".utf8)) == .invalid)
    #expect(HTTPRequest.parse(Data("GET nope HTTP/1.1\r\n\r\n".utf8)) == .invalid)
    #expect(HTTPRequest.parse(Data("GET / HTTP/1.1\r\nno colon\r\n\r\n".utf8)) == .invalid)
    #expect(HTTPRequest.parse(Data(repeating: UInt8(ascii: "a"), count: HTTPRequest.maxHeadBytes + 1)) == .invalid, "a head too big isn't buffered")

    guard case .complete(let plain, _) = HTTPRequest.parse(Data("GET /play/play.js?v=2 HTTP/1.1\r\nHost: x\r\n\r\n".utf8)) else {
      Issue.record("didn't parse")
      return
    }
    #expect(plain.path == "/play/play.js")
    #expect(!plain.isWebSocketUpgrade)
  }

  /// Clients always mask; the server never does.
  @Test func unmasksWhatAClientSends() {
    // RFC 6455 §5.7: a masked "Hello".
    let hello = Data([0x81, 0x85, 0x37, 0xFA, 0x21, 0x3D, 0x7F, 0x9F, 0x4D, 0x51, 0x58])
    #expect(WebSocketFrame.parse(hello, maxPayload: 1024) == .frame(.text("Hello"), length: hello.count))
    #expect(WebSocketFrame.parse(hello.prefix(6), maxPayload: 1024) == .incomplete)

    let unmasked = Data([0x81, 0x05]) + Data("Hello".utf8)
    #expect(WebSocketFrame.parse(unmasked, maxPayload: 1024) == .invalid(WebSocketFrame.protocolError))
    #expect(WebSocketFrame.parse(masked("x", length: 200), maxPayload: 100) == .invalid(WebSocketFrame.tooBig))
  }

  @Test func writesUnmaskedFramesOfEverySize() {
    #expect(WebSocketFrame.text("Hello").serialized == Data([0x81, 0x05]) + Data("Hello".utf8))
    let medium = WebSocketFrame.text(String(repeating: "a", count: 300)).serialized
    #expect(Array(medium.prefix(4)) == [0x81, 126, 0x01, 0x2C])
    let large = WebSocketFrame.text(String(repeating: "a", count: 70_000)).serialized
    #expect(Array(large.prefix(10)) == [0x81, 127, 0, 0, 0, 0, 0, 0x01, 0x11, 0x70])
    #expect(WebSocketFrame.close(WebSocketFrame.goingAway).serialized == Data([0x88, 0x02, 0x03, 0xE9]))
  }

  @Test func assemblesMessagesAcrossFramesAndReads() {
    var messages = WebSocketMessages(maxMessageBytes: 1024)
    let frames = masked("42[\"join\",", fin: false) + masked("pong", opcode: 0x9) + masked("{}]", opcode: 0x0)
    // Byte by byte: however TCP splits it, the same events come out.
    var events: [WebSocketMessages.Event] = []
    for byte in frames { events += messages.receive(Data([byte])) }
    #expect(events == [.ping(Data("pong".utf8)), .text("42[\"join\",{}]")])

    #expect(messages.receive(masked("", opcode: 0x8)) == [.close])
  }

  @Test func refusesAMessageTooBigInPieces() {
    var messages = WebSocketMessages(maxMessageBytes: 8)
    #expect(messages.receive(masked("12345", fin: false)) == [])
    #expect(messages.receive(masked("67890", opcode: 0x0)) == [.invalid(WebSocketFrame.tooBig)])
  }

  @Test func refusesAContinuationWithNothingToContinue() {
    var messages = WebSocketMessages(maxMessageBytes: 64)
    #expect(messages.receive(masked("x", opcode: 0x0)) == [.invalid(WebSocketFrame.protocolError)])
  }

  /// A client frame: masked, with a fixed key.
  private func masked(_ text: String, opcode: UInt8 = 0x1, fin: Bool = true, length: Int? = nil) -> Data {
    let payload = Array(length.map { String(repeating: text, count: $0) } ?? text).map { UInt8(ascii: $0.unicodeScalars.first!) }
    let key: [UInt8] = [0x12, 0x34, 0x56, 0x78]
    var frame: [UInt8] = [(fin ? 0x80 : 0) | opcode]
    if payload.count < 126 {
      frame.append(0x80 | UInt8(payload.count))
    } else {
      frame += [0x80 | 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)]
    }
    frame += key
    frame += payload.enumerated().map { $1 ^ key[$0 & 3] }
    return Data(frame)
  }
}

struct WebPlayerTests {
  /// The app bundles the laptop's own player page; this is what a phone
  /// without the app gets.
  @Test func servesThePlayerPageAndWhatItLoads() throws {
    let player = WebPlayer.shared
    let page = player.response(to: get("/"))
    #expect(page.status == 200)
    #expect(page.headers.contains { $0 == ("Content-Type", "text/html; charset=utf-8") })
    let html = String(decoding: page.body, as: UTF8.self)
    #expect(html.contains("<script src=\"/socket.io/socket.io.js\"></script>"))

    // Everything the page asks for is there.
    let assets = html.matches(of: /(?:src|href)="(\/[^"]+)"/).map { String($0.1) }
    #expect(assets.count >= 7)
    for asset in assets {
      #expect(player.response(to: get(asset)).status == 200, "\(asset)")
    }
    let fonts = String(decoding: player.response(to: get("/fonts/fonts.css")).body, as: UTF8.self)
    for font in fonts.matches(of: /url\((\/[^)]+)\)/).map({ String($0.1) }) {
      #expect(player.response(to: get(font)).status == 200, "\(font)")
    }
    #expect(player.response(to: get("/play")).body == page.body)
  }

  /// A browser has no theme of its own: a hosting phone serves the page in
  /// the host's accent, and `theme.js` paints it before the first frame, so a
  /// player sees the host's colours from the join screen on.
  @Test func servesThePageInTheHostsAccent() throws {
    let player = WebPlayer.shared
    for path in ["/", "/play", "/play/index.html"] {
      let html = String(decoding: player.response(to: get(path), accent: "#ffb000").body, as: UTF8.self)
      #expect(html.contains(##"<html data-accent="#ffb000" lang="en">"##), "\(path)")
    }
    let html = String(decoding: player.response(to: get("/"), accent: "#ffb000").body, as: UTF8.self)
    let script = try #require(html.range(of: #"<script src="/shared/theme.js"></script>"#))
    #expect(script.lowerBound < html.range(of: "</head>")!.lowerBound, "theme.js runs from <head>")

    // Only the page, and only a colour.
    #expect(player.response(to: get("/play/play.js"), accent: "#ffb000").body == player.response(to: get("/play/play.js")).body)
    #expect(player.response(to: get("/"), accent: #""><script>alert(1)</script>"#).body == player.response(to: get("/")).body)
    #expect(!String(decoding: player.response(to: get("/")).body, as: UTF8.self).contains("data-accent"))
  }

  @Test func servesOnlyWhatsBundled() {
    let player = WebPlayer.shared
    for path in ["/../Info.plist", "/play/../../Info.plist", "/Info.plist", "/admin/admin.js", "/nope", "/play/"] {
      #expect(player.response(to: get(path)).status == 404, "\(path)")
    }
    #expect(player.response(to: HTTPRequest(method: "POST", path: "/", headers: [:])).status == 405)
    let head = player.response(to: HTTPRequest(method: "HEAD", path: "/", headers: [:]))
    #expect(head.status == 200)
    #expect(head.body.isEmpty)
  }

  private func get(_ path: String) -> HTTPRequest {
    HTTPRequest(method: "GET", path: path, headers: [:])
  }
}

struct JoinLinkTests {
  /// What the host's QR code holds: a page any phone's camera opens.
  @Test func pointsTheCameraAtTheGamesOwnPage() throws {
    let server = try #require(GameServer(address: "192.168.1.20:3001"))
    let link = JoinLink(server: server, pin: "4821")
    #expect(link.url.absoluteString == "http://192.168.1.20:3001/?pin=4821")
    #expect(link.address == "192.168.1.20:3001")
    #expect(JoinLink(url: link.url) == link, "the app's scanner reads it too")
  }

  /// Read back from the image the host's screen and TV draw, as a camera would.
  @Test func drawsTheWebLinkIntoTheQRCode() throws {
    let link = JoinLink(server: try #require(GameServer(address: "192.168.1.20:3000")), pin: "4821")
    let image = try #require(QRCode.image(for: link.url.absoluteString)?.cgImage)
    // Scaled up with a quiet zone, as `QRCodeView` shows it.
    let drawn = CIImage(cgImage: image).transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    let framed = drawn.composited(over: CIImage(color: .white).cropped(to: drawn.extent.insetBy(dx: -64, dy: -64)))
    let detector = try #require(CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: nil))
    let read = detector.features(in: framed).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
    #expect(read == ["http://192.168.1.20:3000/?pin=4821"])
    let scanned = try #require(read.first.flatMap(URL.init(string:)))
    #expect(JoinLink(url: scanned) == link)
  }

  @Test func opensTheAppFromItsOwnScheme() throws {
    let url = try #require(URL(string: "localtrivia://join?url=http://192.168.1.20:3000&pin=4821"))
    let link = try #require(JoinLink(url: url))
    #expect(link.server.url.absoluteString == "http://192.168.1.20:3000")
    #expect(link.pin == "4821")
  }

  /// A laptop's QR code is its bare address, and that isn't a game this app
  /// plays; nor is anywhere off the local network.
  @Test func refusesWhatIsntAPhoneHostsGame() {
    for text in [
      "http://192.168.1.20:3000",
      "http://192.168.1.20:3000/?pin=48",
      "http://192.168.1.20:3000/admin?pin=4821",
      "http://example.com:3000/?pin=4821",
      "http://8.8.8.8:3000/?pin=4821",
      "https://192.168.1.20:3000/?pin=4821",
      "localtrivia://join?url=http://example.com:3000&pin=4821",
      "localtrivia://other?url=http://192.168.1.20:3000",
    ] {
      #expect(JoinLink(url: URL(string: text)!) == nil, "\(text)")
    }
  }
}
