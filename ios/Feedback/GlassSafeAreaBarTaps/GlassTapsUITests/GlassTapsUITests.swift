import XCTest

/// Each button in the safe-area bar should count one tap. The first test has
/// every ingredient on; each of the rest switches one off.
final class GlassTapsUITests: XCTestCase {
  static let ingredients = ["appDelegate", "tint", "rootSheet", "container", "glassContent", "transition", "columnFrame", "background", "barAnimation", "feedback", "toolbar", "reader"]

  @MainActor func testEverything() { XCTAssertEqual(failingButtons(without: nil), [], "every ingredient on") }

  @MainActor func testWithoutEachIngredient() {
    var report: [String] = []
    for ingredient in Self.ingredients {
      report.append("without \(ingredient): \(failingButtons(without: ingredient))")
    }
    let attachment = XCTAttachment(string: report.joined(separator: "\n"))
    attachment.name = "ingredients"
    attachment.lifetime = .keepAlways
    add(attachment)
    print("INGREDIENTS\n" + report.joined(separator: "\n"))
  }

  /// The buttons whose tap didn't count.
  @MainActor
  private func failingButtons(without ingredient: String?) -> [String] {
    let app = XCUIApplication()
    if let ingredient { app.launchArguments += ["-\(ingredient)", "NO"] }
    app.launch()
    let count = app.staticTexts["count"]
    XCTAssertTrue(count.waitForExistence(timeout: 5))
    if ingredient == nil {
      let tree = XCTAttachment(string: app.debugDescription)
      tree.name = "tree"
      tree.lifetime = .keepAlways
      add(tree)
    }
    var failing: [String] = []
    for button in ["glass", "prominent", "plain"] {
      let before = count.label
      app.buttons[button].tap()
      if count.label == before { failing.append(button) }
    }
    return failing
  }
}
