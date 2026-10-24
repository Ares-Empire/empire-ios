import Foundation

/// Search on the device over everything in the vault: titles, summaries, the notes' text, and the glossary in English
/// and German. Case and accents are ignored ("Druckorte" finds "druckorte", "Handelsstadte" finds "Handelsstädte").
///
/// Ranking: every word of the query must appear in a result. Results whose title holds all the words come first (a
/// title that starts with the query before the rest), then the summary, then a glossary term, then the text, then notes
/// where the words are spread over several of these. Within a rank, by title.
struct VaultSearch: Sendable {
    enum Rank: Int, Comparable, Sendable {
        case titleStart, title, summary, term, text, spread
        static func < (a: Rank, b: Rank) -> Bool { a.rawValue < b.rawValue }
    }

    enum Result: Equatable, Identifiable, Sendable {
        case note(id: String, rank: Rank)
        case term(Term, rank: Rank)

        var id: String {
            switch self {
            case let .note(id, _): "note:" + id
            case let .term(term, _): "term:" + term.english + "|" + term.german
            }
        }

        var rank: Rank {
            switch self {
            case let .note(_, rank), let .term(_, rank): rank
            }
        }
    }

    private struct Entry: Sendable {
        let id: String
        let type: NoteType
        let title: String               // as shown, for sorting
        let titleKey: String            // folded
        let summaryKey: String
        let textKey: String
    }

    private struct TermEntry: Sendable {
        let term: Term
        let key: String                 // English and German, folded
    }

    /// A sentence that holds every word of the query, with the note it stands in.
    struct SentenceHit: Equatable, Identifiable, Sendable {
        let passage: Lookup.Passage
        let sentence: String            // plain text
        let title: String               // the note's title
        let phrase: Bool                // holds the query as one phrase (ranked first)
        var id: String { passage.id + "|" + sentence }
    }

    private struct SentenceEntry: Sendable {
        let passage: Lookup.Passage
        let sentence: String
        let title: String
        let key: String                 // folded
    }

    static let empty = VaultSearch(vault: nil)

    private let entries: [Entry]
    private let terms: [TermEntry]
    private let sentenceEntries: [SentenceEntry]

    init(vault: Vault?) {
        // A note's positions are part of its text (the note itself holds only their ids).
        let positions = Dictionary((vault?.positions ?? []).flatMap(\.positions).map { ($0.id, $0.text) },
                                   uniquingKeysWith: { first, _ in first })
        entries = (vault?.notes ?? []).map { note in
            let stated = note.positions.compactMap { positions[$0] }.map(InlineMarkdown.plain)
            return Entry(id: note.id, type: note.type, title: note.title,
                         titleKey: Self.fold(note.title + " " + note.id),
                         summaryKey: Self.fold(note.summary.map(InlineMarkdown.plain) ?? ""),
                         textKey: Self.fold((stated + [Self.text(of: note.blocks)]).joined(separator: "\n")))
        }
        terms = (vault?.glossary ?? []).map { TermEntry(term: $0, key: Self.fold($0.english + " " + $0.german)) }
        // Every sentence of the notes people read (not the index pages, which only repeat titles and links).
        let indexPages: Set<NoteType> = [.home, .positions, .glossary]
        sentenceEntries = (vault?.notes ?? []).filter { !indexPages.contains($0.type) }.flatMap { note in
            Lookup.passages(of: note).flatMap { passage in
                Lookup.sentences(passage.text).map { sentence in
                    SentenceEntry(passage: passage, sentence: sentence, title: note.title, key: Self.fold(sentence))
                }
            }
        }
    }

    /// The sentences that hold every word of the query (at least two letters typed), the ones with the whole query as
    /// a phrase first, then in the vault's order; at most `limit`.
    func sentences(_ text: String, limit: Int = 40) -> [SentenceHit] {
        let query = Query(text)
        guard query.folded.count >= 2, !query.isEmpty else { return [] }
        var phrase: [SentenceHit] = []
        var rest: [SentenceHit] = []
        for entry in sentenceEntries where query.isFound(in: entry.key) {
            let isPhrase = query.words.count > 1 && entry.key.contains(query.folded)
            let hit = SentenceHit(passage: entry.passage, sentence: entry.sentence, title: entry.title, phrase: isPhrase)
            if isPhrase { phrase.append(hit) } else { rest.append(hit) }
            if phrase.count >= limit { break }
        }
        return Array((phrase + rest).prefix(limit))
    }

    /// The results for a query, best first. `type` limits them to notes of one type (glossary terms then only show for
    /// the glossary type). An empty query finds nothing.
    func results(_ text: String, type: NoteType? = nil) -> [Result] {
        let query = Query(text)
        guard !query.isEmpty else { return [] }
        let all = query.isFound(in:)

        var found: [(rank: Rank, title: String, result: Result)] = []
        for entry in entries where type == nil || entry.type == type {
            let rank: Rank
            if entry.titleKey.hasPrefix(query.folded) { rank = .titleStart }
            else if all(entry.titleKey) { rank = .title }
            else if all(entry.summaryKey) { rank = .summary }
            else if all(entry.textKey) { rank = .text }
            else if all(entry.titleKey + " " + entry.summaryKey + " " + entry.textKey) { rank = .spread }
            else { continue }
            found.append((rank, entry.title, .note(id: entry.id, rank: rank)))
        }
        if type == nil || type == .glossary {
            for entry in terms where all(entry.key) {
                found.append((.term, entry.term.english, .term(entry.term, rank: .term)))
            }
        }
        return found.sorted { first, second in
            if first.rank != second.rank { return first.rank < second.rank }
            return first.title.localizedStandardCompare(second.title) == .orderedAscending
        }.map(\.result)
    }

    /// A query as every search of the app reads it: folded, cut into words. A text matches when it holds every word
    /// (anywhere, also inside a longer word: "druck" finds "Druckorte").
    struct Query: Sendable {
        let folded: String              // the whole query, folded and trimmed
        let words: [String]

        init(_ text: String) {
            folded = VaultSearch.fold(text).trimmingCharacters(in: .whitespacesAndNewlines)
            words = folded.split(whereSeparator: \.isWhitespace).map(String.init)
        }

        var isEmpty: Bool { words.isEmpty }

        /// Every word is in `key` (a folded text). An empty query is found nowhere.
        func isFound(in key: String) -> Bool { !words.isEmpty && words.allSatisfy { key.contains($0) } }

        /// At least one word is in `key` (a folded text).
        func touches(_ key: String) -> Bool { words.contains { key.contains($0) } }
    }

    /// Lower case, without accents and umlaut dots, so typing on any keyboard finds the words.
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
    }

    /// The words of a note's blocks, without Markdown, for searching.
    static func text(of blocks: [Block]) -> String {
        var parts: [String] = []
        for block in blocks {
            switch block {
            case let .heading(_, text, _), let .paragraph(text), let .quote(text):
                parts.append(InlineMarkdown.plain(text))
            case let .list(_, items):
                parts += items.map { InlineMarkdown.plain($0.text) }
            case let .callout(_, title, text, _):
                parts.append(InlineMarkdown.plain((title.map { $0 + " " } ?? "") + text))
            case let .table(header, rows):
                parts += (header + rows.flatMap { $0 }).map(InlineMarkdown.plain)
            case .positions, .embed, .sectionLink, .rule, .unknown:
                break
            }
        }
        return parts.joined(separator: "\n")
    }
}
