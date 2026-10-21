import Foundation

// The words `ContentFilter` keeps out, lower-case and unaccented, each as the
// filter reads it: whole words, before a common ending ("-s", "-ed", "-ing").
// This is a moderation list, so it has to name what it keeps out.
//
// Adding a word: put it in `question` only if a trivia question could have
// no innocent use for it; otherwise in `nameOnly`. A stem matches inside any
// word, so it must be one no innocent word contains.

nonisolated extension ContentFilter {
  enum Words {
    /// Kept out of questions, answers, categories — and names.
    static let question: Set<String> = [
      // Profanity
      "fuck", "fucked", "fucker", "fucking", "fuckin", "fuk", "fuq", "fck", "fcuk", "phuck", "motherfucker",
      "shit", "shits", "shitty", "shite", "bullshit", "horseshit", "dipshit", "shithead", "shitface", "shithole",
      "cunt", "twat", "wank", "wanker", "wanking", "jizz", "cocksucker", "asshole", "arsehole", "dickhead",
      "bellend", "knobhead", "motherfuck", "goddamnit",
      // Slurs
      "nigger", "nigga", "niggaz", "nigguh", "faggot", "fagot", "kike", "kyke", "wetback", "beaner", "tranny",
      "shemale", "retard", "retarded", "raghead", "towelhead", "sandnigger", "porchmonkey", "junglebunny",
      // Sexual
      "porn", "porno", "dildo", "blowjob", "handjob", "rimjob", "cumshot", "cumslut", "creampie", "gangbang",
      "bukkake", "hentai", "milf", "slut", "whore", "skank", "jerkoff", "jackoff", "masturbate", "masturbating",
    ]

    /// Kept out of nicknames and game names, besides `question`'s: words a
    /// trivia question may need, but nobody needs to be called.
    static let nameOnly: Set<String> = [
      "ass", "arse", "asses", "butthole", "dick", "dicks", "cock", "cocks", "prick", "pussy",
      "tit", "tits", "titty", "titties", "boob", "boobs", "booby", "nipple", "nipples", "penis", "vagina", "vulva",
      "clit", "clitoris", "anal", "anus", "scrotum", "testicle", "testicles", "balls", "ballsack", "nutsack",
      "sex", "sexy", "sexx", "xxx", "nude", "nudes", "naked", "horny", "orgasm", "erection", "boner", "cum", "semen",
      "sperm", "rape", "raped", "rapist", "molest", "molester", "pedo", "pedophile", "paedo", "paedophile",
      "incest", "bitch", "bitches", "bastard", "bollock", "bollocks", "piss", "pissed", "douche", "douchebag",
      "fag", "fags", "dyke", "homo", "chink", "gook", "coon", "jap", "wop", "paki", "gypo", "tard", "nazi", "nazis",
      "hitler", "heil", "kkk", "killyourself", "kys",
    ]

    static let name = question.union(nameOnly)

    /// Matched inside any word of a question, or anywhere in a name.
    static let questionStems: [String] = [
      "fuck", "motherf", "nigger", "nigga", "faggot", "cocksuck", "shithead", "bullshit", "asshole", "arsehole",
      "dickhead", "jizz", "wanker", "blowjob", "handjob",
    ]

    /// Matched anywhere in a name, its separators squeezed out. Never one an
    /// innocent name holds: not "shit" (Kinoshita), nor "rapist" (therapist).
    static let nameStems: [String] = questionStems + [
      "cunt", "bitch", "whore", "slut", "porn", "dildo", "pussy", "penis", "vagina", "hitler", "twat", "wank",
      "retard", "molest", "pedophil", "paedo", "killyourself",
    ]
  }
}
