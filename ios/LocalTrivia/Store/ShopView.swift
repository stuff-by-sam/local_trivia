import StoreKit
import SwiftUI

/// Themes and app icons: try a theme on, buy it, wear it.
///
/// Out of the way on purpose — a quiet link under Host a Game — because the
/// game is the point. Tapping a theme this phone doesn't own dresses the
/// shop in it, so it's tried on before it's bought; closing the shop takes
/// it off again.
struct ShopView: View {
  @Environment(Shop.self) private var shop
  @Environment(\.purchase) private var purchase
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize

  /// A theme being tried on, not yet owned.
  @State private var trying: Theme?
  /// The shop's last notice, held here so the alert keeps its words while it
  /// animates away.
  @State private var alert = ""
  @State private var isAlerting = false

  private var shown: Theme { trying ?? shop.theme }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Showcase(theme: shown, isTryingOn: !shop.owns(shown))
        }
        .listRowBackground(Color.clear)

        if !shop.ownsEverything {
          Section {
            EverythingOffer { buy(Shop.everythingID) }
          }
          .listRowBackground(RowBackground())
        }

        themes

        if shop.canChangeIcon {
          icons
        }

        Section {
          Button {
            Task { await shop.restore() }
          } label: {
            HStack {
              Text("Restore Purchases")
              Spacer()
              if shop.isRestoring { ProgressView() }
            }
          }
          .disabled(shop.isRestoring)
        } footer: {
          Text("Bought them on another device, or reinstalled Trivia? Restoring brings back everything this Apple Account owns.")
        }
        .listRowBackground(RowBackground())
      }
      .scrollContentBackground(.hidden)
      .background { Backdrop(mood: .idle, accent: shown.accent) }
      .navigationTitle("Themes & Icons")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .alert(Text(verbatim: alert), isPresented: $isAlerting) {
        Button("OK") {}
      }
    }
    .theme(shown)
    .tint(shown.accent)
    .animation(.smooth, value: shown)
    .preferredColorScheme(.dark)
    .onChange(of: shop.notice) { _, notice in
      guard let notice else { return }
      alert = notice
      isAlerting = true
      shop.notice = nil
    }
    // The theme being tried on is now owned — bought on its own, in the
    // bundle, or approved by a parent — so it goes on for real.
    .onChange(of: shop.owned) {
      if let trying, shop.owns(trying) { shop.wear(trying) }
    }
    // Whatever was just put on is what the shop shows.
    .onChange(of: shop.theme) {
      trying = nil
    }
  }

  // MARK: - Themes

  private var themes: some View {
    Section {
      if shop.availability == .unavailable {
        StoreUnavailable()
      }
      ForEach(Theme.allCases) { theme in
        ThemeRow(theme: theme, isShown: theme == shown) {
          if shop.owns(theme) {
            trying = nil
            shop.wear(theme)
          } else {
            trying = theme
          }
        } onBuy: {
          buy(theme.productID)
        }
      }
    } header: {
      SectionHeader("Themes")
    } footer: {
      Text("A theme dresses this phone, and any TV it puts the game on. Answers keep their colours and shapes on every phone, so B is always the cyan triangle.")
    }
    .listRowBackground(RowBackground())
  }

  // MARK: - Icons

  private var icons: some View {
    Section {
      LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 150 : 88), spacing: 12)], spacing: 18) {
        ForEach(AppIcon.allCases) { icon in
          IconTile(icon: icon) {
            if shop.owns(icon) {
              Task { await shop.setIcon(icon) }
            } else {
              buy(icon.productID)
            }
          }
        }
      }
      .padding(.vertical, 10)
    } header: {
      SectionHeader("App Icons")
    } footer: {
      Text("Changes Trivia's icon on your Home Screen.")
    }
    .listRowBackground(RowBackground())
  }

  private func buy(_ productID: String?) {
    guard let productID else { return }
    Task { await shop.buy(productID) { try await purchase($0) } }
  }
}

/// The theme on show, drawn the way the join screen draws itself.
private struct Showcase: View {
  let theme: Theme
  let isTryingOn: Bool

