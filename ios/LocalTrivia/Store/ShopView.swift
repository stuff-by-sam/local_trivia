import DesignSystem
import StoreKit
import SwiftUI

/// Themes, app icons and answer markers: try one on, buy it, wear it.
///
/// Out of the way on purpose — a toolbar button on the join screen — because
/// the game is the point. Each kind is a group that opens when it's wanted.
/// Tapping a theme or a marker set this phone doesn't own dresses the shop in
/// it, so it's tried on before it's bought; closing the shop takes it off
/// again.
struct ShopView: View {
  @Environment(Shop.self) private var shop
  @Environment(\.purchase) private var purchase
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize

  /// A theme being tried on, not yet owned.
  @State private var trying: Theme?
  /// A marker set being tried on, not yet owned.
  @State private var tryingMarkers: AnswerMarkers?
  @State private var showsThemes = false
  @State private var showsIcons = false
  @State private var showsMarkers = false
  /// The shop's last notice, held here so the alert keeps its words while it
  /// animates away.
  @State private var alert = ""
  @State private var isAlerting = false

  private var shown: Theme { trying ?? shop.theme }
  private var shownMarkers: AnswerMarkers { tryingMarkers ?? shop.markers }

  var body: some View {
    NavigationStack {
      List {
        Section {
          Showcase(theme: shown, trying: trying, tryingMarkers: tryingMarkers)
        }
        .listRowBackground(Color.clear)

        if !shop.ownsEverything {
          Section {
            EverythingOffer { buy(Shop.everythingID) }
          }
        }

        if shop.availability == .unavailable {
          Section {
            StoreUnavailable()
          }
        }

        themes

        if shop.canChangeIcon {
          icons
        }

        markers

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
      }
      // The one sheet that shows the backdrop: trying a theme on is the point.
      .scrollContentBackground(.hidden)
      .background { Backdrop(mood: .idle) }
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
    .environment(\.answerMarkers, shownMarkers)
    .motion(.settle, value: shown)
    .motion(.settle, value: shownMarkers)
    .task { await shop.loadProductsIfNeeded() }
    .onChange(of: shop.notice) { _, notice in
      guard let notice else { return }
      alert = notice
      isAlerting = true
      shop.notice = nil
    }
    // What's being tried on is now owned — bought on its own, in the bundle,
    // or approved by a parent — so it goes on for real.
    .onChange(of: shop.owned) {
      if let trying, shop.owns(trying) { shop.wear(trying) }
      if let tryingMarkers, shop.owns(tryingMarkers) { shop.wear(tryingMarkers) }
    }
    // Whatever was just put on is what the shop shows.
    .onChange(of: shop.theme) {
      trying = nil
    }
    .onChange(of: shop.markers) {
      tryingMarkers = nil
    }
  }

  // MARK: - Themes

  private var themes: some View {
    Section {
      DisclosureGroup(isExpanded: $showsThemes) {
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
      } label: {
        GroupLabel("Themes", current: shop.theme.name) {
          ThemeSwatch(theme: shop.theme, isShown: false)
        }
      }
    } footer: {
      Text("A theme dresses this phone, any TV it puts the game on, and the browsers in a game it hosts.")
    }
  }

  // MARK: - Icons

  private var icons: some View {
    Section {
      DisclosureGroup(isExpanded: $showsIcons) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.iconTile * (typeSize.isAccessibilitySize ? 2.4 : 1.4)), spacing: Space.m)], spacing: Space.l) {
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
        .padding(.vertical, Space.s)
      } label: {
        GroupLabel("App Icons", current: shop.icon.name) {
          IconArtwork(shop.icon.design, size: Size.swatch)
        }
      }
    } footer: {
      Text("Changes Trivia's icon on your Home Screen.")
    }
  }

  // MARK: - Markers

  private var markers: some View {
    Section {
      DisclosureGroup(isExpanded: $showsMarkers) {
        ForEach(AnswerMarkers.allCases) { markers in
          MarkerRow(markers: markers, isShown: markers == shownMarkers) {
            if shop.owns(markers) {
              tryingMarkers = nil
              shop.wear(markers)
            } else {
              tryingMarkers = markers
            }
          } onBuy: {
            buy(markers.productID)
          }
        }
      } label: {
        GroupLabel("Answer Markers", current: shop.markers.name) {
          MarkerSwatch(markers: shop.markers, isShown: false)
        }
      }
    } footer: {
      Text("The shapes beside each answer's letter, on this phone and any TV it puts the game on. Letters and colours stay the same on every phone, so B is always cyan.")
    }
  }

  private func buy(_ productID: String?) {
    guard let productID else { return }
    Task { await shop.buy(productID) { try await purchase($0) } }
  }
}

