import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import Synchronization
import Testing
import UIKit

@testable import LocalTrivia

/// The costs Phase 5 took off the main thread, held to account.
struct PerformanceTests {
  /// Typing a game name, or dragging the scoring slider, used to write the
  /// whole round to disk once per keystroke or step. Now edits settle first.
  @Test func editsSettleIntoOneWrite() async throws {
    let writes = Mutex<[Data]>([])
    let url = URL.temporaryDirectory.appending(path: "round-\(UUID().uuidString).json")
    let library = HostLibrary(fileURL: url) { data, _ in writes.withLock { $0.append(data) } }

    for step in 0..<50 { library.gameName = "NAME \(step)" }
    #expect(writes.withLock(\.count) == 0, "nothing written while edits are still coming")

    let deadline = ContinuousClock.now + HostLibrary.saveDelay + .seconds(2)
    while writes.withLock(\.count) == 0, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
    let written = writes.withLock { $0 }
    #expect(written.count == 1, "50 edits, one write")
    #expect(String(decoding: try #require(written.last), as: UTF8.self).contains("NAME 49"))
  }

  /// Leaving the setup screen, or the app, writes what's pending at once.
  @Test func flushWritesPendingEditsNow() async throws {
    let writes = Mutex(0)
    let url = URL.temporaryDirectory.appending(path: "round-\(UUID().uuidString).json")
    let library = HostLibrary(fileURL: url) { _, _ in writes.withLock { $0 += 1 } }
    library.rules.maxPoints = 2000
    library.flush()
    let deadline = ContinuousClock.now + .seconds(2)
    while writes.withLock({ $0 }) == 0, ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(10))
    }
    #expect(writes.withLock { $0 } == 1)
    library.flush()
    try await Task.sleep(for: .milliseconds(100))
    #expect(writes.withLock { $0 } == 1, "nothing new, nothing written")
  }

  /// The join code's QR image used to be rendered — with a new Core Image
  /// context — every time a view asked for it. Now it's rendered once.
  @Test func rendersEachJoinCodeOnce() throws {
    let payload = "localtrivia://join?url=http://192.168.1.20:3000&pin=\(Int.random(in: 1000...9999))"
    let clock = ContinuousClock()

    // How it was: a fresh context and a fresh render per call.
    let renders = 10
    let before = clock.measure {
      for _ in 0..<renders { _ = Self.renderAsBefore(payload) }
    } / renders

    var first: UIImage?
    let cold = clock.measure { first = QRCode.image(for: payload) }
    var again: UIImage?
    let warm = clock.measure { again = QRCode.image(for: payload) }

    #expect(first != nil)
    #expect(first === again, "the second view gets the same image")
    #expect(warm < before)
    Attachment.record("QR render — before, per call: \(before); now, first: \(cold); now, again: \(warm)", named: "qr-timings.txt")
  }

  private static func renderAsBefore(_ text: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage, let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }
}
