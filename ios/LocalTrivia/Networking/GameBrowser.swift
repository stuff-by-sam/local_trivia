import Foundation
import Network
import Observation
import OSLog

/// Lists games hosted from phones on the local network (see `HostServer`), so
/// joining never starts with typing an IP address. Games are only ever hosted
/// from a phone, and only a hosting phone advertises this type.
@Observable
final class GameBrowser {
  nonisolated static let serviceType = "_trivia-phone._tcp"

  private(set) var games: [GameServer] = []
  /// Set when browsing stopped working — often because Local Network access
  /// is off for the app — so the join screen can say so instead of looking
  /// forever.
  private(set) var hasFailed = false
  /// Looked long enough that a game missing from `games` isn't being
  /// advertised: its host has stopped hosting it.
  private(set) var hasSettled = false
  @ObservationIgnored private var browsing: Task<Void, Never>?
  @ObservationIgnored private var settling: Task<Void, Never>?

  /// Every host on the network has answered well within this.
  nonisolated static let settleTime: Duration = .seconds(3)

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "discovery")

  func start() {
    guard browsing == nil else { return }
    hasFailed = false
    hasSettled = false
    settling = Task { [weak self] in
      try? await Task.sleep(for: Self.settleTime)
      guard !Task.isCancelled, let self, !self.hasFailed else { return }
      self.hasSettled = true
    }
    browsing = Task { [weak self] in
      let browser = NetworkBrowser(for: .bonjour(Self.serviceType, includeTxtRecord: true))
      do {
        try await browser.run { [weak self] endpoints in
          self?.games = Self.games(from: endpoints)
        }
      } catch {
        // Stopped on purpose — a game started — isn't a failure to report.
        guard !Task.isCancelled else { return }
        Self.log.error("browse failed: \(error.localizedDescription, privacy: .public)")
        self?.hasFailed = true
        self?.hasSettled = false
      }
    }
  }

  func stop() {
    browsing?.cancel()
    browsing = nil
    settling?.cancel()
    settling = nil
    hasSettled = false
  }

  /// A host on more than one interface advertises once per interface; the
  /// player should see one game. The TXT record's `url` is the same address
  /// the host's QR code encodes.
  nonisolated static func games(from endpoints: [Bonjour.Endpoint]) -> [GameServer] {
    var seen = Set<String>()
    return endpoints
      .compactMap { endpoint -> GameServer? in
        guard case .string(let url)? = endpoint.txtRecord.getEntry(for: "url"),
          let game = GameServer(address: url, name: endpoint.name),
          seen.insert(game.name).inserted
        else { return nil }
        return game
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}
