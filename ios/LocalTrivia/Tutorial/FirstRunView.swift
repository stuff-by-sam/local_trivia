import DesignSystem
import SwiftUI

/// The first launch, over everything until it's done: the terms to agree to,
/// then how to play (which can be skipped). An update that raises the terms'
/// version shows only the terms again.
struct FirstRunView: View {
  @Environment(Safety.self) private var safety

  var body: some View {
    Group {
      if safety.hasAcceptedTerms {
        TutorialView(isFirstRun: true)
          .transition(.opacity)
      } else {
        TermsView(isAgreeing: true)
          .transition(.opacity)
      }
    }
    .motion(.screen, value: safety.hasAcceptedTerms)
  }
}
