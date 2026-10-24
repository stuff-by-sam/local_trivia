import XCTest

/// How to play: once after the terms on a first launch, through to a practice
/// answer and Let's Play — then again from the join screen, any time.
final class TutorialUITests: XCTestCase {
  override func setUp() {
    continueAfterFailure = false
  }

  @MainActor
  func testWalksAFirstTimePlayerThrough() throws {
    let app = XCUIApplication()
    app.launchArguments += ["-nickname", "UITest", "-termsAccepted", "1", "-resetTutorial", "YES"]
    app.launch()

    XCTAssertTrue(app.staticTexts["Welcome to Trivia"].waitForExistence(timeout: 10), "no tutorial on a first launch")
    XCTAssertTrue(app.buttons["Skip"].exists)
    attach(app, "1 Welcome")
    app.buttons["Next"].tap()
    XCTAssertTrue(app.staticTexts["Join a game"].waitForExistence(timeout: 5))
    app.buttons["Next"].tap()

    // A practice question, answered and scored.
    XCTAssertTrue(app.staticTexts["Answer fast"].waitForExistence(timeout: 5))
    let saturn = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "B,")).firstMatch
    XCTAssertTrue(saturn.waitForExistence(timeout: 5), "no practice answers")
    saturn.tap()
    XCTAssertTrue(app.buttons["Try Another"].waitForExistence(timeout: 5), "no verdict")
    attach(app, "2 Practice")

    for title in ["Standings and the podium", "Host your own", "Play nice", "Make it yours"] {
      app.buttons["Next"].tap()
      XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5), "no page \(title)")
      attach(app, title)
    }
    app.buttons["Let's Play"].tap()
    XCTAssertTrue(app.buttons["Host a Game"].waitForExistence(timeout: 5), "the tutorial never finished")

    // Any time after, from the join screen.
    app.buttons["How to Play"].tap()
    XCTAssertTrue(app.staticTexts["Welcome to Trivia"].waitForExistence(timeout: 5), "How to Play doesn't open it")
    XCTAssertTrue(app.buttons["Done"].exists)
    app.buttons["Done"].tap()
    XCTAssertTrue(app.buttons["Host a Game"].waitForExistence(timeout: 5))
  }

  private func attach(_ app: XCUIApplication, _ name: String) {
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = name
    shot.lifetime = .keepAlways
    add(shot)
  }
}
