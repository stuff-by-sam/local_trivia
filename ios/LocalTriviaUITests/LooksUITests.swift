import XCTest

/// Finds Themes & Icons from the join screen, opens its groups, and picks a
/// theme and a set of answer markers — free, so each goes straight on — then
/// puts the game's own back, so no later run starts in them.
final class LooksUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testPicksAThemeAndMarkers() throws {
    let app = XCUIApplication()
    // Whatever an earlier run left on, this opens wearing the defaults.
    app.launchArguments += ["-nickname", "UITest", "-theme", "phosphor", "-markers", "classic"]
    app.launch()
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 3) { allow.tap() }

    let link = app.buttons["Themes & Icons"]
    XCTAssertTrue(link.waitForExistence(timeout: 10), "no way into Themes & Icons")
    link.tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Phosphor").waitForExistence(timeout: 5))
    XCTAssertFalse(element(in: app, containing: "$").exists, "nothing has a price")
    XCTAssertFalse(element(in: app, containing: "Restore Purchases").exists)
    // Every group starts closed, and the markers come before the icons.
    let themes = button(in: app, startingWith: "Themes")
    let markers = button(in: app, startingWith: "Answer Markers")
    let icons = button(in: app, startingWith: "App Icons")
    XCTAssertFalse(button(in: app, startingWith: "Amber,").exists, "the themes should start closed")
    XCTAssertLessThan(markers.frame.minY, icons.frame.minY, "the markers should sit above the icons")
    capture(app, "1 Groups closed")

    themes.tap()
    let amber = button(in: app, startingWith: "Amber,")
    XCTAssertTrue(amber.waitForExistence(timeout: 5), "the themes didn't open")
    amber.tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Amber").waitForExistence(timeout: 5), "the theme didn't go on")
    capture(app, "2 Wearing Amber")
    themes.tap()

    markers.tap()
    // The list makes rows only as they scroll in.
    app.swipeUp()
    let suits = button(in: app, startingWith: "Suits,")
    XCTAssertTrue(suits.waitForExistence(timeout: 5), "the markers didn't open")
    suits.tap()
    XCTAssertTrue(button(in: app, startingWith: "Answer Markers, Suits").waitForExistence(timeout: 5), "the markers didn't go on")
    capture(app, "3 Wearing Suits")

    // Back to the game's own.
    button(in: app, startingWith: "Classic,").tap()
    XCTAssertTrue(button(in: app, startingWith: "Answer Markers, Classic").waitForExistence(timeout: 5))
    let wearing = element(in: app, containing: "Wearing")
    for _ in 0..<4 where !wearing.exists {
      // A screen at a time: a swipe down at the top would close the sheet.
      app.collectionViews.firstMatch.swipeDown()
    }
    themes.tap()
    button(in: app, startingWith: "Phosphor,").tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Phosphor").waitForExistence(timeout: 5))

    app.buttons["Done"].tap()
    XCTAssertTrue(link.waitForExistence(timeout: 5))
    capture(app, "4 Back, in Phosphor")
  }

  /// A button in the list — not the join screen's toolbar behind it, whose
  /// "Themes & Icons" starts the same way.
  @MainActor
  private func button(in app: XCUIApplication, startingWith text: String) -> XCUIElement {
    app.collectionViews.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
  }

  @MainActor
  private func element(in app: XCUIApplication, containing text: String) -> XCUIElement {
    app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
  }

  @MainActor
  private func capture(_ app: XCUIApplication, _ name: String) {
    Thread.sleep(forTimeInterval: 0.7)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
