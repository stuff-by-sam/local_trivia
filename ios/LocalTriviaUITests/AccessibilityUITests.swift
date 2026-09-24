import XCTest

/// Every screen one phone can reach — joining, the shop, setting up a round,
/// hosting it, playing it through and stopping — at the settings that
/// stretch a layout most: the largest accessibility text size, Increase
/// Contrast, and right-to-left. Each screen is attached as a screenshot and
/// audited for clipped text, missing labels and undersized targets.
///
/// The player-only screens (a guest's lobby, joining mid-question) need a
/// second phone; their previews cover them.
final class AccessibilityUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testEveryScreenAtTheLargestTextSize() throws {
    try captureEveryScreen(as: "AX5", arguments: ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"], failsOnClippedText: true)
  }

  @MainActor
  func testEveryScreenWithIncreaseContrast() throws {
    try captureEveryScreen(as: "Increase Contrast", arguments: ["-increaseContrast", "YES"])
  }

  @MainActor
  func testEveryScreenRightToLeft() throws {
    try captureEveryScreen(as: "RTL", arguments: ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
  }

  // MARK: - The walk

  @MainActor
  /// Clipped text fails the walk only at AX5, where truncation is the risk:
  /// at the default size the audit flags system list rows that draw in full.
  private func captureEveryScreen(as setting: String, arguments: [String], failsOnClippedText: Bool = false) throws {
    let app = XCUIApplication()
    app.launchArguments += ["-nickname", "UITest"] + arguments
    app.launch()
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 3) { allow.tap() }
    var screen = Screens(app: app, setting: setting, failsOnClippedText: failsOnClippedText, test: self)

    let host = app.buttons["Host a Game"]
    XCTAssertTrue(host.waitForExistence(timeout: 10))
    try screen.capture("Join")

    app.buttons["Themes & Icons"].tap()
    XCTAssertTrue(app.element(containing: "Wearing").waitForExistence(timeout: 5))
    try screen.capture("Shop")
    app.buttons["Done"].tap()

    host.tap()
    XCTAssertTrue(app.buttons["Start Hosting"].waitForExistence(timeout: 10))
    // The round is kept between launches: start from an empty one.
    let deleteAll = app.buttons["Delete All"]
    if app.reveal(deleteAll) { deleteAll.tap() }
    try screen.capture("Round, empty")

    XCTAssertTrue(app.reveal(app.buttons["Write a Question"]))
    app.buttons["Write a Question"].tap()
    try screen.capture("New question")
    app.field("What's the question?").typeIn("Which planet has the most moons?")
    XCTAssertTrue(app.reveal(app.buttons["Mark A as the right answer"]))
    app.buttons["Mark A as the right answer"].tap()
    for (letter, answer) in zip(["A", "B", "C", "D"], ["Saturn", "Jupiter", "Uranus", "Neptune"]) {
      let field = app.field("Answer \(letter)")
      XCTAssertTrue(app.reveal(field))
      field.typeIn(answer)
    }
    try screen.capture("New question, filled in")
    // It saves on the way out: no Save button.
    app.navigationBars["New Question"].buttons.firstMatch.tap()
    try screen.capture("Round, one question")

    let drafting = app.buttons["Draft with Apple Intelligence"]
    if app.reveal(drafting) {
      drafting.tap()
      XCTAssertTrue(app.navigationBars["Draft Questions"].waitForExistence(timeout: 5))
      try screen.capture("Draft questions")
      app.navigationBars["Draft Questions"].buttons["Cancel"].tap()
    }

    app.buttons["Start Hosting"].tap()
    XCTAssertTrue(app.element(containing: "In the game").waitForExistence(timeout: 15), "never took a seat in its own game")
    try screen.capture("Host lobby")

    app.buttons["Host controls"].tap()
    try screen.capture("Host menu", audit: false)
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Players")).firstMatch.tap()
    XCTAssertTrue(app.navigationBars["Players"].waitForExistence(timeout: 5))
    try screen.capture("Players")
    app.buttons["Done"].tap()

    app.buttons["Host controls"].tap()
    app.buttons["Show Join Code"].tap()
    XCTAssertTrue(app.element(containing: "Open Trivia on the same Wi-Fi").waitForExistence(timeout: 5))
    try screen.capture("Join code")
    app.swipeDown(velocity: .fast)

    app.buttons["Host controls"].tap()
    app.buttons["Show on a TV…"].tap()
    XCTAssertTrue(app.element(containing: "No TV yet").waitForExistence(timeout: 5))
    try screen.capture("Show on a TV")
    app.buttons["Done"].tap()

    app.button(beginningWith: "Start Game").tap()
    let answer = app.button(beginningWith: "A,")
    XCTAssertTrue(answer.waitForExistence(timeout: 10), "the question never arrived")
    try screen.capture("Question")
    // The host is the only player, so answering ends the question at once.
    answer.tap()
    XCTAssertTrue(app.element(containing: "pts").waitForExistence(timeout: 10), "no result")
    try screen.capture("Result")

    XCTAssertTrue(app.element(containing: "Your position").waitForExistence(timeout: 15))
    try screen.capture("Standings")

    app.button(beginningWith: "Final Results").tap()
    XCTAssertTrue(app.element(containing: "Game over").waitForExistence(timeout: 10))
    try screen.capture("Final")

    app.buttons["Host controls"].tap()
    app.buttons["Stop Hosting"].tap()
    XCTAssertTrue(app.buttons["End the Game for Everyone"].waitForExistence(timeout: 5))
    try screen.capture("Stop hosting?", audit: false)
    app.buttons["End the Game for Everyone"].tap()
    XCTAssertTrue(host.waitForExistence(timeout: 10))
    try screen.capture("Join, after hosting")
  }
}

