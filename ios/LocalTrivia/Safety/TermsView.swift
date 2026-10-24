import DesignSystem
import SwiftUI

/// The Terms of Use: agreed to before anyone hosts or joins a game (shown over
/// everything from `RootView` until they are), and read again from Safety.
///
/// The same terms are on GitHub Pages (docs/terms.html), and served to browser
/// players by the host (public/play/terms.html). Change all three together,
/// and raise `Safety.termsVersion` when everyone should agree again.
struct TermsView: View {
  /// First launch: agreeing is the only way on. Otherwise just the terms.
  var isAgreeing = false

  @Environment(Safety.self) private var safety
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Space.xl) {
          if isAgreeing {
            VStack(alignment: .leading, spacing: Space.s) {
              Text("Before you play")
                .textRole(.title)
                .accessibilityAddTraits(.isHeader)
              Text("Trivia is for people in the same room. Everyone who hosts or plays agrees to these terms first.")
                .textRole(.body)
                .foregroundStyle(.secondary)
            }
          }
          ForEach(Terms.sections) { section in
            VStack(alignment: .leading, spacing: Space.s) {
              Text(section.title)
                .textRole(.headline)
                .accessibilityAddTraits(.isHeader)
              ForEach(section.paragraphs.indices, id: \.self) { index in
                Text(section.paragraphs[index])
                  .textRole(.body)
                  .foregroundStyle(.secondary)
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
          Link(destination: Terms.appleEULA) {
            Label("Apple's Standard License Agreement", systemImage: "arrow.up.right.square")
          }
          .textRole(.bodyEmphasis)
          Text("Effective October 21, 2026")
            .textRole(.labelSmall)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, Space.screen)
        .padding(.vertical, Space.l)
        .gameColumn()
      }
      .navigationTitle("Terms of Use")
      .navigationBarTitleDisplayMode(.inline)
      // Over the app's backdrop, as every screen is: it's the first one seen.
      .containerBackground(for: .navigation) { Backdrop(mood: .idle) }
      .toolbar {
        if !isAgreeing {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        }
      }
      .safeAreaBar(edge: .bottom) {
        if isAgreeing {
          ActionBar {
            FieldMessage(Text("Read them again any time from Safety, on the join screen."), kind: .hint)
            ActionButton("Agree and Continue", systemImage: "checkmark") { safety.acceptTerms() }
          }
        }
      }
      .scrollEdgeEffectStyle(isAgreeing ? .hard : nil, for: .bottom)
    }
    .interactiveDismissDisabled(isAgreeing)
  }
}

/// The terms, section by section.
enum Terms {
  struct Section: Identifiable {
    let title: LocalizedStringResource
    let paragraphs: [LocalizedStringResource]
    var id: String { title.key }
  }

  static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

  static let sections: [Section] = [
    Section(
      title: "These terms",
      paragraphs: [
        "Trivia lets people in the same room play a quiz together: one person hosts on their iPhone or iPad, and everyone else joins with the app or a web browser. These terms apply to everyone who hosts or plays. By agreeing, you accept them along with Apple's Standard License Agreement for apps.",
      ]
    ),
    Section(
      title: "No objectionable content. No abusive users.",
      paragraphs: [
        "There is no tolerance for objectionable content or abusive users. Don't use a nickname, game name, question or answer that is hateful, discriminatory, harassing, threatening, violent, sexually explicit or illegal, or that targets or bullies anyone. Don't harass, threaten or impersonate other players.",
        "Anyone who does can be removed from a game and blocked by its host and by other players.",
      ]
    ),
    Section(
      title: "How the app keeps games safe",
      paragraphs: [
        "Trivia filters objectionable words out of nicknames, game names and questions, and hides any that still reach a player's screen.",
        "A host can remove or block any player at any time. A blocked player is removed at once, and their phone or browser can't join that host's games again.",
        "Every player can report a question, a player or a game, and can block a host or another player. Blocking removes what they posted from your screen straight away: a blocked host's game ends for you and its games aren't listed again, and a blocked player's name is hidden.",
      ]
    ),
    Section(
      title: "Reports",
      paragraphs: [
        "Reports come to us by email at report@local-trivia.com, and blocking someone sends one too. We review every report within 24 hours and act on it, adding objectionable words and names to the app's filter so they can't be used in any game.",
        "Games have no accounts and no servers, so content is removed and users are ejected on the spot, by the people in the game: the host removes or blocks a player, and players block a host or another player.",
      ]
    ),
    Section(
      title: "Your content and your privacy",
      paragraphs: [
        "You're responsible for what you type and for the questions you host — including ones you draft with Apple Intelligence or another AI, which can be wrong. Check them before you play.",
        "Games run on the players' own devices, over the local network. Nothing anyone types is sent to us or to any server, and it's gone when the game ends — except what you choose to send us in a report, which we use only to review it.",
      ]
    ),
  ]
}

#if DEBUG
#Preview("Agreeing") {
  TermsView(isAgreeing: true)
    .environment(Safety(defaults: nil))
}
#endif
