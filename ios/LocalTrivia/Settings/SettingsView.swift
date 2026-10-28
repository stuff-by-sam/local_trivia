import DesignSystem
import SwiftUI

/// Everything about this phone that isn't a game: how it dresses the game,
/// safety, and how to play — behind one button, so the join screen is left
/// to joining and hosting.
struct SettingsView: View {
  /// The pages it opens.
  enum Page: Hashable {
    case looks, safety, howToPlay
  }

  @Environment(Looks.self) private var looks
  @Environment(\.dismiss) private var dismiss
  @State private var path: [Page]

  /// `page` opens it there, as if it had been tapped.
  init(showing page: Page? = nil) {
    _path = State(initialValue: page.map { [$0] } ?? [])
  }

  var body: some View {
    NavigationStack(path: $path) {
      List {
        Section {
          NavigationLink(value: Page.looks) {
            LabeledContent {
              Text(looks.theme.name)
            } label: {
              Label("Themes & Icons", systemImage: "paintpalette")
            }
          }
        }

        Section {
          NavigationLink(value: Page.safety) {
            Label("Safety", systemImage: "hand.raised")
          }
          NavigationLink(value: Page.howToPlay) {
            Label("How to Play", systemImage: "questionmark.circle")
          }
        } footer: {
          Text(verbatim: Self.version)
        }
      }
      .navigationTitle("Settings")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .navigationDestination(for: Page.self) { page in
        switch page {
        case .looks: LooksView()
        case .safety: SafetyView()
        // Let's Play goes back to the game, not to Settings.
        case .howToPlay: TutorialView { dismiss() }
        }
      }
    }
  }

  /// "Trivia 1.0 (7)" — what a report about the app needs to say.
  private static let version: String = {
    let info = Bundle.main.infoDictionary ?? [:]
    let name = info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? "Trivia"
    let version = info["CFBundleShortVersionString"] as? String ?? ""
    let build = info["CFBundleVersion"] as? String ?? ""
    return "\(name) \(version) (\(build))"
  }()
}

#if DEBUG
#Preview("Settings") { ScreenPreview(.settings) }
#endif
