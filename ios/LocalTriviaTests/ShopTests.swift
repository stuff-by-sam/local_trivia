import Foundation
import StoreKit
import StoreKitTest
import Testing

@testable import LocalTrivia

/// The shop against StoreKit's local test environment, set up from the same
/// configuration the Run scheme uses — so these also pin the catalog in code
/// to the products it sells.
@Suite(.serialized) struct ShopTests {
  let session: SKTestSession
  let defaults = UserDefaults(suiteName: "com.stuffbysam.localtrivia.tests.shop.\(UUID().uuidString)")!
  let icons = FakeIcons()

  /// One session for every test, reset before each. A session tears the test
  /// environment down when it's released, so one per test would pull it out
  /// from under the next.
  private static let shared = Result {
    try SKTestSession(
      contentsOf: URL(filePath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appending(path: "LocalTrivia/Store/Products.storekit"))
  }

  init() throws {
    session = try Self.shared.get()
    session.resetToDefaultState()
    session.disableDialogs = true
    session.clearTransactions()
  }

  private func makeShop() async -> Shop {
    let shop = Shop(defaults: defaults, icons: icons)
    await shop.loadProducts()
    return shop
  }

  private func buy(_ productID: String?, in shop: Shop) async throws {
    await shop.buy(try #require(productID)) { try await $0.purchase() }
  }

  /// Refunds a purchase, then checks again until the shop has seen it go —
  /// StoreKit takes a moment, and several seconds on a busy machine running
  /// tests in parallel. (The app's own shop is listening for the refund in
  /// this process too, so it's checked for here rather than heard.)
  private func refund(_ productID: String?, in shop: Shop) async throws {
    let productID = try #require(productID)
    let transaction = try #require(session.allTransactions().first { $0.productIdentifier == productID })
    try session.refundTransaction(identifier: transaction.identifier)
    var checks = 0
    repeat {
      try await Task.sleep(for: .milliseconds(100))
      await shop.refreshEntitlements()
      checks += 1
    } while shop.owned.contains(productID) && checks < 150
  }

  @Test func sellsEverythingInTheCatalog() async {
    let shop = await makeShop()
    #expect(shop.availability == .ready)
    #expect(Set(shop.products.keys) == Set(Shop.productIDs))
    #expect(shop.products.values.allSatisfy { $0.type == .nonConsumable })
  }

  @Test func theFreeOnesAreAlwaysOwned() async {
    let shop = await makeShop()
    await shop.refreshEntitlements()
    #expect(shop.owns(Theme.phosphor))
    #expect(shop.owns(AppIcon.classic))
    #expect(Theme.allCases.filter { !shop.owns($0) }.count == Theme.allCases.count - 1)
  }

  @Test func aThemeHasToBeBoughtBeforeItsWorn() async throws {
    let shop = await makeShop()
    shop.wear(Theme.amber)
    #expect(shop.theme == .phosphor)

    try await buy(Theme.amber.productID, in: shop)
    #expect(shop.owns(Theme.amber))
    #expect(shop.theme == .amber, "a theme goes on as soon as it's bought")
    #expect(defaults.string(forKey: "theme") == "amber")
  }

  /// A refund takes the theme off, but the choice is kept: if the purchase
  /// comes back, so does the theme.
  @Test func aRefundTakesTheThemeBack() async throws {
    let shop = await makeShop()
    try await buy(Theme.cobalt.productID, in: shop)
    #expect(shop.theme == .cobalt)

    try await refund(Theme.cobalt.productID, in: shop)
    #expect(!shop.owns(Theme.cobalt))
    #expect(shop.theme == .phosphor)
    #expect(shop.chosenTheme == .cobalt)
  }

  @Test func anIconGoesOnTheHomeScreenAndARefundTakesItOff() async throws {
    let shop = await makeShop()
    await shop.setIcon(.gold)
    #expect(icons.alternateIconName == nil, "not bought yet")

    try await buy(AppIcon.gold.productID, in: shop)
    #expect(shop.icon == .gold)
    #expect(icons.alternateIconName == "AppIcon-Gold")

    try await refund(AppIcon.gold.productID, in: shop)
    #expect(shop.icon == .classic)
    #expect(icons.alternateIconName == nil)
  }

  @Test func theBundleUnlocksEverything() async throws {
    let shop = await makeShop()
    #expect(!shop.ownsEverything)

    try await buy(Shop.everythingID, in: shop)
    #expect(shop.ownsEverything)
    #expect(Theme.allCases.allSatisfy(shop.owns))
    #expect(AppIcon.allCases.allSatisfy(shop.owns))
    #expect(shop.theme == .phosphor, "the bundle has nothing in particular to put on")

    shop.wear(Theme.noir)
    await shop.setIcon(.synthwave)
    #expect(shop.theme == .noir)
    #expect(icons.alternateIconName == "AppIcon-Synthwave")
  }

  /// Everything bought on its own counts too: nothing's left to buy.
  @Test func buyingEveryItemOwnsEverything() async throws {
    let shop = await makeShop()
    for id in Shop.productIDs where id != Shop.everythingID {
      try await buy(id, in: shop)
    }
    #expect(shop.ownsEverything)
    #expect(!shop.owned.contains(Shop.everythingID))
  }

  /// A refunded bundle takes back what came in it, and nothing bought on its own.
  @Test func aRefundedBundleKeepsWhatWasBoughtSeparately() async throws {
    let shop = await makeShop()
    try await buy(Theme.amber.productID, in: shop)
    try await buy(Shop.everythingID, in: shop)
    shop.wear(Theme.cobalt)
    await shop.setIcon(.noir)

    try await refund(Shop.everythingID, in: shop)
    #expect(shop.owns(Theme.amber))
    #expect(!shop.owns(Theme.cobalt))
    #expect(shop.theme == .phosphor)
    #expect(shop.icon == .classic)
    #expect(icons.alternateIconName == nil)
  }

  /// Ask to Buy: nothing unlocks until a parent approves, and the player is
  /// told why.
  @Test func aPendingPurchaseUnlocksNothingYet() async throws {
    session.askToBuyEnabled = true
    let shop = await makeShop()
    try await buy(Theme.noir.productID, in: shop)
    #expect(!shop.owns(Theme.noir))
    #expect(shop.theme == .phosphor)
    #expect(shop.notice != nil)
  }

  /// Cancelling is the player's choice, not an error — however StoreKit
  /// reports it. (StoreKit's test session can't throw a particular error from
  /// a purchase, so these throw their own.)
  @Test func aCancelledPurchaseSaysNothing() async throws {
    let shop = await makeShop()
    let amber = try #require(Theme.amber.productID)
    await shop.buy(amber) { _ in throw StoreKitError.userCancelled }
    #expect(!shop.owns(Theme.amber))
    #expect(shop.notice == nil)
    #expect(shop.purchasing == nil)
  }

  @Test func aPurchaseThatCantReachTheAppStoreSaysSo() async throws {
    let shop = await makeShop()
    let amber = try #require(Theme.amber.productID)
    await shop.buy(amber) { _ in throw StoreKitError.networkError(URLError(.notConnectedToInternet)) }
    #expect(!shop.owns(Theme.amber))
    #expect(shop.notice?.contains("internet connection") == true)
    #expect(shop.purchasing == nil)
  }

  /// The cache puts the theme on screen at launch; StoreKit has the last word.
  @Test func trustsTheCacheOnlyUntilStoreKitAnswers() async {
    defaults.set([Theme.synthwave.productID!], forKey: "ownedProducts")
    defaults.set("synthwave", forKey: "theme")
    let shop = Shop(defaults: defaults, icons: icons)
    #expect(shop.theme == .synthwave)

    await shop.refreshEntitlements()
    #expect(shop.theme == .phosphor, "nothing was ever bought")
  }

  /// Every alternate icon is built into the app under the name the shop sets.
  @Test func everyAlternateIconIsInTheApp() throws {
    let icons = try #require(Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any])
    let alternates = try #require(icons["CFBundleAlternateIcons"] as? [String: Any])
    for icon in AppIcon.allCases {
      guard let name = icon.alternateName else { continue }
      #expect(alternates[name] != nil, "\(name) isn't in the app")
      #expect(AppIcon(alternateName: name) == icon)
    }
  }
}

/// Keeps the icon to itself rather than changing the simulator's.
final class FakeIcons: IconSwitcher {
  var supportsAlternateIcons: Bool { true }
  private(set) var alternateIconName: String?

  func setAlternateIconName(_ name: String?) async throws {
    alternateIconName = name
  }
}