  var body: some View {
    VStack(spacing: 18) {
      HStack(spacing: 14) {
        ForEach(AnswerStyle.allCases) { style in
          Image(systemName: style.symbol)
            .foregroundStyle(style.color)
        }
      }
      .font(.subheadline)
      .padding(.horizontal, 16)
      .padding(.vertical, 9)
      .glassEffect(in: .capsule)

      HStack(spacing: 0) {
        Text(verbatim: "TRIVIA")
          .tracking(5)
        BlinkingCursor(glyph: "█")
      }
      .font(.mono(size: 34, weight: .heavy))
      .foregroundStyle(theme.accent)
      .shadow(color: theme.accent.opacity(0.45), radius: 12)

      HStack(spacing: 10) {
        Text("Join Game")
        Image(systemName: "arrow.right")
      }
      .terminalStyle(.subheadline, weight: .bold)
      .foregroundStyle(Color.broadcastInk)
      .padding(.horizontal, 28)
      .frame(minHeight: 44)
      .glassEffect(.regular.tint(theme.accent), in: .capsule)

      VStack(spacing: 6) {
        StatusLine(isTryingOn ? "Trying on \(String(localized: theme.name))" : "Wearing \(String(localized: theme.name))")
        Text(theme.tagline)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(
      isTryingOn
        ? Text("Trying on \(String(localized: theme.name)). \(String(localized: theme.tagline))")
        : Text("Wearing \(String(localized: theme.name)). \(String(localized: theme.tagline))"))
  }
}

private struct ThemeRow: View {
  let theme: Theme
  let isShown: Bool
  let onSelect: () -> Void
  let onBuy: () -> Void

  @Environment(Shop.self) private var shop
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    OfferLayout(isStacked: typeSize.isAccessibilitySize) {
      Button(action: onSelect) {
        HStack(spacing: 14) {
          Swatch(theme: theme, isShown: isShown)
          VStack(alignment: .leading, spacing: 3) {
            Text(theme.name)
              .font(.body.weight(.semibold))
              .foregroundStyle(.primary)
            Text(theme.tagline)
              .font(.footnote)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityHint(shop.owns(theme) ? "Wears this theme." : "Tries this theme on.")

      if shop.theme == theme {
        Image(systemName: "checkmark")
          .font(.body.weight(.bold))
          .foregroundStyle(theme.accent)
          .accessibilityLabel("In use")
      } else if shop.owns(theme) {
        Text("Owned")
          .terminalStyle(.caption2)
          .foregroundStyle(.secondary)
      } else if let productID = theme.productID {
        PriceButton(productID: productID, name: theme.name, action: onBuy)
      }
    }
    .padding(.vertical, 4)
  }
}

/// An offer and its price: side by side, or — at accessibility text sizes,
/// where sharing a line would squeeze the words to a letter a line — the
/// price underneath.
private struct OfferLayout<Content: View>: View {
  let isStacked: Bool
  @ViewBuilder var content: Content

  var body: some View {
    let layout = isStacked
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
      : AnyLayout(HStackLayout(spacing: 14))
    layout { content }
  }
}

/// A theme in miniature: its own backdrop, and its cursor.
private struct Swatch: View {
  let theme: Theme
  let isShown: Bool

  var body: some View {
    Backdrop(mood: .idle, accent: theme.accent)
      .theme(theme)
      .overlay {
        Text(verbatim: "█")
          .font(.mono(size: 18, weight: .heavy))
          .foregroundStyle(theme.accent)
          .shadow(color: theme.accent.opacity(0.6), radius: 6)
      }
      .frame(width: 52, height: 52)
      .clipShape(.rect(cornerRadius: 12))
      .overlay {
        RoundedRectangle(cornerRadius: 12)
          .strokeBorder(isShown ? theme.accent.opacity(0.8) : .white.opacity(0.12), lineWidth: isShown ? 1.5 : 1)
      }
      .accessibilityHidden(true)
  }
}

/// The App Store's price for a product, as the button that buys it.
private struct PriceButton: View {
  let productID: String
  let name: LocalizedStringResource
  /// Lit with the accent, for the one offer that should stand out.
  var isProminent = false
  let action: () -> Void

  @Environment(Shop.self) private var shop
  @Environment(\.accent) private var accent

  var body: some View {
    Group {
      if shop.purchasing == productID {
        ProgressView()
      } else if let product = shop.products[productID] {
        let button = Button(action: action) {
          Text(verbatim: product.displayPrice)
            .font(.mono(.subheadline, weight: .bold))
            .foregroundStyle(isProminent ? Color.broadcastInk : accent)
        }
        .disabled(shop.purchasing != nil)
        .accessibilityLabel(Text("Buy \(String(localized: name)), \(product.displayPrice)"))
        if isProminent {
          button
            .buttonStyle(.glassProminent)
            .tint(accent)
        } else {
          button.buttonStyle(.glass)
        }
      } else if shop.availability == .loading {
        ProgressView()
      } else {
        Image(systemName: "lock.fill")
          .foregroundStyle(.tertiary)
          .accessibilityLabel("Not available right now")
      }
    }
    .frame(minWidth: 44, minHeight: 44)
  }
}

/// Every theme and icon in one purchase.
private struct EverythingOffer: View {
  let onBuy: () -> Void

  private static let themes = Theme.allCases.filter { $0.productID != nil }.count
  private static let icons = AppIcon.allCases.filter { $0.productID != nil }.count

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    OfferLayout(isStacked: typeSize.isAccessibilitySize) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Everything")
          .font(.body.weight(.semibold))
        Text("All ^[\(Self.themes) theme](inflect: true) and ^[\(Self.icons) app icon](inflect: true)")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)

      PriceButton(productID: Shop.everythingID, name: "Everything", isProminent: true, action: onBuy)
    }
    .padding(.vertical, 4)
  }
}

/// One icon, and what tapping it does: put it on, or buy it.
private struct IconTile: View {
  let icon: AppIcon
  let action: () -> Void

