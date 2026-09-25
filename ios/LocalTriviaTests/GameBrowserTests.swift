import Foundation
import Testing

@testable import LocalTrivia

@MainActor
struct GameBrowserTests {
  /// Looking for games pauses during every game. Pausing isn't failing: the
  /// join screen mustn't come back saying Local Network may be off.
  @Test func stoppingIsntFailing() async throws {
    let browser = GameBrowser()
    browser.start()
    try await Task.sleep(for: .milliseconds(200))
    browser.stop()
    try await Task.sleep(for: .milliseconds(200))
    #expect(!browser.hasFailed)
    browser.start()
    #expect(!browser.hasFailed)
    browser.stop()
  }
}
