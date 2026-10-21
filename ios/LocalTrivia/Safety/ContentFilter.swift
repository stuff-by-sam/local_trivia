import Foundation

/// Keeps objectionable words out of a game: profanity, slurs and sexual
/// terms in what people type for each other to see. App Review's guideline
/// 1.2 asks for it, and the Terms of Use promise it.
///
/// Two strengths, because a trivia question has reasons a name hasn't. A
/// question may ask about Moby-Dick, a blue tit, Balaam's ass or the Nazis,
/// so it's held to the words with no other use (`Words.question`). A
/// nickname or a game name is held to those and the rest (`Words.name`), and
/// is also read with its spaces and dots squeezed out, so "f.u.c.k" and
/// "fu ck" are caught too.
///
/// Words are matched whole, after folding case and accents and reading
/// look-alike digits and symbols as letters ("sh1t", "@ss"), with common
/// endings taken off ("-s", "-ed", "-ing") — never as parts of longer words,
/// so Scunthorpe and Essex are left alone. A few stems that are never part
/// of an innocent word are matched anywhere in a word.
///
/// The host's phone holds what it's given to this — names at the door
/// (`HostedGame`), questions before they play (`HostQuestion.problem`) — and
/// a player's phone masks anything that still arrives (`GameStore`), from a
/// host this app isn't running on.
nonisolated enum ContentFilter {
  enum Context: Sendable {
    /// A nickname or a game name.
    case name
    /// A question, its answers or its category.
    case question
  }

  /// No objectionable word in `text`.
  static func allows(_ text: String, as context: Context) -> Bool {
    !words(in: text).contains { isObjectionable($0.token, as: context) }
      && !(context == .name && squeezedIsObjectionable(text))
  }

  /// `text` with every objectionable word starred out, letter for letter:
  /// "What the ****?". A name that's only objectionable squeezed is starred
  /// out whole.
  static func masked(_ text: String, as context: Context) -> String {
    if context == .name, squeezedIsObjectionable(text) {
      return String(text.map { $0.isWhitespace ? $0 : "*" })
    }
    var masked = text
    for word in words(in: text).reversed() where isObjectionable(word.token, as: context) {
      masked.replaceSubrange(word.range, with: String(repeating: "*", count: text[word.range].count))
    }
    return masked
  }

  // MARK: - Reading

  /// A run of letters, digits and look-alike symbols, and what it reads as.
  private struct Word {
    let range: Range<String.Index>
    let token: String
  }

  /// Digits and symbols that stand in for letters.
  private static let lookalikes: [Character: Character] = [
    "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
    "@": "a", "$": "s", "!": "i", "|": "i",
  ]

  private static func isWordCharacter(_ character: Character) -> Bool {
    character.isLetter || character.isNumber || lookalikes[character] != nil
  }

  private static func words(in text: String) -> [Word] {
    var words: [Word] = []
    var index = text.startIndex
    while index < text.endIndex {
      guard isWordCharacter(text[index]) else {
        index = text.index(after: index)
        continue
      }
      let start = index
      while index < text.endIndex, isWordCharacter(text[index]) { index = text.index(after: index) }
      let token = read(text[start..<index])
      if !token.isEmpty { words.append(Word(range: start..<index, token: token)) }
    }
    return words
  }

  /// Lower-case, unaccented letters, with look-alikes read as letters. A
  /// "!" or "|" that ends a word is punctuation, not an "i".
  private static func read(_ text: Substring) -> String {
    var text = text
    while let last = text.last, last == "!" || last == "|" { text = text.dropLast() }
    let folded = String(text).folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    return String(folded.compactMap { character in
      if let letter = lookalikes[character] { return letter }
      return character.isLetter ? character : nil
    })
  }

  // MARK: - Matching

  private static func isObjectionable(_ token: String, as context: Context) -> Bool {
    let words = context == .name ? Words.name : Words.question
    let stems = context == .name ? Words.nameStems : Words.questionStems
    let squeezed = squeezeRepeats(token)
    for form in [token, squeezed] {
      if forms(of: form).contains(where: words.contains) { return true }
      if stems.contains(where: form.contains) { return true }
    }
    return false
  }

  /// A name with its separators squeezed out: "f u.c-k" reads "fuck", and
  /// "s.h.i.t" reads as the word it spells.
  private static func squeezedIsObjectionable(_ text: String) -> Bool {
    let squeezed = words(in: text).map(\.token).joined()
    return [squeezed, squeezeRepeats(squeezed)].contains { form in
      Words.nameStems.contains(where: form.contains) || forms(of: form).contains(where: Words.name.contains)
    }
  }

  /// "fuuuuck" reads "fuck"; "booobs", "bobs".
  private static func squeezeRepeats(_ token: String) -> String {
    var last: Character?
    return String(token.filter { character in
      defer { last = character }
      return character != last
    })
  }

  /// The word, and the word with a common ending taken off.
  private static func forms(of token: String) -> [String] {
    var forms = [token]
    // Not "-y" or "-in": spicy and titin are no one's insult.
    for ending in ["s", "es", "ed", "er", "ers", "ing"] where token.count > ending.count + 2 && token.hasSuffix(ending) {
      forms.append(String(token.dropLast(ending.count)))
    }
    if token.hasSuffix("ies"), token.count > 5 { forms.append(String(token.dropLast(3)) + "y") }
    return forms
  }
}

// MARK: - What a host sends

nonisolated extension ServerEvent {
  /// The event with objectionable words starred out of everything people
  /// typed: questions, answers and categories, and other players' names.
  func masked() -> ServerEvent {
    switch self {
    case .joined(let snapshot): .joined(snapshot.masked())
    case .resumed(let snapshot): .resumed(snapshot.masked())
    case .questionStart(let question): .questionStart(question.masked())
    case .gameOver(let result):
      .gameOver(GameOver(podium: result.podium.map { $0.masked() }, standings: result.standings?.map { $0.masked() }))
    case .leaderboard(let board):
      .leaderboard(
        Leaderboard(
          standings: board.standings.map { Leaderboard.Row(rank: $0.rank, nickname: ContentFilter.masked($0.nickname, as: .name), score: $0.score, delta: $0.delta) },
          afterQuestion: board.afterQuestion, totalQuestions: board.totalQuestions, remaining: board.remaining))
    default: self
    }
  }
}

nonisolated extension Question {
  func masked() -> Question {
    Question(
      questionId: questionId, index: index, qNum: qNum, total: total,
      text: ContentFilter.masked(text, as: .question),
      options: options.map { ContentFilter.masked($0, as: .question) },
      category: category.map { ContentFilter.masked($0, as: .question) },
      timeLimit: timeLimit, elapsedMs: elapsedMs)
  }
}

nonisolated extension Placing {
  func masked() -> Placing {
    Placing(rank: rank, nickname: ContentFilter.masked(nickname, as: .name), score: score)
  }
}

nonisolated extension PlayerSnapshot {
  func masked() -> PlayerSnapshot {
    PlayerSnapshot(
      token: token, nickname: nickname, state: state, score: score, rank: rank, playerCount: playerCount,
      eligibleFrom: eligibleFrom, question: question?.masked(), lockedIndex: lockedIndex, lastResult: lastResult,
      podium: podium?.map { $0.masked() }, accent: accent)
  }
}