  @Environment(Shop.self) private var shop
  @Environment(\.accent) private var accent

  var body: some View {
    let isWorn = shop.icon == icon
    Button(action: action) {
      VStack(spacing: 8) {
        AppIcon.Artwork(icon: icon, size: 64)
          .overlay {
            RoundedRectangle(cornerRadius: 64 * 0.225 + 4, style: .continuous)
              .strokeBorder(accent, lineWidth: 2)
              .padding(-4)
              .opacity(isWorn ? 1 : 0)
          }
        Text(icon.name)
          .font(.footnote.weight(.semibold))
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        status
          .font(.mono(.caption, weight: .bold))
          .frame(minHeight: 16)
      }
      .frame(maxWidth: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .disabled(shop.purchasing != nil || (!shop.owns(icon) && shop.products[icon.productID ?? ""] == nil))
    .accessibilityLabel(Text("\(String(localized: icon.name)) icon"))
    .accessibilityValue(accessibilityStatus)
    .accessibilityAddTraits(isWorn ? .isSelected : [])
  }

  @ViewBuilder
  private var status: some View {
    if shop.icon == icon {
      Image(systemName: "checkmark")
        .foregroundStyle(accent)
    } else if shop.owns(icon) {
      Text("Owned")
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
    } else if let productID = icon.productID, shop.purchasing == productID {
      ProgressView()
        .controlSize(.mini)
    } else if let productID = icon.productID, let product = shop.products[productID] {
      Text(verbatim: product.displayPrice)
        .foregroundStyle(accent)
    } else {
      Image(systemName: "lock.fill")
        .foregroundStyle(.tertiary)
    }
  }

  private var accessibilityStatus: Text {
    if shop.icon == icon { return Text("In use") }
    if shop.owns(icon) { return Text("Owned") }
    if let productID = icon.productID, let product = shop.products[productID] { return Text(verbatim: product.displayPrice) }
    return Text("Not available right now")
  }
}

/// No prices without the App Store — but what's owned keeps working.
private struct StoreUnavailable: View {
  @Environment(Shop.self) private var shop

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label("Can't reach the App Store. What you own still works offline.", systemImage: "wifi.slash")
        .font(.footnote)
        .foregroundStyle(Color.broadcastGold)
      Button("Try Again") {
        Task { await shop.loadProducts() }
      }
      .font(.footnote.weight(.semibold))
      .buttonStyle(.borderless)
    }
    .padding(.vertical, 4)
  }
}
