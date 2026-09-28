import XCTest

/// Finds the shop from the join screen, opens its groups, tries a theme and a
/// set of answer markers on, and leaves without buying — which takes both off
/// again. Needs no App Store: trying on works whether or not prices load.
final class ShopUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testTriesOnAThemeAndMarkers() throws {
    let app = XCUIApplication()
    // Whatever an earlier run left on, the shop opens wearing the defaults.
    app.launchArguments += ["-nickname", "UITest", "-theme", "phosphor", "-markers", "classic"]
    app.launch()
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 3) { allow.tap() }

    let shopLink = app.buttons["Themes & Icons"]
    XCTAssertTrue(shopLink.waitForExistence(timeout: 10), "no way into the shop")
    shopLink.tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Phosphor").waitForExistence(timeout: 5))
    let bundle = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Everything,")).firstMatch
    XCTAssertTrue(bundle.exists, "no bundle on offer")
    // Every group starts closed.
    let amber = button(in: app, startingWith: "Amber,")
    XCTAssertFalse(amber.exists, "the themes should start closed")
    capture(app, "1 Shop, groups closed")

    button(in: app, startingWith: "Themes").tap()
    XCTAssertTrue(amber.waitForExistence(timeout: 5), "the themes didn't open")
    amber.tap()
    XCTAssertTrue(element(in: app, containing: "Trying on Amber").waitForExistence(timeout: 5), "the theme didn't go on")
    capture(app, "2 Themes open, trying on Amber")
    button(in: app, startingWith: "Themes").tap()

    // The list makes rows only as they scroll in: bring the group up first.
    app.swipeUp()
    button(in: app, startingWith: "Answer Markers").tap()
    app.swipeUp()
    let suits = button(in: app, startingWith: "Suits,")
    XCTAssertTrue(suits.waitForExistence(timeout: 5), "the markers didn't open")
    capture(app, "3 Markers open")
    suits.tap()
    // Back up to the showcase, a screen at a time: a swipe down at the top
    // would close the sheet.
    let both = element(in: app, containing: "Trying on Amber with Suits")
    for _ in 0..<4 where !both.exists {
      app.collectionViews.firstMatch.swipeDown()
    }
    XCTAssertTrue(both.waitForExistence(timeout: 5), "the markers didn't go on")
    capture(app, "4 Trying on Amber with Suits")

    app.buttons["Done"].tap()
    XCTAssertTrue(shopLink.waitForExistence(timeout: 5))
    capture(app, "5 Back, in Phosphor")
  }

  /// A button in the shop's list — not the join screen's toolbar behind it,
  /// whose "Themes & Icons" starts the same way.
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
