import SwiftUI
import UIKit

@main
struct GlassTapsApp: App {
  @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      ContentView()
        .modifier(If(ContentView.flag("tint")) { $0.tint(.green) })
    }
  }
}

/// Supplies each scene's configuration, as an app does to give an external
/// display a scene of its own. Off with `-appDelegate NO`.
final class AppDelegate: NSObject, UIApplicationDelegate {
  func application(
    _ application: UIApplication,
    configurationForConnecting session: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    guard ContentView.flag("appDelegate") else {
      return UISceneConfiguration(name: "Default Configuration", sessionRole: session.role)
    }
    return UISceneConfiguration(name: nil, sessionRole: session.role)
  }
}

/// Glass buttons in a `safeAreaBar`: tap each and watch the count.
///
/// Every ingredient can be switched off with a launch argument, `-<name> NO`:
/// `appDelegate`, `tint`, `rootSheet`, `container`, `glassContent`,
/// `transition`, `columnFrame`, `background`, `barAnimation`, `feedback`,
/// `toolbar`, `reader`.
struct ContentView: View {
  @State private var taps = 0
  @State private var focusToggle = false

  static func flag(_ name: String) -> Bool {
    UserDefaults.standard.object(forKey: name) as? Bool ?? true
  }

  var body: some View {
    NavigationStack {
      Group {
        if Self.flag("container") {
          GlassEffectContainer(spacing: 4) { column }
        } else {
          column
        }
      }
      .modifier(If(Self.flag("background")) { $0.containerBackground(for: .navigation) { LinearGradient(colors: [.indigo, .black], startPoint: .top, endPoint: .bottom) } })
      .navigationTitle("Glass taps")
    }
    .modifier(If(Self.flag("rootSheet")) { $0.sheet(isPresented: .constant(false)) { Text(verbatim: "sheet") } })
  }

  private var column: some View {
    screen
      .modifier(If(Self.flag("transition")) { $0.id("join").transition(.blurReplace) })
      .modifier(If(Self.flag("columnFrame")) { $0.frame(maxWidth: 540).frame(maxWidth: .infinity) })
  }

  @ViewBuilder
  private var screen: some View {
    if Self.flag("reader") {
      ScrollViewReader { _ in scroll }
    } else {
      scroll
    }
  }

  private var scroll: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Taps: \(taps)")
          .font(.largeTitle.bold())
          .accessibilityIdentifier("count")
        ForEach(1...4, id: \.self) { row in
          Text("Field \(row)")
            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
            .padding(.horizontal)
            .modifier(If(Self.flag("glassContent")) { $0.glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20)) })
        }
      }
      .padding()
    }
    .scrollBounceBehavior(.basedOnSize)
    .safeAreaBar(edge: .bottom) {
      VStack(spacing: 8) {
        bar("Glass", id: "glass", prominent: false)
        bar("Glass Prominent", id: "prominent", prominent: true)
        Button("Plain") { taps += 1 }
          .accessibilityIdentifier("plain")
      }
      .padding()
      .modifier(If(Self.flag("barAnimation")) { $0.animation(.smooth(duration: 0.35), value: focusToggle) })
    }
    .modifier(If(Self.flag("toolbar")) {
      $0.toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") { focusToggle.toggle() }
        }
      }
    })
  }

  @ViewBuilder
  private func bar(_ title: String, id: String, prominent: Bool) -> some View {
    let button = Button { taps += 1 } label: {
      Text(title).frame(maxWidth: .infinity)
    }
    .controlSize(.large)
    .modifier(If(Self.flag("feedback")) { $0.sensoryFeedback(.impact, trigger: taps) })
    .accessibilityIdentifier(id)
    if prominent { button.buttonStyle(.glassProminent) } else { button.buttonStyle(.glass) }
  }
}

/// Applies `transform` when `condition` holds.
private struct If<Transformed: View>: ViewModifier {
  let condition: Bool
  let transform: (AnyView) -> Transformed

  init(_ condition: Bool, _ transform: @escaping (AnyView) -> Transformed) {
    self.condition = condition
    self.transform = transform
  }

  func body(content: Content) -> some View {
    if condition { transform(AnyView(content)) } else { content }
  }
}
