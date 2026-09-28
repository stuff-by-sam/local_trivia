import DesignSystem
import SwiftUI
import Testing
import UIKit

@testable import LocalTrivia

/// What every theme has to keep, whoever adds the next one.
struct ThemeTests {
  /// The accent is text on the theme's ink, and `onAccentInk` is text on the
  /// accent wherever a control is lit with it. Both hold to WCAG AAA.
  @Test func everyThemeStaysReadable() {
    for theme in Theme.allCases {
      #expect(contrast(theme.accent, theme.ink) >= 7, "\(theme.rawValue): accent on its ink")
      #expect(contrast(Palette.onAccentInk, theme.accent) >= 7, "\(theme.rawValue): ink on a lit control")
      #expect(contrast(.white, theme.ink) >= 12, "\(theme.rawValue): text on its ink")
    }
  }

  /// A hosting phone's browser players wear its theme's accent, so the
  /// colour the web gets has to be the one the app draws.
  @Test func givesTheWebPlayerTheSameAccent() throws {
    #expect(Theme.phosphor.webAccent == "#56ff8a", "the web player's own green, so it stays unrotated")
    for theme in Theme.allCases {
      #expect(theme.webAccent.wholeMatch(of: /#[0-9a-f]{6}/) != nil, "\(theme.rawValue): \(theme.webAccent)")
      let hex = try #require(Int(theme.webAccent.dropFirst(), radix: 16))
      var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
      UIColor(theme.accent).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
      #expect([red, green, blue].map { Int(($0 * 255).rounded()) } == [hex >> 16 & 0xFF, hex >> 8 & 0xFF, hex & 0xFF], "\(theme.rawValue)")
    }
  }

  /// Every theme for sale has a home screen icon to go with it.
  @Test func everyThemeHasAnIconToMatch() {
    let icons = Set(AppIcon.allCases.map(\.rawValue))
    for theme in Theme.allCases where theme.productID != nil {
      #expect(icons.contains(theme.rawValue), "no \(theme.rawValue) icon")
    }
  }

  private func contrast(_ a: Color, _ b: Color) -> Double {
    let (one, other) = (luminance(a), luminance(b))
    return (max(one, other) + 0.05) / (min(one, other) + 0.05)
  }

  /// WCAG relative luminance, from the colour's sRGB components.
  private func luminance(_ color: Color) -> Double {
    var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
    UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    func linear(_ component: CGFloat) -> Double {
      let c = Double(component)
      return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
  }
}

/// What every set of answer markers has to keep, whoever adds the next one.
struct AnswerMarkersTests {
  /// Four shapes that exist, that differ, and that VoiceOver names apart —
  /// the shapes are how a colour-blind player tells the answers apart.
  @Test func everySetHasFourShapesToTellApart() {
    for markers in AnswerMarkers.allCases {
      let symbols = AnswerStyle.allCases.map { markers.symbol(for: $0) }
      let names = AnswerStyle.allCases.map { String(localized: markers.shapeName(for: $0)) }
      #expect(Set(symbols).count == 4, "\(markers.rawValue): \(symbols)")
      #expect(Set(names).count == 4, "\(markers.rawValue): \(names)")
      for symbol in symbols {
        #expect(UIImage(systemName: symbol) != nil, "\(markers.rawValue): no symbol \(symbol)")
      }
    }
  }

  /// Classic is what the TV's web presenter and the web player draw.
  @Test func classicIsTheWebGamesSet() {
    #expect(AnswerStyle.allCases.map { AnswerMarkers.classic.symbol(for: $0) } == ["circle.fill", "triangle.fill", "square.fill", "diamond.fill"])
    #expect(AnswerMarkers.classic.productID == nil, "every phone has it")
    #expect(AnswerMarkers.allCases.filter { $0 != .classic }.allSatisfy { $0.productID != nil })
  }
}
