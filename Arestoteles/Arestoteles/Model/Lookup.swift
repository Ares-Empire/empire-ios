import Foundation
import NaturalLanguage

/// Quick lookups (Patrik, 2026-10-24: "usually I just want to quickly look up a fact, a figure or a source"): a note's
/// passages and their sentences, the sentences that hold a figure or a date, the note's sources, and the first sentence
/// of a position for its short card. Pure, so the tests pin it.
enum Lookup {
    /// One passage of a note: a paragraph, a list item, a quote or a callout; where it sits and what it says.
    struct Passage: Equatable, Identifiable, Sendable {
        let note: String
        let block: Int                  // index in `Note.blocks`
        let item: Int?                  // the list item, for a list
        let heading: String?            // the heading it stands under (plain text)
        let markdown: String            // the contract's inline Markdown, for showing it
        let text: String                // plain text, for searching
        var id: String { "\(note)|\(block)|\(item ?? -1)|\(text.hashValue)" }
    }

    /// The first sentence of an inline-Markdown text, as plain text ("Capital interests are dominant.").
    static func headline(_ markdown: String) -> String {
        let plain = InlineMarkdown.plain(markdown).trimmingCharacters(in: .whitespacesAndNewlines)
        return sentences(plain).first ?? plain
    }

    /// A card's line for a position (Patrik: "just one sentence per box, I know what's in there"): the first sentence,
    /// and when that is long, only its first clause, cut at ":", ";", " – " or ", and/but/even/so/while" and ended with
    /// "…" ("The West is only rich because it exploited the rest of the world for centuries…").
    static func cardLine(_ markdown: String, longerThan limit: Int = 66) -> String {
        let sentence = headline(markdown)
        guard sentence.count > limit else { return sentence }
        let cuts = [": ", "; ", " – ", " — ", ", and ", ", but ", ", even ", ", so ", ", while ", ", which "]
        let ends = cuts.compactMap { cut in sentence.range(of: cut).map(\.lowerBound) }
            .filter { sentence.distance(from: sentence.startIndex, to: $0) >= 30 }
        var line = ends.min().map { String(sentence[..<$0]).trimmingCharacters(in: .whitespaces) } ?? sentence
        // Still long: end at the last whole word that fits, never inside a word.
        if line.count > limit {
            let prefix = line.prefix(limit)
            line = prefix.lastIndex(of: " ").map { String(prefix[..<$0]) } ?? String(prefix)
            line = line.trimmingCharacters(in: CharacterSet(charactersIn: " ,;:"))
        }
        return line == sentence ? line : line + "…"
    }

    /// A text's sentences (the system's sentence rules: "e.g." and "U.S." do not end one).
    static func sentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var found: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if !sentence.isEmpty { found.append(sentence) }
            return true
        }
        return found
    }

    /// Every passage of a note, in order, with the heading above it.
    static func passages(of note: Note) -> [Passage] {
        var heading: String?
        var found: [Passage] = []
        for (index, block) in note.blocks.enumerated() {
            func add(_ markdown: String, item: Int? = nil) {
                let text = InlineMarkdown.plain(markdown)
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                found.append(Passage(note: note.id, block: index, item: item, heading: heading, markdown: markdown,
                                     text: text))
            }
            switch block {
            case let .heading(_, text, _):
                heading = InlineMarkdown.plain(text)
            case let .paragraph(text), let .quote(text):
                add(text)
            case let .list(_, items):
                for (number, item) in items.enumerated() { add(item.text, item: number) }
            case let .callout(_, title, text, _):
                add((title.map { "**\($0)** " } ?? "") + text)
            case let .table(_, rows):
                for row in rows { add(row.joined(separator: " · ")) }
            case .positions, .embed, .sectionLink, .rule, .unknown:
                break
            }
        }
        return found
    }

    /// The sentences of a note that hold a figure or a date: a number of two or more digits (a year, an amount, a
    /// count) or a percentage. Each as its own passage, so the list stays short.
    static func figures(of note: Note) -> [Passage] {
        passages(of: note).filter { !isSources($0.heading) }.flatMap { passage in
            sentences(passage.text).filter(holdsFigure).map { sentence in
                Passage(note: passage.note, block: passage.block, item: passage.item, heading: passage.heading,
                        markdown: sentence, text: sentence)
            }
        }
    }

    /// The note's sources: the passages under its "Sources" heading.
    static func sources(of note: Note) -> [Passage] {
        passages(of: note).filter { isSources($0.heading) }
    }

    private static func isSources(_ heading: String?) -> Bool {
        guard let heading else { return false }
        return ["sources", "quellen"].contains(heading.lowercased().trimmingCharacters(in: .whitespaces))
    }

    /// A number with at least two digits ("1454", "90%", "€1,400", "1.5 million") or a percentage.
    static func holdsFigure(_ sentence: String) -> Bool {
        sentence.range(of: #"\d[\d.,]*\d|\d\s?%"#, options: .regularExpression) != nil
    }
}
