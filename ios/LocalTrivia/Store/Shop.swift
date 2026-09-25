import DesignSystem
import Observation
import OSLog
import StoreKit
import UIKit

/// Themes and app icons, sold as non-consumable in-app purchases — one at a
/// time, or all at once (`everythingID`).
///
/// StoreKit's verified entitlements are the record of what this phone owns;
/// nothing is unlocked on the app's say-so. The last answer is cached in
/// preferences so a chosen theme is on screen from the first frame, rather
/// than green until StoreKit replies, and every launch asks again, so a
/// refund takes the theme back. Entitlements are kept on the device, so what
/// was bought works offline — only buying needs the App Store.
///
/// Choosing and owning are kept apart: `chosenTheme` is what the player picked,
/// `theme` is what they're entitled to wear. A theme that's taken back returns
/// by itself if the purchase does (restored, or approved by a parent).
@Observable
final class Shop {
  enum Availability: Equatable {
    case loading
    case ready
    /// The App Store couldn't be reached, or sells nothing here.
    case unavailable
  }

  /// What the App Store sells, by product ID. Empty until it answers.
  private(set) var products: [String: Product] = [:]
  private(set) var availability: Availability = .loading
  /// Product IDs this Apple Account owns.
  private(set) var owned: Set<String> {
    didSet { defaults.set(owned.sorted(), forKey: Keys.owned) }
  }
  /// The product whose purchase sheet is up.
  private(set) var purchasing: String?
  private(set) var isRestoring = false
  /// What happened to the last purchase or restore, when there's news.
  var notice: String?

  private(set) var chosenTheme: Theme {
    didSet { defaults.set(chosenTheme.rawValue, forKey: Keys.theme) }
  }
  /// What the home screen shows. Read when the shop starts: iOS keeps it.
  private(set) var icon: AppIcon = .classic

  /// What the app is drawn in: the chosen theme, while it's owned.
  var theme: Theme { owns(chosenTheme) ? chosenTheme : .phosphor }

  var canChangeIcon: Bool { icons.supportsAlternateIcons }

  /// The bundle: every theme and icon, including ones added later.
  static let everythingID = "com.stuffbysam.localtrivia.bundle.everything"

  static let productIDs = Theme.allCases.compactMap(\.productID) + AppIcon.allCases.compactMap(\.productID) + [everythingID]

  /// Whether the bundle, or every item in it, is owned: nothing left to buy.
  var ownsEverything: Bool {
    Theme.allCases.allSatisfy(owns) && AppIcon.allCases.allSatisfy(owns)
  }

  /// How a product is bought: SwiftUI's `purchase` action from the shop's
  /// view, which knows which scene to present the App Store's sheet over.
  typealias Purchase = (Product) async throws -> Product.PurchaseResult

  @ObservationIgnored private let defaults: UserDefaults
  @ObservationIgnored private let icons: any IconSwitcher
  @ObservationIgnored private var updates: Task<Void, Never>?
  /// Bumped by every entitlement check and every purchase. A check only
  /// writes what it found if nothing has happened since it began, so a slow
  /// one can't undo a purchase that landed while it was reading.
  @ObservationIgnored private var ownershipVersion = 0

  private static let log = Logger(subsystem: "com.stuffbysam.localtrivia", category: "shop")

  private enum Keys {
    static let owned = "ownedProducts"
    static let theme = "theme"
  }

  init(defaults: UserDefaults = .standard, icons: any IconSwitcher = HomeScreen()) {
    self.defaults = defaults
    self.icons = icons
    owned = Set(defaults.stringArray(forKey: Keys.owned) ?? [])
    chosenTheme = defaults.string(forKey: Keys.theme).flatMap(Theme.init(rawValue:)) ?? .phosphor
  }

  func owns(_ theme: Theme) -> Bool { owns(theme.productID) }
  func owns(_ icon: AppIcon) -> Bool { owns(icon.productID) }

  /// Free (no product), bought on its own, or in the bundle.
  private func owns(_ productID: String?) -> Bool {
    guard let productID else { return true }
    return owned.contains(productID) || owned.contains(Self.everythingID)
  }

  // MARK: - StoreKit

  /// Listens for transactions made outside the app — Ask to Buy approvals,
  /// refunds, purchases on another device — and checks what's owned. What's
  /// for sale is asked only when the shop opens (`loadProductsIfNeeded`):
  /// most launches never go near it.
  func start() {
    guard updates == nil else { return }
    icon = AppIcon(alternateName: icons.alternateIconName)
    updates = Task { [weak self] in
      for await update in Transaction.updates {
        guard let self else { return }
        if case .verified(let transaction) = update { await transaction.finish() }
        await refreshEntitlements()
      }
    }
    Task { await refreshEntitlements() }
  }

  /// Asks the App Store what's for sale, unless it already answered.
  func loadProductsIfNeeded() async {
    guard availability != .ready else { return }
    await loadProducts()
  }

