import Foundation
import Testing

/// Plurals are written with automatic grammar agreement — `^[3 question](inflect: true)`
/// — rather than as plural variants in the catalog. This resolves every such
/// key through the app's bundle, as the app does, and holds it to agreeing
/// with its number.
struct StringCatalogTests {
  private static let catalog = URL(filePath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent()
    .appending(path: "LocalTrivia/Localizable.xcstrings")

  @Test func everyInflectedPluralAgreesWithItsNumber() throws {
    let strings = try #require(
      try JSONSerialization.jsonObject(with: Data(contentsOf: Self.catalog)) as? [String: Any]
    )["strings"] as? [String: Any]
    let keys = try #require(strings).keys.filter { $0.contains("inflect: true") }.sorted()
    #expect(!keys.isEmpty, "found no inflected keys in \(Self.catalog.path)")

    for key in keys {
      let one = Self.resolve(key, count: 1)
      let three = Self.resolve(key, count: 3)
      // Same sentence, only the number swapped: if it still reads the same,
      // nothing agreed with it.
      #expect(three.replacingOccurrences(of: "3", with: "1") != one, "\(key) doesn't inflect: \(one) / \(three)")
    }
  }

  @Test func inflectsTheWayTheScreensSayIt() {
    #expect(Self.resolve("^[%lld question](inflect: true) to go", count: 1) == "1 question to go")
    #expect(Self.resolve("^[%lld question](inflect: true) to go", count: 3) == "3 questions to go")
    #expect(Self.resolve("Add ^[%lld Question](inflect: true)", count: 1) == "Add 1 Question")
    #expect(Self.resolve("Add ^[%lld Question](inflect: true)", count: 3) == "Add 3 Questions")
  }

  /// `key` as the app resolves it: rebuilt as the interpolation that
  /// produced it, every number `count`, through `AttributedString(localized:)`
  /// — the app's bundle, its Markdown, and the agreement.
  private static func resolve(_ key: String, count: Int) -> String {
    let specifiers = key.matches(of: /%(lld|@)/)
    var value = String.LocalizationValue.StringInterpolation(literalCapacity: key.count, interpolationCount: specifiers.count)
    var rest = key[...]
    for specifier in specifiers {
      value.appendLiteral(String(rest[..<specifier.range.lowerBound]))
      if specifier.output.1 == "lld" { value.appendInterpolation(count) } else { value.appendInterpolation("X") }
      rest = rest[specifier.range.upperBound...]
    }
    value.appendLiteral(String(rest))
    return String(AttributedString(localized: String.LocalizationValue(stringInterpolation: value)).characters)
  }
}
