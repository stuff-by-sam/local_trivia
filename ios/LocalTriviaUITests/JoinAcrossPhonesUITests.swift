import XCTest

/// One phone hosts and another joins it by its PIN alone: nothing looked for
/// until the PIN's typed, the game found on the network while it is, and in.
/// Needs two simulators on this Mac — so it runs only when asked, with
/// `TEST_RUNNER_TRIVIA_TWO_PHONES=1`: the host's test on one simulator, and
/// while it waits, the player's on the other.
final class JoinAcrossPhonesUITests: XCTestCase {
  private let pin = "4821"

  override func setUpWithError() throws {
    continueAfterFailure = false
    try XCTSkipUnless(ProcessInfo.processInfo.environment["TRIVIA_TWO_PHONES"] == "1", "Needs a second simulator.")
  }

  /// Hosts a one-question round with a known PIN, and waits for a player.
  @MainActor
  func testHostsForAnotherPhone() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-nickname", "Host", "-termsAccepted", "1", "-tutorialSeen", "YES", "-hostPIN", pin]
    app.launch()

    let host = app.buttons["Host a Game"]
    XCTAssertTrue(host.waitForExistence(timeout: 10))
    host.tap()
    XCTAssertTrue(app.buttons["Start Hosting"].waitForExistence(timeout: 10))
    if !app.buttons["Start Hosting"].isEnabled {
      app.buttons["Write a Question"].tap()
      app.field("What's the question?").typeIn("Which planet has the most moons?")
      for letter in ["A", "B", "C", "D"] {
        app.field("Answer \(letter)").typeIn("Answer \(letter)")
      }
      app.buttons["Mark A as the right answer"].tap()
      app.navigationBars["New Question"].buttons.firstMatch.tap()
    }
    app.buttons["Start Hosting"].tap()
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 3) { allow.tap() }
    // Labels read as they're drawn: "IN THE GAME · 2".
    let arrived = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "In the game · 2")).firstMatch
    let joined = arrived.waitForExistence(timeout: 180)
    attach(app, joined ? "Host: a player's in" : "Host: nobody came")
    XCTAssertTrue(joined, "nobody joined")
  }

  /// Types the host's PIN — no game picked, nothing scanned — and is in.
  @MainActor
  func testJoinsByPIN() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-nickname", "Guest", "-termsAccepted", "1", "-tutorialSeen", "YES"]
    app.launch()

    let pinField = app.textFields["Game PIN"]
    XCTAssertTrue(pinField.waitForExistence(timeout: 10))
    XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "Looking")).firstMatch.exists, "looking before anyone asked")
    attach(app, "Player: at rest")
    pinField.tap()
    // Looking starts here, so this is where Local Network is asked for.
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 3) {
      allow.tap()
      pinField.tap()
    }
    pinField.typeText(String(pin.prefix(2)))
    attach(app, "Player: typing the PIN")
    pinField.typeText(String(pin.dropFirst(2)))
    let joined = app.staticTexts.matching(NSPredicate(format: "label ==[c] %@", "You're in")).firstMatch.waitForExistence(timeout: 30)
    attach(app, joined ? "Player: in" : "Player: still out")
    if !joined {
      // What the join screen says, for whoever reads the failure.
      let said = app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
      let typed = pinField.exists ? pinField.value as? String ?? "" : "gone"
      XCTFail("never got into the game; the PIN reads “\(typed)”; the screen says: \(said)")
    }
  }

  @MainActor
  private func attach(_ app: XCUIApplication, _ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}

extension XCUIApplication {
  /// A text field by its title or placeholder; multi-line ones are text views.
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
