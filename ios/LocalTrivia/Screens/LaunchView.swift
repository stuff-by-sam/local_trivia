import SwiftUI

/// The first second after launch: black, as the launch screen left it, with
/// the answer set dotting on in the middle — circle, triangle, square,
/// diamond — before the game fades up underneath.
///
/// It's an overlay, not a gate. The app is already running under it, finding
/// games and rejoining one, and it takes no touches, so nobody quick is held
/// up by it.
struct LaunchView: View {
  let onFinish: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  /// How many of the four are on screen.
  @State private var landed = 0

  var body: some View {
    ZStack {
      Color.black
      HStack(spacing: 26) {
        ForEach(AnswerStyle.allCases) { style in
          let isOn = style.rawValue < landed
          Image(systemName: style.symbol)
            .font(.system(size: 30))
            .foregroundStyle(style.color)
            // Each lands with the phosphor bloom the TV gives it.
            .shadow(color: style.color.opacity(isOn ? 0.6 : 0), radius: 10)
            .scaleEffect(isOn ? 1 : 0.2)
            .opacity(isOn ? 1 : 0)
        }
      }
    }
    .ignoresSafeArea()
    .allowsHitTesting(false)
    .accessibilityHidden(true)
    .task {
      if reduceMotion {
        withAnimation(.easeIn(duration: 0.25)) { landed = AnswerStyle.allCases.count }
      } else {
        for count in 1...AnswerStyle.allCases.count {
          try? await Task.sleep(for: .milliseconds(140))
          withAnimation(.spring(duration: 0.35, bounce: 0.45)) { landed = count }
        }
      }
      try? await Task.sleep(for: .milliseconds(450))
      onFinish()
    }
  }
}
