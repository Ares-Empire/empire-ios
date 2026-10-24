import Foundation

/// The search fields of the Positions, Topics and Library tabs (Patrik, 2026-10-24: search "within the individual tabs
/// for quicker and better access"). Each filters its own tab as it is typed, with the matching of `VaultSearch`
/// (`VaultSearch.Query`: case and accents ignored, every word must appear). Built once per vault, like `VaultSearch`;
/// pure, so the tests pin it.
///
/// - **Positions:** a position's title and text, in the tab's groups and order.
/// - **Topics:** a topic overview's title, summary and section headings; the headings that hold a word of the query
///   come along, so the card can open the note right there.
/// - **Library:** mechanisms, events, questions and actors together, by title, summary (without one: the first
///   paragraph, which the row then shows) and an event's places. Titles that start with the query first, then titles
///   that hold it, then the rest; by title within each.
struct TabSearch: Sendable {
    struct PositionGroup: Equatable, Sendable {
        let title: String
        let note: String
        let positions: [PositionHit]
    }

    struct PositionHit: Equatable, Identifiable, Sendable {
        let position: Position
        /// The title alone does not hold every word: the card shows the position's whole text under it.
        let showsText: Bool
        var id: String { position.id }
    }

    struct TopicHit: Equatable, Identifiable, Sendable {
        let topic: Note
        /// The section headings that hold a word of the query, in the note's order (at most `headingLimit`).
        let headings: [Heading]
        var id: String { topic.id }
    }

    struct Heading: Equatable, Sendable {
        let text: String                // plain text
        let anchor: String
    }

    struct LibraryHit: Equatable, Identifiable, Sendable {
        let note: Note
        /// The line under the title, plain text: the summary, else the first paragraph.
        let lead: String?
        var id: String { note.id }
    }

    static let empty = TabSearch(vault: nil, index: .empty)
    static let headingLimit = 3

    /// The text in a tab's field asks for something (not only spaces).
    static func isQuery(_ text: String) -> Bool { !VaultSearch.Query(text).isEmpty }

    private struct PositionEntry: Sendable {
        let position: Position
        let titleKey: String
        let key: String                 // title and text
    }

    private struct GroupEntry: Sendable {
        let title: String
        let note: String
        let positions: [PositionEntry]
    }

    private struct HeadingEntry: Sendable {
        let heading: Heading
        let key: String
    }

    private struct TopicEntry: Sendable {
        let topic: Note
        let headings: [HeadingEntry]
        let key: String                 // title, summary and headings
    }

    private struct LibraryEntry: Sendable {
        let note: Note
        let lead: String?
        let titleKey: String
        let key: String                 // title, lead and places
    }

    private let groups: [GroupEntry]
    private let topicEntries: [TopicEntry]
    private let libraryEntries: [LibraryEntry]

    init(vault: Vault?, index: VaultIndex) {
        let fold = VaultSearch.fold
        groups = (vault?.positions ?? []).map { group in
            GroupEntry(title: group.title, note: group.note, positions: group.positions.map { position in
                let title = fold(InlineMarkdown.plain(position.title))
                return PositionEntry(position: position, titleKey: title,
                                     key: title + "\n" + fold(InlineMarkdown.plain(position.text)))
            })
        }
        topicEntries = index.topics.map { topic in
            let headings = topic.blocks.compactMap { block -> HeadingEntry? in
                guard case let .heading(_, text, anchor) = block else { return nil }
                let plain = InlineMarkdown.plain(text)
                return HeadingEntry(heading: Heading(text: plain, anchor: anchor), key: fold(plain))
            }
            let summary = topic.summary.map(InlineMarkdown.plain) ?? ""
            return TopicEntry(topic: topic, headings: headings,
                              key: ([fold(topic.title), fold(summary)] + headings.map(\.key)).joined(separator: "\n"))
        }
        libraryEntries = (index.mechanisms + index.events + index.questions + index.actors).map { note in
            let lead = (note.summary ?? Lookup.firstParagraph(of: note)).map(InlineMarkdown.plain)
            let places = note.event?.where.joined(separator: " ") ?? ""
            let title = fold(note.title)
            return LibraryEntry(note: note, lead: lead, titleKey: title,
                                key: [title, fold(lead ?? ""), fold(places)].joined(separator: "\n"))
        }
    }

    /// The positions that hold every word, in their groups (groups without one left out).
    func positions(_ text: String) -> [PositionGroup] {
        let query = VaultSearch.Query(text)
        guard !query.isEmpty else { return [] }
        return groups.compactMap { group in
            let found = group.positions.filter { query.isFound(in: $0.key) }.map { entry in
                PositionHit(position: entry.position, showsText: !query.isFound(in: entry.titleKey))
            }
            return found.isEmpty ? nil : PositionGroup(title: group.title, note: group.note, positions: found)
        }
    }

    /// The topic overviews that hold every word in their title, summary and headings, in the tab's order.
    func topics(_ text: String) -> [TopicHit] {
        let query = VaultSearch.Query(text)
        guard !query.isEmpty else { return [] }
        return topicEntries.filter { query.isFound(in: $0.key) }.map { entry in
            TopicHit(topic: entry.topic,
                     headings: Array(entry.headings.filter { query.touches($0.key) }.map(\.heading).prefix(Self.headingLimit)))
        }
    }

    /// The library's notes of every kind that hold every word.
    func library(_ text: String) -> [LibraryHit] {
        let query = VaultSearch.Query(text)
        guard !query.isEmpty else { return [] }
        func rank(_ entry: LibraryEntry) -> Int {
            entry.titleKey.hasPrefix(query.folded) ? 0 : query.isFound(in: entry.titleKey) ? 1 : 2
        }
        return libraryEntries.filter { query.isFound(in: $0.key) }
            .map { (rank: rank($0), entry: $0) }
            .sorted { first, second in
                if first.rank != second.rank { return first.rank < second.rank }
                return first.entry.note.title.localizedStandardCompare(second.entry.note.title) == .orderedAscending
            }
            .map { LibraryHit(note: $0.entry.note, lead: $0.entry.lead) }
    }
}