/// Captures each screen — a screenshot, its element tree, and what the
/// accessibility audit finds on it.
@MainActor
private struct Screens {
  let app: XCUIApplication
  let setting: String
  let failsOnClippedText: Bool
  let test: XCTestCase
  private var count = 0

  init(app: XCUIApplication, setting: String, failsOnClippedText: Bool, test: XCTestCase) {
    self.app = app
    self.setting = setting
    self.failsOnClippedText = failsOnClippedText
    self.test = test
  }

  /// Screens cross-fade in: an element exists before its screen has settled.
  mutating func capture(_ name: String, audit: Bool = true) throws {
    Thread.sleep(forTimeInterval: 0.8)
    count += 1
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = String(format: "%@ %02d %@", setting, count, name)
    shot.lifetime = .keepAlways
    test.add(shot)
    // What VoiceOver reads, in the order it reads it.
    let tree = XCTAttachment(string: app.debugDescription)
    tree.name = String(format: "%@ %02d %@ — elements", setting, count, name)
    tree.lifetime = .keepAlways
    test.add(tree)
    guard audit else { return }
    var found: [String] = []
    // A finding fails the test but not the walk: every screen is audited,
    // and each one's findings attached.
    let stops = test.continueAfterFailure
    test.continueAfterFailure = true
    defer {
      test.continueAfterFailure = stops
      let audit = XCTAttachment(string: found.isEmpty ? "No findings." : found.joined(separator: "\n"))
      audit.name = String(format: "%@ %02d %@ — audit", setting, count, name)
      audit.lifetime = .keepAlways
      test.add(audit)
    }
    // Where clipped text is reported but doesn't fail: text partly scrolled
    // under the navigation bar or off the screen, which the scroll view
    // cuts, not its layout; and rows of the system's lists, which the audit
    // flags from run to run although they wrap in full.
    let window = app.windows.firstMatch.frame
    let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : window.minY
    let visible = CGRect(x: window.minX, y: top, width: window.width, height: window.maxY - top)
    let lists = app.collectionViews.allElementsBoundByIndex.map(\.frame)
    try app.performAccessibilityAudit(for: [.textClipped, .dynamicType, .sufficientElementDescription, .hitRegion, .trait]) { [failsOnClippedText] issue in
      let clipped = issue.auditType == .textClipped
      // An element can be gone by the time it's reported: reading it then fails.
      let frame = issue.element.flatMap { $0.exists ? $0.frame : nil } ?? .null
      let excused = clipped && (!failsOnClippedText || !visible.contains(frame) || lists.contains { $0.contains(frame) })
      let expected = Self.isExpected(issue) || excused
      let described = issue.element.flatMap { $0.exists ? String($0.debugDescription.prefix(160)) : nil } ?? "no element"
      found.append("\(name): \(expected ? "expected" : "FAILED") \(issue.compactDescription) — \(described)")
      return expected
    }
  }

