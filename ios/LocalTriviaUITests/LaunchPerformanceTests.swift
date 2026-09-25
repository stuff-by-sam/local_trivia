import XCTest

/// Time from launch to the first frame, as the system measures it. Run it on
/// a device for numbers that mean anything; the simulator's are directional.
final class LaunchPerformanceTests: XCTestCase {
  @MainActor
  func testLaunchToFirstFrame() throws {
    let options = XCTMeasureOptions()
    options.iterationCount = 5
    measure(metrics: [XCTApplicationLaunchMetric()], options: options) {
      XCUIApplication().launch()
    }
  }
}
