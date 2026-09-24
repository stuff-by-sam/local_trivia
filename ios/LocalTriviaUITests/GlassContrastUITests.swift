import CoreGraphics
import XCTest

/// The text on the glass the player needs most — a chosen answer, the
/// primary action, the undo toast — measured against the glass behind it,
/// in all ten themes, from what's actually on screen.
///
/// Glass takes its colour from the phone's settings as well as the app's:
/// the Liquid Glass slider (clear to tinted), Reduce Transparency and
/// Increase Contrast. None of them can be set or read from a test, so this
/// measures under whatever the simulator is set to; run it once per setting.
/// It fails below WCAG AA for text, 4.5:1, and attaches every screenshot
/// with a table of what it measured.
final class GlassContrastUITests: XCTestCase {
  private static let themes = ProcessInfo.processInfo.environment["CONTRAST_THEMES"].flatMap { $0.isEmpty ? nil : $0.split(separator: ",").map(String.init) } ?? ["phosphor", "amber", "cobalt", "synthwave", "noir", "gold", "holographic", "chalkboard", "glass", "titanium"]
  private static let minimum = 4.5

  override func setUp() {
    continueAfterFailure = true
  }

  @MainActor
  func testGlassTextHoldsContrastInEveryTheme() throws {
    var table = ["theme\tcomponent\tratio"]
    for theme in Self.themes {
      // Each answer chosen, lit in its colour, before the reveal.
      for (index, letter) in ["A", "B", "C", "D"].enumerated() {
        let question = launch("question.chosen", theme: theme, extra: ["-chosen", "\(index)"])
        let chosen = question.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "\(letter),")).firstMatch
        XCTAssertTrue(chosen.waitForExistence(timeout: 10), "\(theme): no chosen answer")
        let shot = capture(question, "\(theme) chosen \(letter)")
        let frames = XCTAttachment(string: question.buttons.allElementsBoundByIndex.map { "\($0.label) \($0.frame)" }.joined(separator: "\n"))
        frames.name = "\(theme) chosen \(letter) frames"
        frames.lifetime = .keepAlways
        add(frames)
        // The answer's text, between its key and its checkmark.
        let answer = chosen.frame.insetBy(dx: 0, dy: 8).inset(leading: 68, trailing: 44)
        table.append(measure(shot, answer, "\(theme)\tchosen \(letter)"))
      }

      // The primary action: the host's Start Game.
      let lobby = launch("host.lobby", theme: theme)
      let start = lobby.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start Game")).firstMatch
      XCTAssertTrue(start.waitForExistence(timeout: 10), "\(theme): no Start Game")
      let lobbyShot = capture(lobby, "\(theme) primary action")
      table.append(measure(lobbyShot, start.frame.insetBy(dx: 16, dy: 8), "\(theme)\tprimary action"))

      // The undo toast after leaving a game: its message, and its button.
      // It goes by itself after a few seconds, so it's measured at once.
      let join = launch("join.left", theme: theme)
      let undo = join.buttons.matching(NSPredicate(format: "label ==[c] %@", "Undo")).firstMatch
      XCTAssertTrue(undo.waitForExistence(timeout: 5), "\(theme): no undo toast")
      let message = join.staticTexts.matching(NSPredicate(format: "label BEGINSWITH[c] %@", "Left")).firstMatch
      let toastShot = capture(join, "\(theme) undo toast")
      table.append(measure(toastShot, message.frame.insetBy(dx: -4, dy: -6), "\(theme)\tundo message"))
      table.append(measure(toastShot, undo.frame.insetBy(dx: 6, dy: 5), "\(theme)\tundo button"))
    }
    let report = XCTAttachment(string: table.joined(separator: "\n"))
    report.name = "Contrast"
    report.lifetime = .keepAlways
    add(report)
  }

  @MainActor
  private func launch(_ screen: String, theme: String, extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-screen", screen, "-theme", theme] + extra
    app.launch()
    return app
  }

  @MainActor
  private func capture(_ app: XCUIApplication, _ name: String) -> XCUIScreenshot {
    let shot = app.screenshot()
    let attachment = XCTAttachment(screenshot: shot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
    return shot
  }

  /// The contrast of the text in `rect` (points) with what's behind it, and
  /// a failure below the minimum. Returns a row for the report.
  @MainActor
  private func measure(_ shot: XCUIScreenshot, _ rect: CGRect, _ row: String) -> String {
    guard let ratio = Contrast.ratio(in: shot.image, rect: rect) else {
      XCTFail("\(row): nothing to measure in \(rect)")
      return "\(row)\t—"
    }
    XCTAssertGreaterThanOrEqual(ratio, Self.minimum, "\(row.replacingOccurrences(of: "\t", with: " ")): \(ratio.formatted(.number.precision(.fractionLength(2)))):1")
    return "\(row)\t\(ratio.formatted(.number.precision(.fractionLength(2))))"
  }
}

extension CGRect {
  /// Inset on the leading and trailing edges alone.
  fileprivate func inset(leading: CGFloat, trailing: CGFloat) -> CGRect {
    CGRect(x: minX + leading, y: minY, width: max(0, width - leading - trailing), height: height)
  }
}

/// WCAG contrast from a screenshot's pixels.
enum Contrast {
  /// The background is what's around the text — the median of the region's
  /// border, which is drawn clear of it — and the text is the tail furthest
  /// from that, where glyphs are solid rather than anti-aliased (the 1st or
  /// 99th percentile).
  static func ratio(in image: UIImage, rect: CGRect) -> Double? {
    guard let cgImage = image.cgImage else { return nil }
    let scale = image.scale
    let pixels = CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale).integral
      .intersection(CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height))
    guard pixels.width > 4, pixels.height > 4, let crop = cgImage.cropping(to: pixels) else { return nil }

    // Drawn into sRGB, whatever the screenshot's own colour space.
    let width = crop.width, height = crop.height
    var bytes = [UInt8](repeating: 0, count: width * height * 4)
    guard let context = CGContext(
      data: &bytes, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { return nil }
    context.draw(crop, in: CGRect(x: 0, y: 0, width: width, height: height))

    var luminances: [Double] = []
    var border: [Double] = []
    luminances.reserveCapacity(width * height)
    for y in 0..<height {
      for x in 0..<width {
        let index = (y * width + x) * 4
        let value = luminance(bytes[index], bytes[index + 1], bytes[index + 2])
        luminances.append(value)
        if x == 0 || y == 0 || x == width - 1 || y == height - 1 { border.append(value) }
      }
    }
    luminances.sort()
    border.sort()
    let background = border[border.count / 2]
    let darkest = luminances[luminances.count / 100]
    let lightest = luminances[luminances.count * 99 / 100]
    let text = (background - darkest) > (lightest - background) ? darkest : lightest
    return (max(text, background) + 0.05) / (min(text, background) + 0.05)
  }

  private static func luminance(_ r: UInt8, _ g: UInt8, _ b: UInt8) -> Double {
    func linear(_ c: UInt8) -> Double {
      let v = Double(c) / 255
      return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
  }
}
