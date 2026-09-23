import Foundation
import Network

/// A game the app can join — the hosting phone's address — and what to call it.
///
/// Only servers on the local network qualify. That's the product — a game in
/// the room, no internet — and it's also the trust boundary: a QR code stuck on
/// a wall can't send players' phones to a server somewhere else. It matches
/// what App Transport Security is configured to allow (`NSAllowsLocalNetworking`).
nonisolated struct GameServer: Codable, Hashable, Sendable {
  /// The first port a hosting phone tries (`HostServer.ports`).
  static let defaultPort = 3000

  let name: String
  /// Origin only — `http://host:port`.
  let url: URL

  /// Reads what a join link, a Bonjour advert or saved settings hold —
  /// `http://192.168.1.20:3000` — and, leniently, forms like `192.168.1.20` or
  /// `iphone.local`, as long as it's on the local network. A join link is
  /// input from anywhere, so this is also where the local-network rule holds.
  init?(address: String, name: String? = nil) {
    var text = address.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return nil }
    if !text.contains("://") { text = "http://" + text }
    guard var parts = URLComponents(string: text),
      let scheme = parts.scheme?.lowercased(), scheme == "http" || scheme == "https",
      let host = parts.host?.lowercased(), !host.isEmpty, Self.isLocal(host: host)
    else { return nil }

    parts.scheme = scheme
    parts.host = host
    if parts.port == nil, scheme == "http" { parts.port = Self.defaultPort }
    parts.path = ""
    parts.query = nil
    parts.fragment = nil
    parts.user = nil
    parts.password = nil
    guard let url = parts.url else { return nil }

    self.url = url
    self.name = name ?? parts.port.map { "\(host):\($0)" } ?? host
  }

  /// Decoding (the last-used game, from settings) re-applies the same rules, so
  /// there's no path to a `GameServer` that skipped them.
  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let url = try container.decode(URL.self, forKey: .url)
    let name = try container.decode(String.self, forKey: .name)
    guard let server = GameServer(address: url.absoluteString, name: name) else {
      throw DecodingError.dataCorruptedError(forKey: .url, in: container, debugDescription: "Not a local game server")
    }
    self = server
  }

  /// The same game under the name it's advertised as.
  func renamed(_ name: String) -> GameServer {
    GameServer(name: name, url: url)
  }

  private init(name: String, url: URL) {
    self.name = name
    self.url = url
  }

  /// This phone itself — a game it's hosting.
  var isLoopback: Bool {
    guard let host = url.host()?.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) else { return false }
    return host == "localhost" || IPv4Address(host)?.isLoopback == true || IPv6Address(host)?.isLoopback == true
  }

  /// `host:port`, for showing under a friendly name.
  var address: String {
    let host = url.host() ?? url.absoluteString
    return url.port.map { "\(host):\($0)" } ?? host
  }

  // MARK: - What counts as local

  /// Private and link-local addresses, loopback, and names only a local
  /// resolver answers: bare hostnames, mDNS (`.local`), and the suffixes
  /// reserved for home and private networks.
  static func isLocal(host: String) -> Bool {
    let bare = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    if let v4 = IPv4Address(bare) { return isLocal(v4) }
    if let v6 = IPv6Address(bare) { return isLocal(v6) }
    if bare == "localhost" || !bare.contains(".") { return true }
    return localSuffixes.contains { bare.hasSuffix($0) }
  }

  private static let localSuffixes = [".local", ".home.arpa", ".lan", ".internal"]

  static func isLocal(_ address: IPv6Address) -> Bool {
    if let mapped = address.asIPv4 { return isLocal(mapped) }
    // fc00::/7 is unique-local — IPv6's private range.
    return address.isLoopback || address.isLinkLocal || (address.rawValue.first.map { $0 & 0xFE == 0xFC } ?? false)
  }

  static func isLocal(_ address: IPv4Address) -> Bool {
    if address.isLoopback || address.isLinkLocal { return true }
    let octets = Array(address.rawValue)
    guard octets.count == 4 else { return false }
    switch (octets[0], octets[1]) {
    case (10, _): return true  // 10.0.0.0/8
    case (172, 16...31): return true  // 172.16.0.0/12
    case (192, 168): return true  // 192.168.0.0/16
    default: return false
    }
  }
}
