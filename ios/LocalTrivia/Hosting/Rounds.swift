import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// The rounds that come with the app: playable with no typing and no Apple
/// Intelligence. Each is a CSV in the app (`Starter Rounds/`), checked fact
/// by fact, and opens as a round of the host's own — a copy, theirs to change.
enum StarterRound: String, CaseIterable, Identifiable {
  case generalKnowledge = "Starter-General-Knowledge"
  case science = "Starter-Science-Class"
  case kids = "Starter-Kids"
  case twentyTens = "Starter-The-2010s"
  case throwback = "Starter-Throwback"

  var id: String { rawValue }

  var name: LocalizedStringResource {
    switch self {
    case .generalKnowledge: "General Knowledge"
    case .science: "Science Class"
    case .kids: "For Kids"
    case .twentyTens: "The 2010s"
    case .throwback: "Throwback"
    }
  }

  var summary: LocalizedStringResource {
    switch self {
    case .generalKnowledge: "History, science, books, art and more"
    case .science: "Chemistry, biology and Earth science"
    case .kids: "Easy questions for younger players"
    case .twentyTens: "Music, movies and moments from the decade"
    case .throwback: "Cartoons, shows, songs and internet moments"
    }
  }

  var symbol: String {
    switch self {
    case .generalKnowledge: "globe.americas.fill"
    case .science: "flask.fill"
    case .kids: "teddybear.fill"
    case .twentyTens: "music.note"
    case .throwback: "gamecontroller.fill"
    }
  }

  /// How many questions it has: read from the app once, not each time a
  /// list of starters is drawn.
  var count: Int? { Self.counts[self] ?? nil }

  private static let counts: [StarterRound: Int?] = Dictionary(uniqueKeysWithValues: allCases.map { ($0, $0.questions?.count) })

  /// Its questions, read from the app: nil only if the file's missing.
  var questions: [HostQuestion]? {
    guard let url = Bundle.main.url(forResource: rawValue, withExtension: "csv"),
      let text = try? String(contentsOf: url, encoding: .utf8)
    else { return nil }
    return CSVImport.parse(text).questions
  }

  /// A round of the host's own from it.
  var round: SavedRound? {
    questions.map { SavedRound(name: String(localized: name), questions: $0) }
  }
}

/// A round as a file to send: a CSV named after it, which opens as a round
/// on any phone with the app (`SavedRound.received(from:)`) and imports into
/// the web admin console. It carries the answer key: it's for another host.
struct RoundFile: Transferable, Sendable {
  let round: SavedRound

  /// The round's name, less what a file name can't hold.
  var fileName: String {
    let name = round.name
      .components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.whitespacesAndNewlines))
      .filter { !$0.isEmpty }
      .joined(separator: " ")
    return (name.isEmpty ? String(localized: "Trivia Round") : name) + ".csv"
  }

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .commaSeparatedText) { file in
      // A folder of its own, so the file can have the round's name.
      let folder = URL.temporaryDirectory.appending(path: "Shared Rounds/\(UUID().uuidString)", directoryHint: .isDirectory)
      try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
      let url = folder.appending(path: file.fileName)
      try Data(CSVExport.text(for: file.round.questions).utf8).write(to: url, options: .atomic)
      return SentTransferredFile(url)
    }
  }
}

extension SavedRound {
  /// The round in a CSV another phone sent, or one opened from Files, named
  /// after the file; nil if it holds no questions. A copy iOS made in the
  /// app's inbox to hand it over is let go once it's read.
  static func received(from url: URL) -> SavedRound? {
    let isScoped = url.startAccessingSecurityScopedResource()
    defer {
      if isScoped { url.stopAccessingSecurityScopedResource() }
      if url.standardizedFileURL.path().hasPrefix(URL.documentsDirectory.appending(path: "Inbox").standardizedFileURL.path()) {
        try? FileManager.default.removeItem(at: url)
      }
    }
    guard let data = try? Data(contentsOf: url),
      // A spreadsheet saves as UTF-8 or, from older Excel, Windows Latin 1.
      let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP1252)
    else { return nil }
    let questions = CSVImport.parse(text).questions
    guard !questions.isEmpty else { return nil }
    let name = url.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
    return SavedRound(name: name.isEmpty ? String(localized: "Shared Round") : name, questions: questions)
  }
}
