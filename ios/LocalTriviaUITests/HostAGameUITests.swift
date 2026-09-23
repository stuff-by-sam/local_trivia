import XCTest

/// Hosts a game on this phone and plays it through, end to end: write a round,
/// start hosting, play a question as the host, standings, podium, and stop
/// hosting. Games are only ever hosted from a phone, so this needs nothing but
/// the simulator.
final class HostAGameUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testHostsAndPlaysAGame() throws {
    let app = XCUIApplication()
    // Argument-domain defaults: sets the remembered nickname for this launch only.
    app.launchArguments += ["-nickname", "UITest"]
    app.launch()
    allowLocalNetworkIfAsked()

    let host = app.buttons["Host a Game"]
    XCTAssertTrue(host.waitForExistence(timeout: 10))
    capture(app, "1 Join")
    host.tap()
    XCTAssertTrue(app.buttons["Start Hosting"].waitForExistence(timeout: 10))

    // The round is kept between launches: start from an empty one.
    let deleteAll = app.buttons["Delete All…"]
    if deleteAll.exists {
      deleteAll.tap()
      app.buttons["Delete All Questions"].tap()
    }

    app.buttons["Write a Question"].tap()
    app.field("What's the question?").typeIn("Which planet has the most moons?")
    for (letter, answer) in zip(["A", "B", "C", "D"], ["Saturn", "Jupiter", "Uranus", "Neptune"]) {
      app.field("Answer \(letter)").typeIn(answer)
    }
    app.buttons["Save"].tap()
    capture(app, "2 Round")

    app.buttons["Start Hosting"].tap()
    XCTAssertTrue(app.element(containing: "You're in").waitForExistence(timeout: 15), "never took a seat in its own game")
    capture(app, "3 Lobby")

    // The TV guide: how to put the game on one, and that none is connected yet.
    app.buttons["Host controls"].tap()
    app.buttons["Show on a TV…"].tap()
    XCTAssertTrue(app.element(containing: "No TV yet").waitForExistence(timeout: 5), "no TV guide")
    capture(app, "3b TV guide")
    app.buttons["Done"].tap()

    app.button(beginningWith: "Start Game").tap()
    let answer = app.button(beginningWith: "A,")
    XCTAssertTrue(answer.waitForExistence(timeout: 10), "the question never arrived")
    capture(app, "4 Question")
    // The host is the only player, so answering ends the question at once.
    answer.tap()
    let verdict = app.staticTexts.matching(NSPredicate(format: "label MATCHES[c] %@", "correct")).firstMatch
    XCTAssertTrue(verdict.waitForExistence(timeout: 10), "no result, or not the right one")
    capture(app, "5 Result")

    app.button(beginningWith: "Show Standings").tap()
    XCTAssertTrue(app.element(containing: "Your position").waitForExistence(timeout: 10))
    capture(app, "6 Standings")

    app.button(beginningWith: "Final Results").tap()
    XCTAssertTrue(app.element(containing: "Game over").waitForExistence(timeout: 10), "never reached the podium")
    capture(app, "7 Final")

    app.buttons["Host controls"].tap()
    app.buttons["Stop Hosting"].tap()
    app.buttons["End the Game for Everyone"].tap()
    XCTAssertTrue(host.waitForExistence(timeout: 10), "never went back to the join screen")
  }

  /// A fresh install may ask before touching the local network.
  @MainActor
  private func allowLocalNetworkIfAsked() {
    let allow = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
    if allow.waitForExistence(timeout: 3) { allow.tap() }
  }

  /// Screens cross-fade in; an element exists before its screen has settled.
  @MainActor
  private func capture(_ app: XCUIApplication, _ name: String) {
    Thread.sleep(forTimeInterval: 0.7)
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}

extension XCUIApplication {
  @MainActor
  fileprivate func element(containing text: String) -> XCUIElement {
    descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
  }

  /// Action buttons carry an icon after their title, so match the start.
  @MainActor
  fileprivate func button(beginningWith text: String) -> XCUIElement {
    buttons.matching(NSPredicate(format: "label BEGINSWITH %@", text)).firstMatch
  }

  /// A text field by its title or placeholder. Multi-line fields surface as
  /// text views, so look at both.
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
