import Foundation
import OSLog
import Security

/// Where the resume token lives.
///
/// The token is a bearer credential: whoever presents it takes over this
/// player's seat — name, score, the answer they're about to give. So it's kept
/// in the Keychain rather than preferences: on this device only, never copied
/// into a backup or onto a new phone, and unreadable while the phone is locked.
nonisolated protocol TokenStore: Sendable {
  func load() -> String?
  func save(_ token: String?)
}

nonisolated struct KeychainTokenStore: TokenStore {
  var service = "com.stuffbysam.localtrivia.session"
  var account = "resume-token"

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "keychain")

  func load() -> String? {
    var query = identity
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      if status != errSecItemNotFound { Self.log.error("token read failed: \(status, privacy: .public)") }
      return nil
    }
    return String(data: data, encoding: .utf8)
  }

  func save(_ token: String?) {
    let cleared = SecItemDelete(identity as CFDictionary)
    if cleared != errSecSuccess, cleared != errSecItemNotFound {
      Self.log.error("token delete failed: \(cleared, privacy: .public)")
    }
    guard let token else { return }
    var item = identity
    item[kSecValueData as String] = Data(token.utf8)
    // Only while unlocked, and never leaves this device.
    item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    let added = SecItemAdd(item as CFDictionary, nil)
    if added != errSecSuccess { Self.log.error("token write failed: \(added, privacy: .public)") }
  }

  private var identity: [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }
}
