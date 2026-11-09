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

  /// Host a Game asks what's in play every time it's drawn — at every
  /// keystroke of the game's name — and each asking used to read every
  /// question in the round against the word filter again, four times over.
  /// Now a text's verdict is remembered, and what's in play is worked out
  /// when the round changes.
  @Test func readsARoundAgainstTheFilterOnce() {
    // Words no other test has asked about, so the first reading is a real one.
    let letters = Array("jqvxz")
    func word(_ number: Int) -> String {
      var number = number
      var word = ""
      repeat {
        word.append(letters[number % letters.count])
        number /= letters.count
      } while number > 0
      return word
    }
    let run = String((0..<12).map { _ in letters.randomElement()! })
    let round = (0..<60).map { number in
      HostQuestion(
        text: "Which \(run) \(word(number)) is the largest of them all?",
        options: ["The \(word(number)) one", "The \(word(number + 1000)) one", "The \(word(number + 2000)) one", "The \(word(number + 3000)) one"],
        correct: 0, category: run.uppercased())
    }
    let clock = ContinuousClock()

    // How it was: every question read, each time it's asked.
    var inPlay = 0
    let reading = clock.measure { inPlay = round.count(where: \.isPlayable) }
    #expect(inPlay == round.count)
    // Read once already: asking again is looking up what was found.
    let asking = (0..<5).map { _ in clock.measure { inPlay = round.count(where: \.isPlayable) } }.min() ?? reading
    #expect(inPlay == round.count)
    #expect(asking * 5 < reading, "a second asking reads nothing again")

    // And the round keeps the answer, so the screen doesn't ask at all.
    let library = HostLibrary(fileURL: nil)
    library.questions = round
    let kept = (0..<5).map { _ in clock.measure { inPlay = library.playable.count } }.min() ?? reading
    #expect(inPlay == round.count)
    #expect(kept * 5 < reading)
    Attachment.record(
      "\(round.count) questions in play — read against the filter: \(reading); asked again: \(asking); kept by the round: \(kept)",
      named: "filter-timings.txt")
  }

  private static func renderAsBefore(_ text: String) -> UIImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let output = filter.outputImage, let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
    return UIImage(cgImage: cgImage)
  }
}