/// What's on show, drawn the way the join screen draws itself: the theme,
/// and the answer markers above the wordmark.
private struct Showcase: View {
  let theme: Theme
  /// What's being tried on and isn't owned yet, if anything.
  let trying: Theme?
  let tryingMarkers: AnswerMarkers?

  var body: some View {
    VStack(spacing: Space.l) {
      AnswerSetMark()
        .font(.subheadline)
      Wordmark(scale: .showcase)
      VStack(spacing: Space.xs) {
        StatusLine(verbatim: status)
        Text(tagline)
          .textRole(.detail)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Space.s)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: "\(status). \(String(localized: tagline))"))
  }

  private var status: String {
    switch (trying, tryingMarkers) {
    case let (theme?, markers?): String(localized: "Trying on \(String(localized: theme.name)) with \(String(localized: markers.name))")
    case let (theme?, nil): String(localized: "Trying on \(String(localized: theme.name))")
    case let (nil, markers?): String(localized: "Trying on \(String(localized: markers.name))")
    case (nil, nil): String(localized: "Wearing \(String(localized: theme.name))")
    }
  }

  /// What's being tried on says what it is; otherwise the theme does.
  private var tagline: LocalizedStringResource {
    if trying == nil, let tryingMarkers { tryingMarkers.tagline } else { theme.tagline }
  }
}

/// A group's row while it's closed: what's in it, and what's on now.
private struct GroupLabel<Artwork: View>: View {
  let title: LocalizedStringKey
  let current: LocalizedStringResource
  @ViewBuilder var artwork: Artwork

  init(_ title: LocalizedStringKey, current: LocalizedStringResource, @ViewBuilder artwork: () -> Artwork) {
    self.title = title
    self.current = current
    self.artwork = artwork()
  }

  var body: some View {
    HStack(spacing: Space.m) {
      artwork
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(title)
          .textRole(.bodyEmphasis)
          .foregroundStyle(.primary)
        Text(current)
          .textRole(.detail)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.vertical, Space.xs)
    .accessibilityElement(children: .combine)
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
        HStack(spacing: Space.m) {
          ThemeSwatch(theme: theme, isShown: isShown)
          VStack(alignment: .leading, spacing: Space.xxs) {
            Text(theme.name)
              .textRole(.bodyEmphasis)
              .foregroundStyle(.primary)
            Text(theme.tagline)
              .textRole(.detail)
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
          .fontWeight(.bold)
          .foregroundStyle(theme.accent)
          .accessibilityLabel("In use")
      } else if shop.owns(theme) {
        Text("Owned")
          .textRole(.labelSmall)
          .foregroundStyle(.secondary)
      } else if let productID = theme.productID {
        PriceButton(productID: productID, name: theme.name, action: onBuy)
      }
    }
    .padding(.vertical, Space.xs)
  }
}

private struct MarkerRow: View {
  let markers: AnswerMarkers
  let isShown: Bool
  let onSelect: () -> Void
  let onBuy: () -> Void

