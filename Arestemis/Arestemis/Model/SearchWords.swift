import Foundation

/// A thing search's words (brief 149, the Arestemis repo's brief 148; Patrik 2026-11-03: ties from several makers in one
/// search): up to five, each 2–100 characters, none repeating another. The first is sent as `query`, the rest as
/// `more_queries`; every word is searched on every chosen site, and the description (`extra`) says what fits per word.
/// The rules are the server's (Arestemis/docs/API.md → `ItemSearch.more_queries`), so the form refuses what the server
/// would; the server stays the judge, and its refusals name the word (`search.more_queries[1]`).
enum SearchWords {
    static let maxCount = 5
    static let lengths = 2...100

    /// What makes two words the same to the server: case, accents, width and runs of spaces do not count ("Hermès
    /// Krawatte" = "hermes  KRAWATTE"), as its `casefold` of the NFKD form without combining marks.
    static func key(_ word: String) -> String {
        word.decomposedStringWithCompatibilityMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// The word among `words` that `word` repeats, as it is written there; nil when it is new.
    static func repeated(_ word: String, in words: [String]) -> String? {
        let key = key(word)
        return words.first { Self.key($0) == key }
    }

    /// A search named after its words (its automatic name, its card): the first word, and "+ 2" for two more
    /// ("Hermès Krawatte + 2"), the same in both languages as the server writes it (`texts.py`, "{query} + {count}");
    /// nil without words.
    static func title(_ words: [String]) -> String? {
        guard let first = words.first else { return nil }
        return words.count > 1 ? "\(first) + \(words.count - 1)" : first
    }

    // MARK: the server's refusals

    /// The fields a refusal of the words names: `search.query` (the first word), `search.more_queries` (all the more
    /// words) and `search.more_queries[i]` (one of them), for `ArestemisStore.saveHunt(fieldsShown:)`.
    static var refusalFields: Set<String> {
        Set(["search.query", "search.more_queries"] + (0..<(maxCount - 1)).map { "search.more_queries[\($0)]" })
    }

    /// Whether a refusal's field is about the words.
    static func isWordsField(_ field: String?) -> Bool {
        guard let field else { return false }
        return field == "search.query" || field == "search.more_queries" || wordIndex(field: field) != nil
    }

    /// The place among all the words (0 = `query`) that a refusal's field names; nil for one that names none
    /// (`search.more_queries` alone, another field).
    static func wordIndex(field: String) -> Int? {
        if field == "search.query" { return 0 }
        let prefix = "search.more_queries[", suffix = "]"
        guard field.hasPrefix(prefix), field.hasSuffix(suffix) else { return nil }
        let number = field.dropFirst(prefix.count).dropLast(suffix.count)
        guard !number.isEmpty, number.allSatisfy({ $0.isASCII && $0.isNumber }), let index = Int(number) else { return nil }
        return index + 1
    }

    /// The server's refusal as its line under the words: led by the word it is about while that word is still there
    /// ("“Kiton tie”: …", German „Kiton-Krawatte“: …), else the sentence alone. The quotes are built here: a catalog
    /// key of punctuation alone is kept untranslated by `scripts/strings.py`.
    static func refusalLine(_ message: String, field: String, words: [String], language: AppLanguage = .current) -> String {
        guard let index = wordIndex(field: field), words.indices.contains(index) else { return message }
        let word = words[index]
        return (language == .german ? "„\(word)“" : "“\(word)”") + ": " + message
    }
}
