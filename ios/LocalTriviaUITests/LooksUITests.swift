import XCTest

/// Finds Themes & Markers in Settings and tries on a theme and a set of
/// answer markers from the honeycomb — free, so each goes straight on —
/// makes a set of its own and deletes it again, then puts the game's own
/// back, so no later run starts in them.
final class LooksUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testPicksAThemeAndMarkers() throws {
    let app = XCUIApplication()
    // Whatever an earlier run left on, this opens wearing the defaults.
    app.launchArguments += ["-nickname", "UITest", "-termsAccepted", "1", "-tutorialSeen", "YES", "-theme", "phosphor", "-markers", "classic"]
    app.launch()

    let settings = app.buttons["Settings"]
    XCTAssertTrue(settings.waitForExistence(timeout: 10), "no way into Settings")
    settings.tap()
    let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Themes & Markers")).firstMatch
    XCTAssertTrue(link.waitForExistence(timeout: 5), "no way into Themes & Markers")
    link.tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Phosphor").waitForExistence(timeout: 5))
    XCTAssertFalse(element(in: app, containing: "$").exists, "nothing has a price")
    XCTAssertFalse(element(in: app, containing: "Restore Purchases").exists)
    XCTAssertFalse(element(in: app, containing: "App Icon").exists, "the icons are gone")
    XCTAssertTrue(bubble(in: app, named: "Make Your Own Theme").exists, "no way to make a theme")
    capture(app, "1 Themes")

    // A tap puts a theme on, and says so at the top.
    let amber = bubble(in: app, named: "Amber.")
    XCTAssertTrue(amber.waitForExistence(timeout: 5), "no Amber bubble")
    amber.tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Amber").waitForExistence(timeout: 5), "the theme didn't go on")
    XCTAssertTrue(isSelected(amber), "Amber's bubble isn't lit")
    capture(app, "2 Wearing Amber")

    app.buttons["Answer Markers"].tap()
    let suits = bubble(in: app, named: "Suits.")
    XCTAssertTrue(suits.waitForExistence(timeout: 5), "the markers didn't show")
    suits.tap()
    XCTAssertTrue(isSelected(suits), "the markers didn't go on")
    XCTAssertTrue(element(in: app, containing: "Using Suits").exists)
    capture(app, "3 Using Suits")

    // Four taps make a set: each shape goes beside the lit key, A to D.
    bubble(in: app, named: "Make Your Own Markers").tap()
    XCTAssertTrue(app.navigationBars["New Markers"].waitForExistence(timeout: 5), "no markers editor")
    for shape in ["pentagon", "hexagon", "octagon", "star"] {
      let cell = app.buttons[shape]
      XCTAssertTrue(cell.waitForExistence(timeout: 5), "no \(shape) in the library")
      cell.tap()
    }
    XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "D, star")).firstMatch.exists, "the star isn't beside D")
    capture(app, "4 New markers")
    app.navigationBars["New Markers"].buttons["Save"].tap()
    let own = bubble(in: app, named: "My Markers")
    XCTAssertTrue(own.waitForExistence(timeout: 5), "the new set isn't in the honeycomb")
    XCTAssertTrue(isSelected(own), "the new set didn't go on")

    // Deleting the set being used puts Classic back on.
    own.press(forDuration: 1)
    let delete = app.buttons["Delete"]
    XCTAssertTrue(delete.waitForExistence(timeout: 5), "no menu on the set")
    delete.tap()
    XCTAssertTrue(element(in: app, containing: "Using Classic").waitForExistence(timeout: 5), "Classic didn't go back on")
    XCTAssertTrue(element(in: app, containing: "Deleted").exists, "no undo offered")

    // Back to the game's own.
    app.buttons["Themes"].tap()
    bubble(in: app, named: "Phosphor.").tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Phosphor").waitForExistence(timeout: 5))

    app.navigationBars["Themes & Markers"].buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "not back in Settings")
    app.buttons["Done"].tap()
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    capture(app, "5 Back, in Phosphor")
  }

  /// A bubble, by the start of what VoiceOver calls it.
  @MainActor
  private func bubble(in app: XCUIApplication, named name: String) -> XCUIElement {
    app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
  }

  /// Whether `element` says it's the one on, within a few seconds.
  @MainActor
  private func isSelected(_ element: XCUIElement) -> Bool {
    let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
    return XCTWaiter().wait(for: [selected], timeout: 5) == .completed
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
