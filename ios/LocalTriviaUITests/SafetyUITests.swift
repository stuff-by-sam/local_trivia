import XCTest

/// What App Review's guideline 1.2 asks to see: the terms before anyone plays,
/// and a player's way to flag content and block. Each step is attached as a
/// screenshot.
final class SafetyUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  /// Nobody hosts or joins before agreeing; the terms are under Safety after.
  @MainActor
  func testTermsComeFirst() throws {
    let app = XCUIApplication()
    // As a first launch: the agreement from any earlier run doesn't count.
    app.launchArguments += ["-nickname", "UITest", "-termsAccepted", "0", "-tutorialSeen", "YES"]
    app.launch()

    let agree = app.buttons["Agree and Continue"]
    XCTAssertTrue(agree.waitForExistence(timeout: 10), "no terms on first launch")
    XCTAssertTrue(app.staticTexts["No objectionable content. No abusive users."].exists)
    XCTAssertFalse(app.buttons["Host a Game"].isHittable, "the join screen is reachable before agreeing")
    attach(app, "1 Terms")
    agree.tap()

    XCTAssertTrue(app.buttons["Host a Game"].waitForExistence(timeout: 5))
    app.buttons["Safety"].tap()
    XCTAssertTrue(app.buttons["Terms of Use"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Report a Problem"].exists)
    attach(app, "2 Safety")
  }

  /// A player in a question: report it, then block the host.
  @MainActor
  func testAPlayerCanReportAndBlock() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-screen", "question"]
    app.launch()

    let menu = app.buttons["Game menu"]
    XCTAssertTrue(menu.waitForExistence(timeout: 10), "no game menu for a player")
    menu.tap()
    XCTAssertTrue(app.buttons["Report Question…"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["Report or Block a Player…"].exists)
    XCTAssertTrue(app.buttons["Block Host…"].exists)
    XCTAssertTrue(app.buttons["Leave Game"].exists)
    attach(app, "3 Game menu")

    app.buttons["Report Question…"].tap()
    XCTAssertTrue(app.buttons["Send Report"].waitForExistence(timeout: 5), "no report sheet")
    XCTAssertTrue(app.buttons["Hateful or discriminatory"].exists, "no reasons to pick from")
    attach(app, "4 Report")
    app.buttons["Cancel"].tap()

    menu.tap()
    app.buttons["Block Host…"].tap()
    let block = app.buttons["Block and Report"]
    XCTAssertTrue(block.waitForExistence(timeout: 5), "no confirmation")
    attach(app, "5 Block host")
  }

  private func attach(_ app: XCUIApplication, _ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
