import DesignSystem
import PhotosUI
import SwiftUI

/// Makes or changes a theme of the player's own: a name, a colour, and what
/// it's over — one of the game's backdrops, or a photo of theirs.
///
/// The sheet wears the theme as it's made, glass and all, so what you see is
/// what you'll get. A photo is dressed for the glass the moment it's picked
/// (`ThemePhoto.dress`), and offers its own colour for the accent; it waits
/// in a temporary file until Save moves it in, and Cancel lets it go.
struct ThemeEditor: View {
  let isNew: Bool
  /// What it was when the sheet opened, to tell whether Cancel loses anything.
  private let original: OwnTheme

  @Environment(Looks.self) private var looks
  @Environment(\.dismiss) private var dismiss
  @State private var draft: OwnTheme
  /// What the system's colour picker shows: the draft's colour, as a colour.
  @State private var anyColor: Color
  /// Whether it's over a photo rather than a texture.
  @State private var usesPhoto: Bool
  /// A photo picked here, dressed and waiting to be kept.
  @State private var newPhoto: URL?
  @State private var pickedItem: PhotosPickerItem?
  @State private var isDressing = false
  @State private var problem: String?
  @State private var confirmsDiscard = false

  init(own: OwnTheme, isNew: Bool) {
    self.isNew = isNew
    original = own
    _draft = State(initialValue: own)
    _anyColor = State(initialValue: Theme.color(own.color))
    _usesPhoto = State(initialValue: own.photo != nil)
  }

  /// The photo it can be over: one just picked, or the one it had.
  private var photo: ThemePhoto? {
    if let newPhoto { return ThemePhoto(url: newPhoto) }
    return draft.photo.map { ThemePhoto(url: looks.photos.appending(path: $0)) }
  }

  /// The theme as it stands.
  private var theme: Theme {
    draft.theme(photo: usesPhoto ? photo : nil)
  }

  /// The draft over `texture`, for its bubble.
  private func theme(over texture: Backdrop.Texture) -> Theme {
    var over = draft
    over.backdrop = texture
    return over.theme(photo: nil)
  }

  /// Whether Cancel would lose something.
  private var hasChanges: Bool {
    draft != original || newPhoto != nil || usesPhoto != (original.photo != nil)
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          ThemeSample()
        }
        .listRowBackground(Color.clear)