  /// What the audit reports that's by design, and so doesn't fail the test.
  /// Everything it finds is still in the report.
  private static func isExpected(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
    // Nothing on screen to point at: text scrolled past the fold, or an
    // element that's gone by the time it's reported.
    guard let element = issue.element, element.exists else { return true }
    switch issue.auditType {
    // Bars, display figures and the wordmark stop growing on purpose
    // (DESIGN.md, "Type"); a bar offers the Large Content Viewer instead.
    case .dynamicType: return true
    // A field's placeholder is an example, not something to read in full.
    case .textClipped: return element.elementType == .textField || element.elementType == .textView
    default: return false
    }
  }
}

private enum Size {
  /// How far above the keyboard or action bar a field must sit to take a tap.
  static let tapMargin: CGFloat = 24
}

extension XCUIApplication {
  @MainActor
  fileprivate func element(containing text: String) -> XCUIElement {
    descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
  }

  @MainActor
  fileprivate func button(beginningWith text: String) -> XCUIElement {
    buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
  }

  /// Scrolls until `element` sits in the upper middle of the screen — clear
  /// of the navigation bar, the action bar and the keyboard. Lists only build
  /// the rows in view, so until it exists this looks further down, and turns
  /// back when the list stops moving.
  @MainActor
  fileprivate func reveal(_ element: XCUIElement) -> Bool {
    let window = windows.firstMatch.frame
    let list = collectionViews.firstMatch.exists ? collectionViews.firstMatch : scrollViews.firstMatch
    var showMoreBelow = true
    var turns = 0
    for _ in 0..<30 {
      // Below the navigation bar; above the keyboard, or the action bar.
      let top = window.minY + window.height * 0.15
      let bottom = keyboards.firstMatch.exists ? keyboards.firstMatch.frame.minY : window.maxY - window.height * 0.2
      let band = top...max(top, bottom - Size.tapMargin)
      if element.exists, element.isHittable, band.contains(element.frame.midY) { return true }
      if element.exists, !element.frame.isEmpty { showMoreBelow = element.frame.midY > band.upperBound }
      let before = list.staticTexts.firstMatch.frame
      let from = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: showMoreBelow ? 0.5 : 0.25))
      let to = coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: showMoreBelow ? 0.25 : 0.5))
      from.press(forDuration: 0.05, thenDragTo: to)
      if !element.exists, list.staticTexts.firstMatch.frame == before {
        turns += 1
        guard turns < 3 else { return false }
        showMoreBelow.toggle()
      }
    }
    return false
  }

  @MainActor
  fileprivate func field(_ title: String) -> XCUIElement {
    let types = [XCUIElement.ElementType.textField, .textView].map { NSNumber(value: $0.rawValue) }
    let named = NSPredicate(format: "elementType IN %@ AND (label == %@ OR placeholderValue == %@)", types, title, title)
    return descendants(matching: .any).matching(named).firstMatch
  }
}

extension XCUIElement {
  @MainActor
  fileprivate func typeIn(_ text: String) {
    XCTAssertTrue(waitForExistence(timeout: 5), "no field to type into")
    tap()
    typeText(text)
  }
}
