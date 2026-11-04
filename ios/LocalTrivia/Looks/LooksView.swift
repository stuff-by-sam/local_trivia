import DesignSystem
import SwiftUI

/// Themes and answer markers: how this phone dresses the game. Every one is
/// free; tapping a bubble puts it on, and the last bubble makes one of your
/// own.
///
/// Out of the way on purpose — a page of Settings — because the game is the
/// point. The choices are bubbles in a honeycomb, as watchOS lays out its
/// apps, so a glance takes them all in: what's on is lit, and said in words
/// at the top, where the page shows it off. Trying one on is a tap, and
/// taking it off is another.
struct LooksView: View {
  /// Which choices the honeycomb shows.
  enum Kind: Hashable {
    case themes, markers
  }

  @Environment(Looks.self) private var looks
  @ScaledMetric(relativeTo: .body) private var scaledBubble = Size.bubble
  @State private var kind: Kind
  @State private var editing: Editing?
  @State private var undo: UndoItem?

  init(showing kind: Kind = .themes) {
    _kind = State(initialValue: kind)
  }

  /// Bigger with the text, but never so big a row holds fewer than two.
  private var bubble: CGFloat { min(scaledBubble, Size.bubble * 1.8) }
  /// How near the top or bottom a bubble starts to shrink, as on watchOS.
  private var lens: CGFloat { bubble * 0.6 }

  var body: some View {
    VStack(spacing: Space.m) {
      Showcase(kind: kind)
        .dynamicTypeSize(...Size.barTypeLimit)
      Picker(selection: $kind) {
        Text("Themes").tag(Kind.themes)
        Text("Answer Markers").tag(Kind.markers)
      } label: {
        Text("Choices")
      }
      .pickerStyle(.segmented)
      .padding(.horizontal, Space.screen)
      .dynamicTypeSize(...Size.barTypeLimit)

      ScrollView {
        VStack(spacing: Space.xl) {
          switch kind {
          case .themes: Honeycomb(diameter: bubble) { themes }
          case .markers: Honeycomb(diameter: bubble) { markerSets }
          }
          Text(footer)
            .textRole(.detail)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Space.screen)
      }
      // At rest nothing sits in the lens: it's what scrolling does.
      .contentMargins(.vertical, lens, for: .scrollContent)
      .scrollBounceBehavior(.always)
    }
    .background { Backdrop(mood: .idle) }
    .glassClarity(.clear)
    .navigationTitle("Themes & Markers")
    .navigationBarTitleDisplayMode(.inline)
    .theme(looks.theme)
    .environment(\.answerMarkers, looks.markers)
    .motion(.settle, value: looks.theme)
    .motion(.settle, value: looks.markers)
    .motion(.settle, value: kind)
    .haptic(.pick, trigger: looks.theme.id)
    .haptic(.pick, trigger: looks.markers.id)
    .undoToast($undo)
    .sheet(item: $editing) { editing in
      switch editing {
      case .theme(let own, let isNew): ThemeEditor(own: own, isNew: isNew)
      case .markers(let own, let isNew): MarkersEditor(own: own, isNew: isNew)
      }
    }
  }

  /// What a pick changes, and what it never does.
  private var footer: LocalizedStringResource {
    let isPad = UIDevice.current.userInterfaceIdiom == .pad
    return switch (kind, isPad) {
    case (.themes, false): "A theme dresses this phone, any TV it puts the game on, and the browsers in a game it hosts. Touch and hold a theme for more."
    case (.themes, true): "A theme dresses this iPad, any TV it puts the game on, and the browsers in a game it hosts. Touch and hold a theme for more."
    case (.markers, false): "The shapes beside each answer's letter, on this phone and any TV it puts the game on. Letters and colors stay the same on every phone, so B is always cyan."
    case (.markers, true): "The shapes beside each answer's letter, on this iPad and any TV it puts the game on. Letters and colors stay the same on every phone, so B is always cyan."
    }
  }

  // MARK: - Themes

  @ViewBuilder
  private var themes: some View {
    ForEach(looks.themes) { theme in
      let isWorn = theme.id == looks.theme.id
      Button {
        looks.wear(theme)
      } label: {
        ThemeBubble(theme: theme, isWorn: isWorn, diameter: bubble)
      }
      .buttonStyle(.bubble)
      .fisheye(band: lens)
      .contextMenu { menu(for: theme) }
      .accessibilityLabel(Text(verbatim: "\(theme.name.string). \(theme.tagline.string)"))
      .accessibilityHint(isWorn ? Text(verbatim: "") : Text("Wears this theme."))
      .accessibilityAddTraits(isWorn ? .isSelected : [])
    }
    Button {
      let name = looks.freshName(String(localized: "My Theme"), taken: looks.ownThemes.map(\.name))
      editing = .theme(OwnTheme(startingFrom: looks.theme, name: name), isNew: true)
    } label: {
      MakeBubble(diameter: bubble)
    }
    .buttonStyle(.bubble)
    .fisheye(band: lens)
    .accessibilityLabel(Text("Make Your Own Theme"))
  }

