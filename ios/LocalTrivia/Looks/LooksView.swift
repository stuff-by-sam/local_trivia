import DesignSystem
import SwiftUI

/// Themes, answer markers and app icons: how this phone dresses the game.
/// Every one is free; tapping one puts it on.
///
/// Out of the way on purpose — a toolbar button on the join screen — because
/// the game is the point. Each kind is a group that opens when it's wanted,
/// and says what's in use while it's closed.
struct LooksView: View {
  @Environment(Looks.self) private var looks
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var typeSize

  @State private var showsThemes = false
  @State private var showsMarkers = false
  @State private var showsIcons = false
  /// The last notice, held here so the alert keeps its words while it
  /// animates away.
  @State private var alert = ""
  @State private var isAlerting = false

  var body: some View {
    NavigationStack {
      List {
        Section {
          Showcase(theme: looks.theme)
        }
        .listRowBackground(Color.clear)

        themes
        markers

        if looks.canChangeIcon {
          icons
        }
      }
      // The one sheet that shows the backdrop: showing a theme is the point.
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
    .theme(looks.theme)
    .environment(\.answerMarkers, looks.markers)
    .motion(.settle, value: looks.theme)
    .motion(.settle, value: looks.markers)
    .onChange(of: looks.notice) { _, notice in
      guard let notice else { return }
      alert = notice
      isAlerting = true
      looks.notice = nil
    }
  }

  // MARK: - Themes

  private var themes: some View {
    Section {
      DisclosureGroup(isExpanded: $showsThemes) {
        ForEach(Theme.allCases) { theme in
          ThemeRow(theme: theme) { looks.wear(theme) }
        }
      } label: {
        GroupLabel("Themes", current: looks.theme.name) {
          ThemeSwatch(theme: looks.theme, isShown: false)
        }
      }
    } footer: {
      Text("A theme dresses this phone, any TV it puts the game on, and the browsers in a game it hosts.")
    }
  }

  // MARK: - Markers

  private var markers: some View {
    Section {
      DisclosureGroup(isExpanded: $showsMarkers) {
        ForEach(AnswerMarkers.allCases) { markers in
          MarkerRow(markers: markers) { looks.wear(markers) }
        }
      } label: {
        GroupLabel("Answer Markers", current: looks.markers.name) {
          MarkerSwatch(markers: looks.markers, isShown: false)
        }
      }
    } footer: {
      Text("The shapes beside each answer's letter, on this phone and any TV it puts the game on. Letters and colours stay the same on every phone, so B is always cyan.")
    }
  }

  // MARK: - Icons

  private var icons: some View {
    Section {
      DisclosureGroup(isExpanded: $showsIcons) {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.iconTile * (typeSize.isAccessibilitySize ? 2.4 : 1.4)), spacing: Space.m)], spacing: Space.l) {
          ForEach(AppIcon.allCases) { icon in
            IconTile(icon: icon) {
              Task { await looks.setIcon(icon) }
            }
          }
        }
        .padding(.vertical, Space.s)
      } label: {
        GroupLabel("App Icons", current: looks.icon.name) {
          IconArtwork(looks.icon.design, size: Size.swatch)
        }
      }
    } footer: {
      Text("Changes Trivia's icon on your Home Screen.")
    }
  }
}

/// What's on, drawn the way the join screen draws itself: the theme, and the
/// answer markers above the wordmark.
private struct Showcase: View {
  let theme: Theme

  var body: some View {
    VStack(spacing: Space.l) {
      AnswerSetMark()
        .font(.subheadline)
      Wordmark(scale: .showcase)
      VStack(spacing: Space.xs) {
        StatusLine("Wearing \(String(localized: theme.name))")
        Text(theme.tagline)
          .textRole(.detail)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Space.s)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text("Wearing \(String(localized: theme.name)). \(String(localized: theme.tagline))"))
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
  let onSelect: () -> Void

  @Environment(Looks.self) private var looks

  var body: some View {
    let isWorn = looks.theme == theme
    Button(action: onSelect) {
      HStack(spacing: Space.m) {
        ThemeSwatch(theme: theme, isShown: isWorn)
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
        if isWorn {
          Image(systemName: "checkmark")
            .fontWeight(.bold)
            .foregroundStyle(theme.accent)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .padding(.vertical, Space.xs)
    .accessibilityAddTraits(isWorn ? .isSelected : [])
    .accessibilityHint(isWorn ? Text(verbatim: "") : Text("Wears this theme."))
  }
}

private struct MarkerRow: View {
  let markers: AnswerMarkers
  let onSelect: () -> Void

  @Environment(Looks.self) private var looks

  var body: some View {
    let isWorn = looks.markers == markers
    Button(action: onSelect) {
      HStack(spacing: Space.m) {
        MarkerSwatch(markers: markers, isShown: isWorn)
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
        if isWorn {
          Image(systemName: "checkmark")
            .fontWeight(.bold)
            .foregroundStyle(.themeAccent)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .padding(.vertical, Space.xs)
    .accessibilityAddTraits(isWorn ? .isSelected : [])
    .accessibilityHint(isWorn ? Text(verbatim: "") : Text("Uses these markers."))
  }
}

/// One icon: tapping it puts it on the Home Screen.
private struct IconTile: View {
  let icon: AppIcon
  let action: () -> Void

  @Environment(Looks.self) private var looks

  var body: some View {
    let isWorn = looks.icon == icon
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
        // Room for the check under every tile, so the rows line up.
        Image(systemName: "checkmark")
          .textRole(.figureSmall)
          .foregroundStyle(.themeAccent)
          .opacity(isWorn ? 1 : 0)
          .frame(minHeight: Space.l)
      }
      .frame(maxWidth: .infinity)
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(Text("\(String(localized: icon.name)) icon"))
    .accessibilityAddTraits(isWorn ? .isSelected : [])
  }
}

#if DEBUG
#Preview("Themes & Icons") { ScreenPreview(.looks) }
#endif
