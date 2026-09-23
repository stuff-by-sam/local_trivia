import SwiftUI

/// The four answer options: colour + shape + letter, never colour alone, so
/// they stay distinguishable for colour-blind players.
///
/// Same set, same order as the web game (`PAL` in public/shared/common.js), so
/// "B, the cyan triangle" means the same thing wherever trivia is played.
enum AnswerStyle: Int, CaseIterable, Identifiable {
  case a, b, c, d

  var id: Int { rawValue }

  var letter: String { ["A", "B", "C", "D"][rawValue] }

  var symbol: String { ["circle.fill", "triangle.fill", "square.fill", "diamond.fill"][rawValue] }

  var shapeName: LocalizedStringResource {
    switch self {
    case .a: "circle"
    case .b: "triangle"
    case .c: "square"
    case .d: "diamond"
    }
  }

  var color: Color {
    switch self {
    case .a: .broadcastGreen
    case .b: Color(hex: 0x55E6FF)
    case .c: Color(hex: 0xFFB347)
    case .d: Color(hex: 0xFF6AD5)
    }
  }
}

extension Color {
  /// The game's accent: phosphor green.
  static let broadcastGreen = Color(hex: 0x56FF8A)
  static let broadcastRed = Color(hex: 0xFF6A6A)
  static let broadcastGold = Color(hex: 0xFFB347)
  static let broadcastInk = Color(hex: 0x04080A)

  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }
}

extension EnvironmentValues {
  /// The game's accent, for headings, the cursor and the lit edge of controls.
  /// Views read it from here rather than naming the colour.
  @Entry var accent: Color = .broadcastGreen
}
