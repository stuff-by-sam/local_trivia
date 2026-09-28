import Foundation
import Security
import Testing

@testable import LocalTrivia

/// Runs against the real Keychain, under a service name of its own.
@Suite struct KeychainTokenStoreTests {
  let store = KeychainTokenStore(service: "com.stuffbysam.localtrivia.tests.\(UUID().uuidString)")

  @Test func storesReplacesAndClears() {
    #expect(store.load() == nil)
    store.save("tok-1")
    #expect(store.load() == "tok-1")
    store.save("tok-2")  // replaces rather than adding a second item
    #expect(store.load() == "tok-2")
    store.save(nil)
    #expect(store.load() == nil)
  }

  /// Device-only and unlocked-only: never in a backup, never on a new phone.
  @Test func staysOnThisDevice() throws {
    store.save("tok-1")
    defer { store.save(nil) }
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: store.service,
      kSecAttrAccount as String: store.account,
      kSecReturnAttributes as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var item: CFTypeRef?
    #expect(SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess)
    let attributes = try #require(item as? [String: Any])
    #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
  }
}