  func loadProducts() async {
    availability = .loading
    do {
      let found = try await Product.products(for: Self.productIDs)
      products = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
      availability = found.isEmpty ? .unavailable : .ready
    } catch {
      Self.log.error("couldn't load products: \(error.localizedDescription, privacy: .public)")
      availability = .unavailable
    }
  }

  /// Replaces what's owned with what StoreKit can verify, and takes a
  /// refunded icon off the home screen.
  func refreshEntitlements() async {
    ownershipVersion += 1
    let version = ownershipVersion
    var verified: Set<String> = []
    for await entitlement in Transaction.currentEntitlements {
      guard case .verified(let transaction) = entitlement, transaction.revocationDate == nil else { continue }
      verified.insert(transaction.productID)
    }
    // Something newer has happened; its answer, or the next check's, stands.
    guard version == ownershipVersion else { return }
    owned = verified
    if !owns(icon) { await setIcon(.classic) }
  }

  /// Buys a product and, once it's verified, puts it on.
  func buy(_ productID: String, with purchase: Purchase) async {
    guard let product = products[productID], purchasing == nil else { return }
    purchasing = productID
    notice = nil
    defer { purchasing = nil }

    let result: Product.PurchaseResult
    do {
      result = try await purchase(product)
    } catch StoreKitError.userCancelled {
      return
    } catch {
      Self.log.error("purchase failed: \(error.localizedDescription, privacy: .public)")
      notice = Self.describe(error)
      return
    }

    switch result {
    case .success(.verified(let transaction)):
      ownershipVersion += 1
      owned.insert(transaction.productID)
      await transaction.finish()
      if let theme = Theme.allCases.first(where: { $0.productID == transaction.productID }) {
        wear(theme)
      } else if let icon = AppIcon.allCases.first(where: { $0.productID == transaction.productID }) {
        await setIcon(icon)
      }
    case .success(.unverified(_, let failure)):
      Self.log.error("unverified purchase: \(failure.localizedDescription, privacy: .public)")
      notice = String(localized: "The App Store couldn't confirm that purchase, so it hasn't been unlocked.")
    case .pending:
      notice = String(localized: "Waiting for approval. It'll unlock here once it's approved.")
    case .userCancelled:
      break
    @unknown default:
      break
    }
  }

  /// Asks the App Store for everything this Apple Account has bought. It may
  /// ask the player to sign in.
  func restore() async {
    guard !isRestoring else { return }
    isRestoring = true
    notice = nil
    defer { isRestoring = false }
    do {
      try await AppStore.sync()
    } catch StoreKitError.userCancelled {
      return
    } catch {
      Self.log.error("restore failed: \(error.localizedDescription, privacy: .public)")
      notice = Self.describe(error)
      return
    }
    await refreshEntitlements()
    notice = owned.isEmpty
      ? String(localized: "This Apple Account hasn't bought any themes or icons yet.")
      : String(localized: "Your themes and icons are restored.")
  }

  // MARK: - Wearing

  func wear(_ theme: Theme) {
    guard owns(theme) else { return }
    chosenTheme = theme
  }

  /// Changes the home screen icon. iOS tells the player it has.
  func setIcon(_ icon: AppIcon) async {
    guard owns(icon), icons.supportsAlternateIcons else { return }
    guard icon.alternateName != icons.alternateIconName else {
      self.icon = icon
      return
    }
    do {
      try await icons.setAlternateIconName(icon.alternateName)
      self.icon = icon
    } catch {
      Self.log.error("couldn't change the icon: \(error.localizedDescription, privacy: .public)")
      notice = String(localized: "Couldn't change the icon. Try again in a moment.")
    }
  }

  private static func describe(_ error: any Error) -> String {
    if case StoreKitError.networkError = error {
      return String(localized: "Couldn't reach the App Store. Check your internet connection and try again.")
    }
    return String(localized: "The App Store couldn't complete that. Try again in a moment.")
  }
}

/// Where the home screen icon is set: the app itself, or a stand-in in tests.
protocol IconSwitcher {
  var supportsAlternateIcons: Bool { get }
  var alternateIconName: String? { get }
  func setAlternateIconName(_ name: String?) async throws
}

/// The app's own icon. It asks UIKit each time rather than holding on to the
/// application: the shop is made before UIKit has finished launching the app.
struct HomeScreen: IconSwitcher {
  var supportsAlternateIcons: Bool { UIApplication.shared.supportsAlternateIcons }
  var alternateIconName: String? { UIApplication.shared.alternateIconName }

  func setAlternateIconName(_ name: String?) async throws {
    try await UIApplication.shared.setAlternateIconName(name)
  }
}

#if DEBUG
extension Shop {
  /// A shop that never asks the App Store — it answers that it's ready, with
  /// nothing priced — for previews.
  static func preview(defaults: UserDefaults) -> Shop {
    let shop = Shop(defaults: defaults, icons: PreviewIcons())
    shop.availability = .ready
    return shop
  }
}

private struct PreviewIcons: IconSwitcher {
  var supportsAlternateIcons: Bool { true }
  var alternateIconName: String? { nil }
  func setAlternateIconName(_ name: String?) async throws {}
}
#endif
