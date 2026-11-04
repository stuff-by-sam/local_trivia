import DesignSystem
import SwiftUI

/// Makes or changes a set of answer markers of the player's own: a name, and
/// a shape for each of A, B, C and D from the library (`MarkerShape`).
///
/// The four keys at the top are the set as it stands, drawn as the game
/// draws them. Tapping a shape puts it beside the key that's lit and lights
/// the next, so four taps make a set; a shape already in the set swaps
/// places with the one it replaces, so a set never has the same shape twice.
struct MarkersEditor: View {
  let isNew: Bool
  /// What it was when the sheet opened, to tell whether Cancel loses anything.
  private let original: OwnMarkers

  @Environment(Looks.self) private var looks
  @Environment(\.dismiss) private var dismiss
  @State private var draft: OwnMarkers
  /// The key the next shape goes beside.
  @State private var slot: AnswerStyle = .a
  @State private var search = ""
  @State private var confirmsDiscard = false

  init(own: OwnMarkers, isNew: Bool) {
    self.isNew = isNew
    original = own
    _draft = State(initialValue: own)
  }

  private var hasChanges: Bool { draft != original }

  /// The library's shapes, in their categories, as far as the search allows.
  private var shelves: [(MarkerShape.Category, [MarkerShape])] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
    return MarkerShape.Category.allCases.compactMap { category in
      let shapes = MarkerShape.library.filter { shape in
        shape.category == category
          && (query.isEmpty || String(localized: shape.name).localizedStandardContains(query))
      }
      return shapes.isEmpty ? nil : (category, shapes)
    }
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.xl) {
          keys
          TextField("Name", text: $draft.name, prompt: Text("My Markers"))
            .textInputAutocapitalization(.words)
            .submitLabel(.done)
            .padding(Space.inset)
            .glassCard(in: .rect(cornerRadius: Radius.control))
          library
        }
        .padding(.horizontal, Space.screen)
        .padding(.bottom, Space.xl)
      }
      .scrollDismissesKeyboard(.interactively)
      .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: Text("Search shapes"))
      .background { Backdrop(mood: .idle) }
      .glassClarity(.clear)
      .environment(\.answerMarkers, draft.markers)
      .motion(.snap, value: draft.symbols)
      .motion(.snap, value: slot)
      .haptic(.pick, trigger: draft.symbols)
      .navigationTitle(isNew ? "New Markers" : "Edit Markers")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") {
            if hasChanges { confirmsDiscard = true } else { dismiss() }
          }
          .confirmationDialog(isNew ? "Discard these markers?" : "Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button(isNew ? "Discard Markers" : "Discard Changes", role: .destructive) { dismiss() }
            Button("Keep Editing", role: .cancel) {}
          }
        }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .disabled(!draft.isComplete)
        }
      }
    }
    .interactiveDismissDisabled(hasChanges)
  }

  // MARK: - The set

  /// A, B, C and D with their shapes, the one taking the next shape lit.
  private var keys: some View {
    HStack(spacing: Space.s) {
      ForEach(AnswerStyle.allCases) { style in
        let isLit = slot == style
        let shape = draft.shapes.indices.contains(style.rawValue) ? draft.shapes[style.rawValue] : nil
        Button {
          slot = style
        } label: {
          VStack(spacing: Space.s) {
            AnswerKey(style: style)
              .font(.title3)
            (shape.map { Text($0.name) } ?? Text(verbatim: " "))
              .textRole(.detail)
              .foregroundStyle(.secondary)
              .lineLimit(2, reservesSpace: true)
              .multilineTextAlignment(.center)
              .minimumScaleFactor(0.8)
          }
          .frame(maxWidth: .infinity)
          .padding(.vertical, Space.m)
          .padding(.horizontal, Space.xs)
          .glassCard(in: .rect(cornerRadius: Radius.control), tint: isLit ? style.color : nil)
          .overlay {
            RoundedRectangle(cornerRadius: Radius.control)
              .strokeBorder(style.color, lineWidth: Size.bubbleRing)
              .opacity(isLit ? 1 : 0)
          }
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: "\(style.letter), \(shape.map { String(localized: $0.name) } ?? "")"))
        .accessibilityHint(Text("Choose a shape for \(style.letter)."))
        .accessibilityAddTraits(isLit ? .isSelected : [])
      }
    }
    .dynamicTypeSize(...Size.barTypeLimit)
  }

  // MARK: - The library

  private var library: some View {
    VStack(alignment: .leading, spacing: Space.l) {
      if shelves.isEmpty {
        ContentUnavailableView.search(text: search)
      }
      ForEach(shelves, id: \.0) { category, shapes in
        VStack(alignment: .leading, spacing: Space.s) {
          SectionHeader(verbatim: String(localized: category.name))
          LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.target + Space.m), spacing: Space.s)], spacing: Space.s) {
            ForEach(shapes) { shape in
              cell(shape)
            }
          }
        }
      }
    }
  }

  /// One shape: in its answer's colour, with its letter, if it's in the set.
  private func cell(_ shape: MarkerShape) -> some View {
    let used = draft.symbols.firstIndex(of: shape.symbol).flatMap(AnswerStyle.init(rawValue:))
    return Button {
      put(shape)
    } label: {
      Symbols.image(shape.symbol)
        .font(.title2)
        .imageScale(.medium)
        .foregroundStyle(used.map { AnyShapeStyle($0.color) } ?? AnyShapeStyle(.primary))
        .frame(maxWidth: .infinity, minHeight: Size.target + Space.m)
        .glassCard(in: .rect(cornerRadius: Radius.minimum), tint: used?.color)
        .overlay(alignment: .topTrailing) {
          if let used {
            Text(verbatim: used.letter)
              .textRole(.status)
              .foregroundStyle(.onAccent)
              .padding(.horizontal, Space.xs)
              .background(used.color, in: .capsule)
              .padding(Space.xxs)
          }
        }
        .contentShape(.rect)
    }
    .buttonStyle(.bubble)
    .accessibilityLabel(Text(shape.name))
    .accessibilityValue(used.map { Text("Beside \($0.letter)") } ?? Text(verbatim: ""))
    .accessibilityHint(Text("Puts it beside \(slot.letter)."))
  }

  // MARK: - Changes

  /// Puts `shape` beside the lit key, swapping it with that key's shape if
  /// it's already beside another, and lights the next key.
  private func put(_ shape: MarkerShape) {
    var symbols = draft.symbols
    for missing in AnswerMarkers.classic.shapes.map(\.symbol) where symbols.count < AnswerStyle.allCases.count {
      if !symbols.contains(missing) { symbols.append(missing) }
    }
    let here = slot.rawValue
    if let there = symbols.firstIndex(of: shape.symbol) {
      symbols.swapAt(there, here)
    } else {
      symbols[here] = shape.symbol
    }
    draft.symbols = symbols
    slot = AnswerStyle(rawValue: (here + 1) % AnswerStyle.allCases.count) ?? .a
  }

  private func save() {
    var own = draft
    own.name = own.displayName
    looks.keep(own)
    dismiss()
  }
}

#if DEBUG
#Preview("New Markers") { ScreenPreview(.markersEditor) }
#endif
