// swift-tools-version: 6.2
import PackageDescription

// The app's design language as code: colour roles, type, space, shape,
// motion, haptics, the backdrop, and the components every screen is built
// from. See ios/DESIGN.md. Nothing outside this package names a colour, a
// size, a radius, a curve or a haptic.
let package = Package(
  name: "DesignSystem",
  platforms: [.iOS("27.0")],
  products: [
    .library(name: "DesignSystem", targets: ["DesignSystem"])
  ],
  targets: [
    .target(
      name: "DesignSystem",
      swiftSettings: [
        .defaultIsolation(MainActor.self),
        .enableUpcomingFeature("MemberImportVisibility"),
      ]
    )
  ]
)
