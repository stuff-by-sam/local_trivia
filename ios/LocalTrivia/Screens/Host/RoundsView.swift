import DesignSystem
import SwiftUI

/// The host's rounds — the one being played, and the ones put by — and the
/// starter rounds that come with the app. Tapping one plays it, and the one
/// it replaces is kept; a starter opens as a copy of the host's own.
///
/// Touch and hold a round to rename, duplicate, share or delete it. Sharing
/// sends it as a CSV (`RoundFile`), which another phone with the app opens
/// as a round of its own.
struct RoundsView: View {
  @Environment(HostController.self) private var host
  @Environment(\.dismiss) private var dismiss
  @State private var renaming: SavedRound?
  @State private var name = ""
  @State private var undo: UndoItem?

  var body: some View {
    let library = host.library
    List {
      Section {
        ForEach(library.rounds) { round in
          row(round, isPlaying: round.id == library.roundID)
        }
        Button("New Round", systemImage: "plus") {
          let taken = Set(library.rounds.map(\.name))
          var name = String(localized: "New Round")
          var number = 2
          while taken.contains(name) {
            name = String(localized: "New Round \(number)")
            number += 1
          }
          library.startRound(named: name)
          dismiss()
        }
      } header: {
        SectionHeader("Your Rounds")
      } footer: {
        Text("Tap a round to play it. The one it replaces stays here, and everything saves as you edit.")
      }

      Section {
        ForEach(StarterRound.allCases) { starter in
          Button {
            guard let round = starter.round else { return }
            library.receive(round)
            dismiss()
          } label: {
            StarterRow(starter: starter)
          }
          .buttonStyle(.plain)
        }
      } header: {
        SectionHeader("Starter Rounds")
      } footer: {
        Text("Ready to play, with every answer checked. Each opens as a copy that's yours to change.")
      }
    }
    .navigationTitle("Rounds")
    .navigationBarTitleDisplayMode(.inline)
    .undoToast($undo)
    .alert("Rename Round", isPresented: Binding { renaming != nil } set: { if !$0 { renaming = nil } }) {
      TextField("Name", text: $name)
        .textInputAutocapitalization(.words)
      Button("Rename") {
        if let renaming { library.rename(renaming.id, to: name) }
      }
      Button("Cancel", role: .cancel) {}
    }
  }

  private func row(_ round: SavedRound, isPlaying: Bool) -> some View {
    Button {
      host.library.open(round.id)
      dismiss()
    } label: {
      HStack(spacing: Space.m) {
        VStack(alignment: .leading, spacing: Space.xxs) {
          Text(verbatim: round.name)
            .textRole(.bodyEmphasis)
            .foregroundStyle(.primary)
          Text("^[\(round.questions.count) question](inflect: true)")
            .textRole(.detail)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        if isPlaying {
          Image(systemName: "checkmark")
            .fontWeight(.bold)
            .foregroundStyle(.themeAccent)
            .accessibilityHidden(true)
        }
      }
      .contentShape(.rect)
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(isPlaying ? .isSelected : [])
    .accessibilityHint(isPlaying ? Text("Being played.") : Text("Plays this round."))
    .swipeActions(edge: .trailing) {
      Button("Delete", systemImage: "trash", role: .destructive) { delete(round) }
    }
    .contextMenu {
      Button("Rename", systemImage: "pencil") {
        name = round.name
        renaming = round
      }
      Button("Duplicate", systemImage: "plus.square.on.square") {
        host.library.duplicate(round.id)
      }
      if !round.questions.isEmpty {
        ShareLink(item: RoundFile(round: round), preview: SharePreview(round.name)) {
          Label("Share…", systemImage: "square.and.arrow.up")
        }
      }
      Divider()
      Button("Delete", systemImage: "trash", role: .destructive) { delete(round) }
    }
  }

  /// Deletes, and offers to put it back.
  private func delete(_ round: SavedRound) {
    let library = host.library
    guard let removal = Motion.settle.perform({ library.remove(round.id) }) else { return }
    undo = UndoItem(String(localized: "Deleted “\(round.name)”")) {
      Motion.settle.perform { library.undo(removal) }
    }
  }
}

/// A starter round: what it's about, and how many questions it has.
private struct StarterRow: View {
  let starter: StarterRound

  @Environment(\.palette) private var palette

  var body: some View {
    HStack(spacing: Space.m) {
      GlassSymbol(starter.symbol, color: palette.accent, depth: .mark)
        .font(.title3)
        .frame(minWidth: Size.target)
      VStack(alignment: .leading, spacing: Space.xxs) {
        Text(starter.name)
          .textRole(.bodyEmphasis)
          .foregroundStyle(.primary)
        Text(starter.summary)
          .textRole(.detail)
          .foregroundStyle(.secondary)
        if let count = starter.questions?.count {
          Text("^[\(count) question](inflect: true)")
            .textRole(.detail)
            .foregroundStyle(.secondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Image(systemName: "plus.circle")
        .foregroundStyle(.themeAccent)
        .accessibilityHidden(true)
    }
    .contentShape(.rect)
    .accessibilityElement(children: .combine)
    .accessibilityHint(Text("Opens a copy as one of your rounds."))
  }
}

#if DEBUG
#Preview("Rounds") { ScreenPreview(.rounds) }
#endif
