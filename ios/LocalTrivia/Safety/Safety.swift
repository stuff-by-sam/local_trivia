import Foundation
import Observation

/// What keeps a game with strangers safe to play: the Terms of Use everyone
/// agrees to first, who this phone has blocked, and the report being written.
/// (App Review guideline 1.2, for apps where people see what others type.)
///
/// A game has no accounts and no server, so a block is kept on the phone
/// that made it, and acts there:
/// - A **host** blocks a player: they're removed, and the phone they played
///   on (`installID`, or a browser's own id) can't join a game hosted here
///   again. Their address is kept out too, for as long as this hosting lasts.
/// - A **player** blocks a host: they leave the game, and that host's games
///   aren't listed here again.
/// - A **player** blocks another player: their name is hidden on this phone,
///   in the standings, the podium and on the TV.
///
/// Every block also sends a report, so the developer hears of it.
@Observable
final class Safety {
  /// Where reports go.
  nonisolated static let reportAddress = "report@local-trivia.com"
  /// Raised when the terms change enough that everyone should agree again.
  nonisolated static let termsVersion = 1

  struct BlockedHost: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    /// The host's `installID`, from its advert; nil for a game found only by
    /// its address.
    let hostID: String?
    let name: String
    /// The host's address, without its port.
    let address: String
    var date = Date()
  }

  struct BlockedPlayer: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let nickname: String
    /// The id their phone or browser joined with, if it sent one.
    let device: String?
    var date = Date()
  }

  struct HiddenName: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    let nickname: String
    var date = Date()
  }

  private(set) var acceptedTermsVersion: Int {
    didSet { defaults?.set(acceptedTermsVersion, forKey: Keys.terms) }
  }
  private(set) var blockedHosts: [BlockedHost] { didSet { save(blockedHosts, Keys.hosts) } }
  private(set) var blockedPlayers: [BlockedPlayer] { didSet { save(blockedPlayers, Keys.players) } }
  private(set) var hiddenNames: [HiddenName] { didSet { save(hiddenNames, Keys.names) } }
  /// The report being written, shown over whatever's on screen — the game
  /// may end under it, after a block.
  var report: Report?

  /// A random id for this install, never tied to the person or the device:
  /// it's how a host this phone joins can keep it out after a block, and how
  /// a player can hide this phone's games. It goes only to phones on the
  /// same network, in a game.
  let installID: String

  var hasAcceptedTerms: Bool { acceptedTermsVersion >= Self.termsVersion }

  @ObservationIgnored private let defaults: UserDefaults?

  private enum Keys {
    static let terms = "termsAccepted"
    static let install = "installID"
    static let hosts = "blockedHosts"
    static let players = "blockedPlayers"
    static let names = "hiddenNames"
  }

  /// `defaults: nil` keeps everything in memory (tests, previews).
  init(defaults: UserDefaults? = .standard) {
    self.defaults = defaults
    acceptedTermsVersion = defaults?.integer(forKey: Keys.terms) ?? 0
    blockedHosts = Self.load(defaults, Keys.hosts) ?? []
    blockedPlayers = Self.load(defaults, Keys.players) ?? []
    hiddenNames = Self.load(defaults, Keys.names) ?? []
    if let saved = defaults?.string(forKey: Keys.install) {
      installID = saved
    } else {
      installID = UUID().uuidString.lowercased()
      defaults?.set(installID, forKey: Keys.install)
    }
  }

  func acceptTerms() {
    acceptedTermsVersion = Self.termsVersion
  }

  // MARK: - Hosts

  func block(host server: GameServer, hostID: String?) {
    guard !isBlocked(server, hostID: hostID) else { return }
    blockedHosts.append(BlockedHost(hostID: hostID, name: server.name, address: Self.host(of: server)))
  }

  /// By the host's id when both sides have one; otherwise by its name at its
  /// address — a common name alone ("Trivia Night") would hide strangers' games.
  func isBlocked(_ server: GameServer, hostID: String?) -> Bool {
    blockedHosts.contains { blocked in
      if let hostID, let blockedID = blocked.hostID { return hostID == blockedID }
      return blocked.name == server.name && blocked.address == Self.host(of: server)
    }
  }

  func unblock(_ host: BlockedHost) {
    blockedHosts.removeAll { $0.id == host.id }
  }

  private static func host(of server: GameServer) -> String {
    server.url.host() ?? server.address
  }

  // MARK: - Players, as a host

  func block(player nickname: String, device: String?) {
    blockedPlayers.append(BlockedPlayer(nickname: nickname, device: device))
  }

  /// Whether a phone or browser that joins with `device` is kept out.
  func isBarred(device: String?) -> Bool {
    guard let device, !device.isEmpty else { return false }
    return blockedPlayers.contains { $0.device == device }
  }

  func unblock(_ player: BlockedPlayer) {
    blockedPlayers.removeAll { $0.id == player.id }
  }

  // MARK: - Names, as a player

  func hide(name nickname: String) {
    guard !isHidden(nickname) else { return }
    hiddenNames.append(HiddenName(nickname: nickname))
  }

  func isHidden(_ nickname: String) -> Bool {
    hiddenNames.contains { $0.nickname.localizedCaseInsensitiveCompare(nickname) == .orderedSame }
  }

  /// `nickname`, unless it's hidden here.
  func shown(_ nickname: String) -> String {
    isHidden(nickname) ? String(localized: "Blocked player") : nickname
  }

  func unhide(_ name: HiddenName) {
    hiddenNames.removeAll { $0.id == name.id }
  }

  // MARK: - Storage

  private func save<T: Encodable>(_ value: T, _ key: String) {
    defaults?.set(try? JSONEncoder().encode(value), forKey: key)
  }

  private static func load<T: Decodable>(_ defaults: UserDefaults?, _ key: String) -> T? {
    defaults?.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
  }
}

// MARK: - Games a player can see

extension GameBrowser {
  /// The games on the network, less those of hosts this phone has blocked.
  func games(shownBy safety: Safety) -> [GameServer] {
    games.filter { !safety.isBlocked($0, hostID: hostIDs[$0.url]) }
  }
}

extension GameStore {
  /// Into the game a join link or QR code names — unless this phone blocked
  /// its host, when the join screen says why nothing happened.
  func join(_ link: JoinLink, safety: Safety, browser: GameBrowser) {
    guard !safety.isBlocked(link.server, hostID: browser.hostIDs[link.server.url]) else {
      noteBlockedHost()
      return
    }
    join(link.server, pin: link.pin)
  }
}
