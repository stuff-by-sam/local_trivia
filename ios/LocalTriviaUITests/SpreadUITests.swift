import XCTest

/// A big screen — iPad, and iPhone Duo open — lays each game screen out as a
/// spread: two halves either side of the window's middle, where iPhone Duo's
/// hinge runs whichever way it's turned. Nothing a player reads or taps may
/// sit across that middle, standing up or on its side. Each screen is
/// attached as a screenshot, with the fold drawn on it.
///
/// Needs a simulator with room to spread — an iPad's; on a phone it skips.
final class SpreadUITests: XCTestCase {
  /// `Space.fold`: the gutter a spread keeps clear down its middle.
  private let gutter: CGFloat = 48

  /// Every full-screen screen. Sheets aren't spreads: the system keeps them
  /// off the fold itself.
  private let screens = [
    "terms", "tutorial", "join", "join.found", "lobby", "host.lobby", "spectating", "question",
    "question.chosen", "result.correct", "standings", "final", "host.final",
  ]

  override func setUp() {
    continueAfterFailure = true
  }

  @MainActor
  func testNothingSitsOnTheFoldStandingUp() throws {
    try checkEveryScreen(.portrait)
  }

  @MainActor
  func testNothingSitsOnTheFoldOnItsSide() throws {
    try checkEveryScreen(.landscapeLeft)
  }

  /// Right to left, the halves change sides — the question on the right,
  /// the answers on the left — and the fold stays clear.
  @MainActor
  func testNothingSitsOnTheFoldRightToLeft() throws {
    try checkEveryScreen(.landscapeLeft, arguments: ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"])
  }

  /// Typing on stacked halves, the keyboard covers the second: the form
  /// takes the screen, the PIN above the keyboard.
  @MainActor
  func testTheFormHasTheScreenWhileTyping() throws {
    XCUIDevice.shared.orientation = .portrait
    let app = XCUIApplication()
    app.launchArguments = ["-screen", "join", "-showsFold", "YES"]
    app.launch()
    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 10))
    try XCTSkipUnless(
      window.horizontalSizeClass == .regular && window.verticalSizeClass == .regular,
      "Only a screen with room for two halves spreads."
    )
    let pin = app.textFields["Game PIN"]
    XCTAssertTrue(pin.waitForExistence(timeout: 5))
    let before = pin.frame
    pin.tap()
    let keyboard = app.keyboards.firstMatch
    // A simulator typing on the Mac's keyboard shows none of its own.
    let hasKeyboard = keyboard.waitForExistence(timeout: 5)
    Thread.sleep(forTimeInterval: 1)
    XCTAssertLessThan(pin.frame.minY, before.minY, "the form didn't move up into the screen")
    if hasKeyboard {
      XCTAssertLessThanOrEqual(pin.frame.maxY, keyboard.frame.minY, "the keyboard covers the PIN")
    }
    let shot = XCTAttachment(screenshot: app.screenshot())
    shot.name = "join typing portrait"
    shot.lifetime = .keepAlways
    add(shot)
  }

  @MainActor
  private func checkEveryScreen(_ orientation: UIDeviceOrientation, arguments: [String] = []) throws {
    XCUIDevice.shared.orientation = orientation
    // Standing up again for whatever runs next.
    defer { XCUIDevice.shared.orientation = .portrait }
    for screen in screens {
      let app = XCUIApplication()
      app.launchArguments = ["-screen", screen, "-showsFold", "YES", "-termsAccepted", "1", "-tutorialSeen", "YES"] + arguments
      app.launch()
      let window = app.windows.firstMatch
      XCTAssertTrue(window.waitForExistence(timeout: 10))
      try XCTSkipUnless(
        window.horizontalSizeClass == .regular && window.verticalSizeClass == .regular,
        "Only a screen with room for two halves spreads."
      )
      // The glass characters' traces and the screen transition settle.
      Thread.sleep(forTimeInterval: 1.5)

      let fold = foldBand(in: window.frame)
      if screen == "question", orientation.isLandscape {
        // Read first, from the leading side: the question, then the answers.
        let question = app.staticTexts["Which planet has the most moons?"].frame
        let answer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "A,")).firstMatch.frame
        let isRightToLeft = !arguments.isEmpty
        XCTAssertEqual(question.midX < window.frame.midX, !isRightToLeft, "the question's on the wrong side")
        XCTAssertEqual(answer.midX > window.frame.midX, !isRightToLeft, "the answers are on the wrong side")
      }
      let scrollers = app.scrollViews.allElementsBoundByIndex.map(\.frame)
      for element in readableAndTappable(in: app) {
        // A half's scroll view clips what's scrolled past its edge.
        let center = CGPoint(x: element.frame.midX, y: element.frame.midY)
        let scroller = scrollers.filter { $0.contains(center) }.min { $0.width * $0.height < $1.width * $1.height }
        let shown = scroller.map { element.frame.intersection($0) } ?? element.frame
        if shown.intersects(fold) {
          XCTFail("\(screen), \(orientation == .portrait ? "standing up" : "on its side"): “\(element.label)” sits on the fold at \(shown)")
        }
      }
      let shot = XCTAttachment(screenshot: app.screenshot())
      shot.name = "\(screen) \(orientation == .portrait ? "portrait" : "landscape")\(arguments.isEmpty ? "" : " RTL")"
      shot.lifetime = .keepAlways
      add(shot)
    }
  }

  /// The gutter down the window's middle, across its longer side — less a
  /// few points each side: a line of text's frame runs a little past its
  /// letters, and a frame that only brushes the gutter isn't on the fold.
  private func foldBand(in window: CGRect) -> CGRect {
    let band = gutter - 8
    return if window.width >= window.height {
      CGRect(x: window.midX - band / 2, y: window.minY, width: band, height: window.height)
    } else {
      CGRect(x: window.minX, y: window.midY - band / 2, width: window.width, height: band)
    }
  }

  /// What a player reads or taps in the screen itself, on screen — not
  /// what a half's scroll view has clipped, and not the system's bars, which
  /// the system lays out around the hinge.
  @MainActor
  private func readableAndTappable(in app: XCUIApplication) -> [XCUIElement] {
    let bars = app.navigationBars.allElementsBoundByIndex.map(\.frame)
    let kinds = [app.buttons, app.staticTexts, app.textFields, app.images]
    return kinds.flatMap { $0.allElementsBoundByIndex }.filter { element in
      let frame = element.frame
      return element.exists && !frame.isEmpty && frame.width < 4_000 && !bars.contains { $0.intersects(frame) }
        && element.isHittable
    }
  }
}
