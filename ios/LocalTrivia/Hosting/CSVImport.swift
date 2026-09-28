import Foundation

/// CSV → questions: a port of public/shared/csv.js, so a file that imports in
/// the web admin console imports the same way here.
///
/// Columns are positional (headings can say anything):
///
///     question, option_a, option_b, option_c, option_d, correct, category, time_limit
///
/// It tolerates the shapes real exports come in — a title line above the
/// header, no header at all, answer keys as A–D, 1–4, 0–3 or the option's
/// text — and reports bad rows by line number instead of failing.
nonisolated enum CSVImport {
  struct Result: Equatable, Sendable {
    var questions: [HostQuestion]
    var errors: [String]
    var notes: [String]
  }

  static func parse(_ text: String) -> Result {
    let rows = splitRows(text)
    let start = firstDataRow(rows)
    let dataRows = rows.dropFirst(start).map { $0.map(trimmed) }
    let base = numericBase(dataRows)

    var result = Result(questions: [], errors: [], notes: [])
    if base == 0 { result.notes.append("Zero-indexed answer keys (0–3) detected and mapped to A–D.") }

    for (offset, raw) in rows.enumerated().dropFirst(start) {
      let cells = raw.map(trimmed)
      let line = offset + 1
      guard cells.count >= 6 else {
        result.errors.append("Line \(line): needs at least 6 columns (found \(cells.count)).")
        continue
      }
      let options = Array(cells[1...4])
      guard !cells[0].isEmpty, !options.contains(where: \.isEmpty) else {
        result.errors.append("Line \(line): the question or an answer is empty.")
        continue
      }
      let correct = resolveCorrect(cells[5], options: options, base: base)
      guard (0...3).contains(correct) else {
        result.errors.append("Line \(line): '\(cells[5])' isn't A–D, 1–4 or one of the answers.")
        continue
      }

      var timeLimit: Int?
      if cells.count > 7, !cells[7].isEmpty {
        if let seconds = leadingInteger(cells[7]), HostQuestion.timeLimits.contains(seconds) {
          timeLimit = seconds
        } else {
          result.errors.append(
            "Line \(line): time limit must be \(HostQuestion.timeLimits.lowerBound)–\(HostQuestion.timeLimits.upperBound)s (ignored).")
        }
      }

      let category = cells.count > 6 && !cells[6].isEmpty ? cells[6].uppercased() : "GENERAL"
      result.questions.append(
        HostQuestion(text: cells[0], options: options, correct: correct, category: category, timeLimit: timeLimit))
    }
    return result
  }

  // MARK: - Reading

  /// RFC 4180-ish: quoted fields, escaped `""`, CR, LF or CRLF line ends.
  /// Walks Unicode scalars, not Characters: Swift treats CRLF as a single
  /// Character, and the rules here are about the individual code points.
  static func splitRows(_ text: String) -> [[String]] {
    var rows: [[String]] = []
    var row = [""]
    var inQuotes = false
    let scalars = Array(text.unicodeScalars)
    var index = 0
    while index < scalars.count {
      let scalar = scalars[index]
      if inQuotes {
        if scalar != "\"" {
          row[row.count - 1].unicodeScalars.append(scalar)
        } else if index + 1 < scalars.count, scalars[index + 1] == "\"" {
          row[row.count - 1].append("\"")
          index += 1
        } else {
          inQuotes = false
        }
      } else if scalar == "\"" {
        inQuotes = true
      } else if scalar == "," {
        row.append("")
      } else if scalar == "\n" || scalar == "\r" {
        if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" { index += 1 }
        rows.append(row)
        row = [""]
      } else {
        row[row.count - 1].unicodeScalars.append(scalar)
      }
      index += 1
    }
    rows.append(row)
    return rows.filter { $0.contains { !trimmed($0).isEmpty } }
  }

  /// Exports often carry a title line above the real header, so look for the
  /// header in the first few rows; anything above it is preamble.
  private static func firstDataRow(_ rows: [[String]]) -> Int {
    for index in rows.indices.prefix(5) where looksLikeHeader(rows[index]) { return index + 1 }
    return 0
  }

  private static func looksLikeHeader(_ row: [String]) -> Bool {
    let cells = row.map { trimmed($0).lowercased() }
    return cells.contains("correct") && cells.contains { ["question", "text", "prompt"].contains($0) }
  }

  /// Numeric keys are 1–4 (documented) or 0–3 (zero-indexed exports). Decide
  /// once per file from unambiguous evidence: a 0 proves zero-indexed, a 4
  /// proves one-indexed; only 1/2/3 is ambiguous and reads as documented.
  private static func numericBase(_ rows: [[String]]) -> Int {
    let numbers = Set(rows.compactMap { $0.count > 5 ? $0[5] : nil }.filter(isDigits).compactMap { Int($0) })
    if numbers.contains(0) { return 0 }
    return 1
  }

  private static func resolveCorrect(_ raw: String, options: [String], base: Int) -> Int {
    let key = raw.uppercased()
    if key.count == 1, let letter = key.unicodeScalars.first, ("A"..."D").contains(letter) {
      return Int(letter.value - UnicodeScalar("A").value)
    }
    if isDigits(raw), let number = Int(raw) { return number - base }
    return options.firstIndex { $0.lowercased() == raw.lowercased() } ?? -1
  }

  // MARK: - Helpers

  private static func trimmed(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func isDigits(_ value: String) -> Bool {
    !value.isEmpty && value.unicodeScalars.allSatisfy { ("0"..."9").contains($0) }
  }

  /// `parseInt(value, 10)`: the leading digits, if any ("30s" → 30).
  private static func leadingInteger(_ value: String) -> Int? {
    Int(String(value.unicodeScalars.prefix { ("0"..."9").contains($0) }))
  }
}
