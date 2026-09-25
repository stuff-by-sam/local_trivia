# Feedback draft — not filed

**Status: not ready to file.** The bug reproduces every time in Trivia, but
this minimal project doesn't reproduce it yet (see *Reduction*). File it
once it does, or attach the app with Apple's consent to take it privately.

---

**Title:** Glass buttons in a `safeAreaBar` don't receive taps when the view is inside a `GlassEffectContainer`

**Area:** SwiftUI › Liquid Glass

**Platform:** iOS 27.0 (Simulator, iPhone 18 Pro); Xcode 27.0 (27A266a)

## Description

In our app, a button with `.buttonStyle(.glassProminent)` (or `.glass`)
placed in `.safeAreaBar(edge: .bottom)` on a `ScrollView` stops receiving
taps when the screen is inside a `GlassEffectContainer`. The button draws,
is reported hittable, and has the right accessibility frame, but neither
an XCUITest element tap nor a coordinate tap at its centre reaches it.
Removing the `GlassEffectContainer` restores taps.

The failing view, as the whole of the app's window:

```swift
WindowGroup {
  NavigationStack {
    GlassEffectContainer(spacing: 4) {
      ScrollView { Text(verbatim: "content") }
        .safeAreaBar(edge: .bottom) {
          Button(tapped ? "Tapped" : "Host a Game") { tapped = true }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding()
        }
    }
  }
}
```

## Steps

1. Run the app; tap the button in the bottom safe-area bar.

**Expected:** the label changes to "Tapped".
**Actual:** nothing happens. Without `GlassEffectContainer`, it changes.

## Reduction

The same view, pasted into a new project (this one), receives taps. With
each of these added to the new project it still does, so none of them is
the trigger on its own:

- `@UIApplicationDelegateAdaptor` returning `UISceneConfiguration(name: nil, sessionRole:)`
- `.tint`, a `.sheet` and `.animation`/`.sensoryFeedback` on the root
- interactive glass in the scroll content; full-width `.large` buttons
- `.id` + `.transition(.blurReplace)`, `.frame(maxWidth:)`, `.containerBackground(for: .navigation)`, a toolbar item, `ScrollViewReader`
- the app's Info.plist (dark style, portrait only, light status bar, indirect input events, launch screen colour) and asset catalog (global accent colour)
- `ENABLE_PREVIEWS = YES` (the app built as a debug dylib under a stub)

Removing the StoreKit configuration from the app's scheme doesn't restore
taps either. Remaining differences between the two projects are
project-wide build settings (`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`,
approachable concurrency, alternate app icons) and a local Swift package
linked statically.

`GlassTapsUITests` taps each button with the container on and off, and
with each ingredient switched off (launch arguments listed in
`GlassTapsApp.swift`); today every combination passes.

## Workaround

Keep the screen with the safe-area bar outside the `GlassEffectContainer`
(Trivia's `RootView` does this for its join screen).