  @ViewBuilder
  private func menu(for theme: Theme) -> some View {
    if let own = looks.ownTheme(theme.id) {
      Button("Edit", systemImage: "pencil") {
        editing = .theme(own, isNew: false)
      }
      Button("Duplicate", systemImage: "plus.square.on.square") {
        var copy = own
        copy.id = "own-" + UUID().uuidString
        copy.name = looks.freshName(own.displayName, taken: looks.ownThemes.map(\.name))
        editing = .theme(copy, isNew: true)
      }
      Divider()
      Button("Delete", systemImage: "trash", role: .destructive) {
        delete(own)
      }
    } else {
      Button("Make Your Own from This", systemImage: "plus.square.on.square") {
        let name = looks.freshName(String(localized: "My \(theme.name.string)"), taken: looks.ownThemes.map(\.name))
        editing = .theme(OwnTheme(startingFrom: theme, name: name), isNew: true)
      }
    }
  }

  private func delete(_ own: OwnTheme) {
    guard let index = looks.ownThemes.firstIndex(of: own) else { return }
    let wasWorn = looks.theme.id == own.id
    Motion.settle.perform { looks.remove(own) }
    undo = UndoItem(String(localized: "Deleted “\(own.displayName)”")) {
      Motion.settle.perform { looks.restore(own, at: index, wearing: wasWorn) }
    }
  }

  // MARK: - Markers

  @ViewBuilder
  private var markerSets: some View {
    ForEach(looks.markerSets) { markers in
      let isWorn = markers.id == looks.markers.id
      Button {
        looks.wear(markers)
      } label: {
        MarkerBubble(markers: markers, isWorn: isWorn, diameter: bubble)
      }
      .buttonStyle(.bubble)
      .fisheye(band: lens)
      .contextMenu { menu(for: markers) }
      .accessibilityLabel(Text(verbatim: "\(markers.name.string). \(markers.tagline.string)"))
      .accessibilityHint(isWorn ? Text(verbatim: "") : Text("Uses these markers."))
      .accessibilityAddTraits(isWorn ? .isSelected : [])
    }
    Button {
      let name = looks.freshName(String(localized: "My Markers"), taken: looks.ownMarkers.map(\.name))
      editing = .markers(OwnMarkers(startingFrom: looks.markers, name: name), isNew: true)
    } label: {
      MakeBubble(diameter: bubble)
    }
    .buttonStyle(.bubble)
    .fisheye(band: lens)
    .accessibilityLabel(Text("Make Your Own Markers"))
  }

  @ViewBuilder
  private func menu(for markers: AnswerMarkers) -> some View {
    if let own = looks.ownMarkers(markers.id) {
      Button("Edit", systemImage: "pencil") {
        editing = .markers(own, isNew: false)
      }
      Button("Duplicate", systemImage: "plus.square.on.square") {
        let name = looks.freshName(own.displayName, taken: looks.ownMarkers.map(\.name))
        editing = .markers(OwnMarkers(name: name, symbols: own.symbols), isNew: true)
      }
      Divider()
      Button("Delete", systemImage: "trash", role: .destructive) {
        delete(own)
      }
    } else {
      Button("Make Your Own from This", systemImage: "plus.square.on.square") {
        let name = looks.freshName(String(localized: "My \(markers.name.string)"), taken: looks.ownMarkers.map(\.name))
        editing = .markers(OwnMarkers(startingFrom: markers, name: name), isNew: true)
      }
    }
  }

  private func delete(_ own: OwnMarkers) {
    guard let index = looks.ownMarkers.firstIndex(of: own) else { return }
    let wasWorn = looks.markers.id == own.id
    Motion.settle.perform { looks.remove(own) }
    undo = UndoItem(String(localized: "Deleted “\(own.displayName)”")) {
      Motion.settle.perform { looks.restore(own, at: index, wearing: wasWorn) }
    }
  }
}

/// What the page's sheet is editing: a theme or a set of markers of the
/// player's own, new or being changed.
private enum Editing: Identifiable {
  case theme(OwnTheme, isNew: Bool)
  case markers(OwnMarkers, isNew: Bool)

  var id: String {
    switch self {
    case .theme(let own, _): own.id
    case .markers(let own, _): own.id
    }
  }
}

/// What's on, drawn the way the join screen draws itself — the theme, and
/// the answer markers above the wordmark — and said in words: the theme's
/// name and tagline, or the markers'. Always two lines of tagline tall, so
/// the honeycomb under it never moves when a pick has a shorter one.
private struct Showcase: View {
  let kind: LooksView.Kind

  @Environment(Looks.self) private var looks

  var body: some View {
    let (name, tagline) =
      switch kind {
      case .themes: (String(localized: "Wearing \(looks.theme.name.string)"), looks.theme.tagline)
      case .markers: (String(localized: "Using \(looks.markers.name.string)"), looks.markers.tagline)
      }
    VStack(spacing: Space.l) {
      AnswerSetMark(depth: .mark)
        .font(.subheadline)
      Wordmark(scale: .showcase)
      VStack(spacing: Space.xs) {
        StatusLine(verbatim: name)
        Text(tagline)
          .textRole(.detail)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
          .lineLimit(2, reservesSpace: true)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.horizontal, Space.screen)
    .padding(.top, Space.s)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Text(verbatim: "\(name). \(tagline.string)"))
  }
}

#if DEBUG
#Preview("Themes") { ScreenPreview(.looks) }
#Preview("Answer Markers") { ScreenPreview(.looksMarkers) }
#endif
