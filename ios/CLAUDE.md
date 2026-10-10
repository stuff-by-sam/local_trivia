# iOS app — working rules

## All UI uses the design system

Every screen, state and surface is built from the `DesignSystem` package
(`ios/DesignSystem`), per `ios/DESIGN.md`. In app code:

- **No literals for style.** No hex or RGB colours, no `.white/.black.opacity`,
  no `.system(size:)`, no numeric padding, spacing, frame sizes or corner
  radii, no `.tracking(n)`, no `withAnimation`/`.animation`, no
  `sensoryFeedback`/feedback generators, no `.shadow`, no
  `.preferredColorScheme`. Use `Palette` roles, `TextRole`/`TVRole`, `Space`,
  `Size`, `Radius`, `TVMetrics`, `Motion`, `Haptic` and `.glow(_:)`.
- **No tertiary text.** `.secondary` is the quietest text a player may need.
- **System components first.** Toolbars, sheets, forms, menus and buttons are
  the system's (`.glass`, `.glassProminent`, `ActionButton`). Everything else
  is layered glass, per DESIGN.md's "Layers": content sits on `.panel()` /
  `.glassCard(in:)` (clear or tinted by the screen's `glassClarity`), and
  display type and SF Symbol marks are glass characters (`GlassText`,
  `GlassCounter`, `GlassSymbol`). Body text, questions, answers and what the
  player types sit on glass; they're never made of it.
- **SF Symbols for every icon.** No text glyphs as icons. App icons are the
  exception: Apple's terms keep SF Symbols out of them.
- **A new style is a new token.** Add it to the package, give it a preview in
  every state (`Previews/ComponentPreviews.swift`), and document it in
  DESIGN.md — then use it.

`DesignSystemLintTests` enforces the first two; run the unit tests before
committing UI changes.

## Build and test

```
xcodebuild test -project LocalTrivia.xcodeproj -scheme LocalTrivia \
  -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

Check every API against the installed SDK before using it. On iOS 27.0,
glass buttons in a `safeAreaBar` inside a `GlassEffectContainer` don't
receive taps — keep such bars outside the container (see `RootView`).
