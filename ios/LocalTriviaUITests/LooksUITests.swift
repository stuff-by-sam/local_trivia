import XCTest

/// Finds Themes & Icons in Settings, opens its groups, and picks a theme and
/// a set of answer markers — free, so each goes straight on — then puts the
/// game's own back, so no later run starts in them.
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
    let link = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Themes & Icons")).firstMatch
    XCTAssertTrue(link.waitForExistence(timeout: 5), "no way into Themes & Icons")
    link.tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Phosphor").waitForExistence(timeout: 5))
    XCTAssertFalse(element(in: app, containing: "$").exists, "nothing has a price")
    XCTAssertFalse(element(in: app, containing: "Restore Purchases").exists)
    // Every group starts closed, and the markers come before the icons.
    let themes = button(in: app, startingWith: "Themes,")
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
    // The list makes rows only as they scroll in, and the sets run on past
    // the screen: each row is scrolled to, and says itself that it's on.
    let suits = button(in: app, startingWith: "Suits,")
    XCTAssertTrue(reveal(suits, in: app), "the markers didn't open")
    suits.tap()
    XCTAssertTrue(isSelected(suits), "the markers didn't go on")
    capture(app, "3 Wearing Suits")

    // Back to the game's own.
    let classic = button(in: app, startingWith: "Classic,")
    XCTAssertTrue(reveal(classic, in: app))
    classic.tap()
    XCTAssertTrue(isSelected(classic), "the classic markers didn't go back on")
    let wearing = element(in: app, containing: "Wearing")
    for _ in 0..<4 where !wearing.exists {
      // A screen at a time: a swipe down at the top would close the sheet.
      app.collectionViews.firstMatch.swipeDown()
    }
    themes.tap()
    button(in: app, startingWith: "Phosphor,").tap()
    XCTAssertTrue(element(in: app, containing: "Wearing Phosphor").waitForExistence(timeout: 5))

    app.navigationBars["Themes & Icons"].buttons.firstMatch.tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5), "not back in Settings")
    app.buttons["Done"].tap()
    XCTAssertTrue(settings.waitForExistence(timeout: 5))
    capture(app, "4 Back, in Phosphor")
  }

  /// Drags the list a little at a time until `element` sits where it can be
  /// tapped, clear of the bars: down the list first, then back up.
  @MainActor
  private func reveal(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
    let window = app.windows.firstMatch.frame
    let band = (window.minY + window.height * 0.15)...(window.maxY - window.height * 0.15)
    for step in 0..<12 {
      if element.exists, element.isHittable, band.contains(element.frame.midY) { return true }
      let isDown = element.exists ? element.frame.midY > band.upperBound : step < 5
      let from = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: isDown ? 0.7 : 0.35))
      let to = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: isDown ? 0.4 : 0.65))
      from.press(forDuration: 0.05, thenDragTo: to)
    }
    return false
  }

  /// Whether `element` says it's the one on, within a few seconds.
  @MainActor
  private func isSelected(_ element: XCUIElement) -> Bool {
    let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: element)
    return XCTWaiter().wait(for: [selected], timeout: 5) == .completed
  }

  /// A button in the list — not Settings' row behind it, whose "Themes &
  /// Icons" starts the same way.
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