        Group {
        Section {
          TextField("Name", text: $draft.name, prompt: Text("My Theme"))
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
        } header: {
          Text("Name")
        }

        Section {
          colors
          ColorPicker("Any Color", selection: $anyColor, supportsOpacity: false)
        } header: {
          Text("Color")
        } footer: {
          if Theme.isLightened(draft.color) {
            Text("Lightened a little, so text on it stays easy to read.")
          }
        }

        Section {
          backdrops
          let hasPhoto = photo != nil
          PhotosPicker(selection: $pickedItem, matching: .images, preferredItemEncoding: .current) {
            Label(hasPhoto ? "Choose Another Photo…" : "Choose a Photo…", systemImage: "photo.on.rectangle")
          }
          .disabled(isDressing)
        } header: {
          Text("Backdrop")
        } footer: {
          Text("A photo stays on this device. It's softened and dimmed so the game reads over it, and shows on any TV this device puts the game on.")
        }
        }
        // Clear glass over the backdrop: the theme shows through every row.
        .listRowBackground(Rectangle().fill(.clear).glassCard(in: .rect))
      }
      .scrollContentBackground(.hidden)
      .background { Backdrop(mood: .idle) }
      .glassClarity(.clear)
      .motion(.settle, value: theme)
      .navigationTitle(isNew ? "New Theme" : "Edit Theme")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            if hasChanges { confirmsDiscard = true } else { cancel() }
          }
          .confirmationDialog(isNew ? "Discard this theme?" : "Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button(isNew ? "Discard Theme" : "Discard Changes", role: .destructive, action: cancel)
            Button("Keep Editing", role: .cancel) {}
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .disabled(isDressing)
        }
      }
      .onChange(of: anyColor) { _, color in
        let rgb = Theme.rgb(of: color)
        if rgb != draft.color { draft.color = rgb }
      }
      .task(id: pickedItem) {
        await dress(pickedItem)
      }
      .alert(Text(verbatim: problem ?? ""), isPresented: Binding { problem != nil } set: { if !$0 { problem = nil } }) {
        Button("OK") {}
      }
    }
    // Outside the stack, so its bar's buttons wear the theme too.
    .theme(theme)
    .interactiveDismissDisabled(hasChanges)
  }

  // MARK: - Colour

  private var colors: some View {
    ScrollView(.horizontal) {
      HStack(spacing: Space.s) {
        ForEach(Theme.suggestions) { suggestion in
          let isPicked = draft.color == suggestion.color
          Button {
            draft.color = suggestion.color
            anyColor = Theme.color(suggestion.color)
          } label: {
            Circle()
              .fill(Theme.color(suggestion.color))
              .frame(width: Size.target, height: Size.target)
              .overlay {
                Image(systemName: "checkmark")
                  .fontWeight(.bold)
                  .foregroundStyle(.onAccent)
                  .opacity(isPicked ? 1 : 0)
              }
              .overlay { Circle().strokeBorder(.panelStroke, lineWidth: 1) }
          }
          .buttonStyle(.bubble)
          .accessibilityLabel(Text(suggestion.name))
          .accessibilityAddTraits(isPicked ? .isSelected : [])
        }
      }
      .padding(.vertical, Space.xs)
    }
    .scrollIndicators(.hidden)
  }

  // MARK: - Backdrop

  /// Every texture, as a bubble in the draft's colour, and the photo when
  /// there is one.
  private var backdrops: some View {
    Honeycomb(diameter: Size.swatch, spacing: Space.s) {
      ForEach(Backdrop.Texture.allCases, id: \.self) { texture in
        let isPicked = !usesPhoto && draft.backdrop == texture
        Button {
          usesPhoto = false
          draft.backdrop = texture
        } label: {
          ThemeBubble(theme: theme(over: texture), isWorn: isPicked, diameter: Size.swatch)
        }
        .buttonStyle(.bubble)
        .accessibilityLabel(Text(texture.name))
        .accessibilityAddTraits(isPicked ? .isSelected : [])
      }
      if let photo {
        Button {
          usesPhoto = true
        } label: {
          ThemeBubble(theme: draft.theme(photo: photo), isWorn: usesPhoto, diameter: Size.swatch)
        }
        .buttonStyle(.bubble)
        .accessibilityLabel(Text("Your Photo"))
        .accessibilityAddTraits(usesPhoto ? .isSelected : [])
      }
    }
    .padding(.vertical, Space.s)
    .overlay {
      if isDressing {
        ProgressView()
          .accessibilityLabel(Text("Preparing your photo"))
      }
    }
  }

  // MARK: - Photo

  /// Reads the picked photo, dresses it for the glass off the main actor,
  /// and puts it on — with its colour.
  private func dress(_ item: PhotosPickerItem?) async {
    guard let item else { return }
    isDressing = true
    defer {
      isDressing = false
      pickedItem = nil
    }
    do {
      guard let picked = try await item.loadTransferable(type: PickedPhoto.self) else {
        problem = String(localized: "That photo couldn't be opened. Try another.")
        return
      }
      let (dressed, color) = await Task.detached(priority: .userInitiated) {
        (ThemePhoto.dress(contentsOf: picked.url), ThemePhoto.suggestedColor(in: picked.url))
      }.value
      try? FileManager.default.removeItem(at: picked.url)
      guard let dressed else {
        problem = String(localized: "That photo couldn't be opened. Try another.")
        return
      }
      let url = URL.temporaryDirectory.appending(path: "ThemePhoto-\(UUID().uuidString).jpg")
      try dressed.write(to: url)
      if let old = newPhoto { try? FileManager.default.removeItem(at: old) }
      newPhoto = url
      usesPhoto = true
      if let color {
        draft.color = color
        anyColor = Theme.color(color)
      }
    } catch {
      problem = String(localized: "That photo couldn't be opened. Try another.")
    }
  }

  // MARK: - Done

  private func save() {
    var own = draft
    own.name = own.displayName
    if !usesPhoto { own.photo = nil }
    do {
      try looks.keep(own, newPhoto: usesPhoto ? newPhoto : nil)
      if !usesPhoto, let newPhoto { try? FileManager.default.removeItem(at: newPhoto) }
      dismiss()
    } catch {
      problem = String(localized: "Couldn't save the theme. Try again.")
    }
  }

  private func cancel() {
    if let newPhoto { try? FileManager.default.removeItem(at: newPhoto) }
    dismiss()
  }
}

/// A taste of the game in the theme being made: the wordmark, and a chosen
/// answer on its glass.
private struct ThemeSample: View {
  var body: some View {
    VStack(spacing: Space.l) {
      AnswerSetMark(depth: .mark)
        .font(.subheadline)
      Wordmark(scale: .showcase)
      AnswerButton(style: .b, text: String(localized: "Saturn"), longestOption: 7, state: .chosen) {}
        .allowsHitTesting(false)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, Space.s)
    .accessibilityHidden(true)
  }
}

/// A photo the picker hands over, copied somewhere it'll stay until it's
/// dressed: the picker's own copy goes when the transfer ends.
private struct PickedPhoto: Transferable {
  let url: URL

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(importedContentType: .image) { received in
      let copy = URL.temporaryDirectory
        .appending(path: "Picked-\(UUID().uuidString)")
        .appendingPathExtension(received.file.pathExtension)
      try FileManager.default.copyItem(at: received.file, to: copy)
      return PickedPhoto(url: copy)
    }
  }
}

#if DEBUG
#Preview("New Theme") { ScreenPreview(.themeEditor) }
#endif
