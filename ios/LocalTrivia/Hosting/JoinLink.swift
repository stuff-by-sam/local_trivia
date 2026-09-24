import CoreImage
import CoreImage.CIFilterBuiltins
import Darwin
import Foundation
import UIKit

/// `localtrivia://join?url=http://192.168.1.20:3000&pin=4821` — what the host's
/// QR code holds. Scanned with the Camera app it opens this app straight into
/// the game; scanned in-app it does the same. The PIN rides along because the
/// code is only ever on the host's screen, in the room — the same place the
/// PIN itself is shown.
nonisolated struct JoinLink: Equatable, Sendable {
  static let scheme = "localtrivia"

  let server: GameServer
  let pin: String?

  init(server: GameServer, pin: String?) {
    self.server = server
    self.pin = pin.flatMap(Self.validPIN)
  }

  /// Anything can open a URL, so it's held to the same rules as a restored
  /// game: local-network servers only, and a PIN that's four digits or nothing.
  init?(url: URL) {
    guard url.scheme?.lowercased() == Self.scheme, url.host() == "join",
      let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
      let address = items.first(where: { $0.name == "url" })?.value,
      let server = GameServer(address: address)
    else { return nil }
    self.init(server: server, pin: items.first { $0.name == "pin" }?.value)
  }

  var url: URL {
    var parts = URLComponents()
    parts.scheme = Self.scheme
    parts.host = "join"
    parts.queryItems = [URLQueryItem(name: "url", value: server.url.absoluteString)] + (pin.map { [URLQueryItem(name: "pin", value: $0)] } ?? [])
    return parts.url!
  }

  private static func validPIN(_ pin: String) -> String? {
    pin.count == GameStore.pinLength && pin.allSatisfy { $0.isASCII && $0.isNumber } ? pin : nil
  }
}

/// The address other phones can reach this one at.
nonisolated enum LocalAddress {
  /// Wi-Fi first; then a Personal Hotspot's bridge, so a host can run a game
  /// with no router at all by letting everyone join their hotspot.
  static func current() -> String? {
    var head: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&head) == 0, let first = head else { return nil }
    defer { freeifaddrs(head) }

    var candidates: [(interface: String, address: String)] = []
    for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
      let flags = Int32(entry.pointee.ifa_flags)
      guard flags & IFF_UP != 0, flags & IFF_LOOPBACK == 0,
        let socketAddress = entry.pointee.ifa_addr, socketAddress.pointee.sa_family == UInt8(AF_INET)
      else { continue }
      var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
      guard getnameinfo(socketAddress, socklen_t(socketAddress.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0
      else { continue }
      let address = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
      let interface = String(decoding: Data(bytes: entry.pointee.ifa_name, count: strlen(entry.pointee.ifa_name)), as: UTF8.self)
      // Private and routable on the LAN; link-local (169.254) means no network.
      guard GameServer.isLocal(host: address), !address.hasPrefix("169.254.") else { continue }
      candidates.append((interface, address))
    }
    return candidates.first { $0.interface == "en0" }?.address
      ?? candidates.first { $0.interface.hasPrefix("bridge") }?.address
      ?? candidates.first?.address
  }
}

/// Renders a QR code: black modules on white, crisp at any size.
///
/// Rendered once per payload and kept: a view asking again — the lobby, the
/// join code sheet, the TV — gets the same image instead of a fresh render,
/// and one Core Image context serves them all.
enum QRCode {
  private static let context = CIContext(options: [.cacheIntermediates: false])
  private static var rendered: [String: UIImage] = [:]

  static func image(for text: String) -> UIImage? {
    if let image = rendered[text] { return image }
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage,
      let cgImage = context.createCGImage(output, from: output.extent)
    else { return nil }
    let image = UIImage(cgImage: cgImage)
    // A game has one join link; a handful covers a host who restarts.
    if rendered.count >= 4 { rendered.removeAll() }
    rendered[text] = image
    return image
  }
}
