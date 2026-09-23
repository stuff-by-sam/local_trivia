import Foundation
import Testing

/// The app names no colours, sizes, radii, curves or haptics of its own:
/// every one comes from the DesignSystem package (ios/DESIGN.md). This reads
/// the app's sources and fails on any literal that should have been a token,
/// with the file and line, so a one-off can't slip in unnoticed.
struct DesignSystemLintTests {
  /// What a view mustn't spell out, and the token to use instead.
  private static let rules: [(pattern: String, use: String)] = [
    (#"Color\(hex:|Color\(red:|0x[0-9A-Fa-f]{6}\b"#, "a Palette role (.danger, palette.accent, …)"),
    (#"\.(white|black)\.opacity\("#, "a Palette role (.panel, .hairline, .slot)"),
    (#"\.system\(size:|Font\.custom|\.custom\("#, "a TextRole or TVRole"),
    (#"\.tracking\([0-9]"#, "a TextRole or TVRole"),
    (#"cornerRadius: [0-9]"#, "Radius or TVMetrics"),
    (#"padding\((\.[a-zA-Z]+, )?-?[0-9]"#, "Space"),
    (#"spacing: [1-9]"#, "Space"),
    (#"(width|height|minWidth|minHeight|maxWidth|maxHeight): [1-9]"#, "Size or TVMetrics"),
    (#"withAnimation\(|\.animation\("#, "Motion (.motion(_:value:), Motion.x.perform)"),
    (#"sensoryFeedback\(|FeedbackGenerator"#, "Haptic (.haptic(_:trigger:))"),
    (#"\.shadow\("#, ".glow(_:)"),
    (#"\.preferredColorScheme\("#, "nothing: the app is dark by Info.plist"),
    (#"\.foregroundStyle\(\.tertiary\)"#, ".secondary — tertiary text fails contrast on ink"),
  ]

  /// Prototypes, kept for comparison, not built on.
  private static let exempt: Set<String> = ["Explorations.swift"]

  @Test func appSourcesUseOnlyDesignTokens() throws {
    let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appending(path: "LocalTrivia")
    let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
      .compactMap { $0 as? URL }
      .filter { $0.pathExtension == "swift" && !Self.exempt.contains($0.lastPathComponent) }
    #expect(!files.isEmpty, "found no sources at \(root.path)")

    let rules = try Self.rules.map { (try Regex($0.pattern), $0.use) }
    var violations: [String] = []
    for file in files {
      let lines = try String(contentsOf: file, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false)
      for (number, line) in lines.enumerated() {
        let code = line.trimmingCharacters(in: .whitespaces)
        guard !code.hasPrefix("//") else { continue }
        for (regex, use) in rules where line.contains(regex) {
          violations.append("\(file.lastPathComponent):\(number + 1): \(code) — use \(use)")
        }
      }
    }
    #expect(violations.isEmpty, "\(violations.count) literal(s) outside the design system:\n\(violations.joined(separator: "\n"))")
  }
}