  @Environment(Shop.self) private var shop
  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    OfferLayout(isStacked: typeSize.isAccessibilitySize) {
      Button(action: onSelect) {
        HStack(spacing: Space.m) {
          MarkerSwatch(markers: markers, isShown: isShown)
          VStack(alignment: .leading, spacing: Space.xxs) {
            Text(markers.name)
              .textRole(.bodyEmphasis)
              .foregroundStyle(.primary)
            Text(markers.tagline)
              .textRole(.detail)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityHint(shop.owns(markers) ? "Uses these markers." : "Tries these markers on.")

      if shop.markers == markers {
        Image(systemName: "checkmark")
          .fontWeight(.bold)
          .foregroundStyle(.themeAccent)
          .accessibilityLabel("In use")
      } else if shop.owns(markers) {
        Text("Owned")
          .textRole(.labelSmall)
          .foregroundStyle(.secondary)
      } else if let productID = markers.productID {
        PriceButton(productID: productID, name: markers.name, action: onBuy)
      }
    }
    .padding(.vertical, Space.xs)
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
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.s))
      : AnyLayout(HStackLayout(spacing: Space.m))
    layout { content }
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

  var body: some View {
    Group {
      if shop.purchasing == productID {
        ProgressView()
      } else if let product = shop.products[productID] {
        let button = Button(action: action) {
          Text(verbatim: product.displayPrice)
            .textRole(.figure)
            .foregroundStyle(isProminent ? AnyShapeStyle(.onAccent) : AnyShapeStyle(.themeAccent))
        }
        .disabled(shop.purchasing != nil)
        .accessibilityLabel(Text("Buy \(String(localized: name)), \(product.displayPrice)"))
        if isProminent {
          button.buttonStyle(.glassProminent)
        } else {
          button.buttonStyle(.glass)
        }
      } else if shop.availability == .loading {
        ProgressView()
      } else {
        Image(systemName: "lock.fill")
          .foregroundStyle(.secondary)
          .accessibilityLabel("Not available right now")
      }
    }
    .frame(minWidth: Size.target, minHeight: Size.target)
  }
}

/// Every theme, icon and marker set in one purchase.
private struct EverythingOffer: View {
  let onBuy: () -> Void

  private static let themes = Theme.allCases.filter { $0.productID != nil }.count
  private static let icons = AppIcon.allCases.filter { $0.productID != nil }.count
  private static let markers = AnswerMarkers.allCases.filter { $0.productID != nil }.count

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    OfferLayout(isStacked: typeSize.isAccessibilitySize) {
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text("Everything")
          .textRole(.bodyEmphasis)
        Text("All ^[\(Self.themes) theme](inflect: true), ^[\(Self.icons) app icon](inflect: true) and ^[\(Self.markers) set](inflect: true) of answer markers")
          .textRole(.detail)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)

      PriceButton(productID: Shop.everythingID, name: "Everything", isProminent: true, action: onBuy)
    }
    .padding(.vertical, Space.xs)
  }
}

/// One icon, and what tapping it does: put it on, or buy it.
private struct IconTile: View {
  let icon: AppIcon
  let action: () -> Void

  @Environment(Shop.self) private var shop

  var body: some View {
    let isWorn = shop.icon == icon
    Button(action: action) {
      VStack(spacing: Space.s) {
        IconArtwork(icon.design)
          .overlay {
            RoundedRectangle(cornerRadius: Size.iconTile * IconArtwork.cornerRatio + Space.xs, style: .continuous)
              .strokeBorder(.themeAccent, lineWidth: 2)
              .padding(-Space.xs)
              .opacity(isWorn ? 1 : 0)
          }
        Text(icon.name)
          .textRole(.detail)
          .fontWeight(.semibold)
          .foregroundStyle(.primary)
          .lineLimit(1)
          .minimumScaleFactor(0.7)
        status
          .textRole(.figureSmall)
          .frame(minHeight: Space.l)
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
        .foregroundStyle(.themeAccent)
    } else if shop.owns(icon) {
      Text("Owned")
        .textCase(.uppercase)
        .foregroundStyle(.secondary)
    } else if let productID = icon.productID, shop.purchasing == productID {
      ProgressView()
        .controlSize(.mini)
    } else if let productID = icon.productID, let product = shop.products[productID] {
      Text(verbatim: product.displayPrice)
        .foregroundStyle(.themeAccent)
    } else {
      Image(systemName: "lock.fill")
        .foregroundStyle(.secondary)
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
    VStack(alignment: .leading, spacing: Space.s) {
      Label("Can't reach the App Store. What you own still works offline.", systemImage: "wifi.slash")
        .textRole(.detail)
        .foregroundStyle(.warning)
      Button("Try Again") {
        Task { await shop.loadProducts() }
      }
      .textRole(.detail)
      .fontWeight(.semibold)
      .buttonStyle(.borderless)
      .frame(minHeight: Size.target)
    }
    .padding(.vertical, Space.xs)
  }
}

#if DEBUG
#Preview("Shop") { ScreenPreview(.shop) }
#endif
