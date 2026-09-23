import XCTest

/// Finds the shop from the join screen, tries a theme on, and leaves without
/// buying — which takes the theme off again. Needs no App Store: trying on
/// works whether or not prices load.
final class ShopUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testTriesOnATheme() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-nickname", "UITest"]
    app.launch()
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 3) { allow.tap() }

    let shopLink = app.buttons["Themes & Icons"]
    XCTAssertTrue(shopLink.waitForExistence(timeout: 10), "no way into the shop")
    shopLink.tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Phosphor").waitForExistence(timeout: 5))
    let bundle = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Everything,")).firstMatch
    XCTAssertTrue(bundle.exists, "no bundle on offer")
    capture(app, "1 Shop")

    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Amber,")).firstMatch.tap()
    XCTAssertTrue(element(in: app, containing: "Trying on Amber").waitForExistence(timeout: 5), "the theme didn't go on")
    capture(app, "2 Trying on Amber")

    app.swipeUp()
    capture(app, "3 Icons")

    app.buttons["Done"].tap()
    XCTAssertTrue(shopLink.waitForExistence(timeout: 5))
    capture(app, "4 Back, in Phosphor")
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
