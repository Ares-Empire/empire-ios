import Foundation

/// The lookups the screens need, built once per vault: notes and positions by id, backlinks, the topic overviews, the
/// library (mechanisms with how often they are used, events by year and region, questions, actors). Pure: the tests
/// build it from the samples.
nonisolated struct VaultIndex: Sendable {
    /// One year of the events timeline (`year` nil: events without a year, at the end).
    struct EventYear: Equatable, Sendable {
        let year: Int?
        let events: [Note]
    }

    static let empty = VaultIndex(vault: nil)

    private let notes: [String: Note]
    private let positions: [String: Position]
    private let eventsByYear: [Int: [Note]]
    /// Topic overviews, by title.
    let topics: [Note]
    /// Mechanisms, by title.
    let mechanisms: [Note]
    /// Events by `from` (then title); events without a year last.
    let events: [Note]
    /// Every region an event names, sorted.
    let regions: [String]
    let questions: [Note]
    let actors: [Note]
    /// Where a position can be added: "Positions" (across topics) first, then each topic overview.
    let positionTargets: [Note]
    /// How many notes use each mechanism (link to it), without the index pages.
    private let mechanismUse: [String: Int]

    init(vault: Vault?) {
        let all = vault?.notes ?? []
        notes = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        positions = Dictionary((vault?.positions ?? []).flatMap(\.positions).map { ($0.id, $0) },
                               uniquingKeysWith: { first, _ in first })
        let byTitle: (Note, Note) -> Bool = { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        topics = all.filter(\.isTopicOverview).sorted(by: byTitle)
        mechanisms = all.filter { $0.type == .mechanism }.sorted(by: byTitle)
        questions = all.filter { $0.type == .question }.sorted(by: byTitle)
        actors = all.filter { $0.type == .actor }.sorted(by: byTitle)
        events = all.filter { $0.type == .event }.sorted { first, second in
            switch (first.event?.from, second.event?.from) {
            case let (a?, b?) where a != b: a < b
            case (.some, nil): true
            case (nil, .some): false
            default: byTitle(first, second)
            }
        }
        regions = Set(events.flatMap { $0.event?.where ?? [] }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        eventsByYear = Dictionary(grouping: events.filter { $0.event?.from != nil }) { $0.event!.from! }
        positionTargets = all.filter { $0.type == .positions } + topics
        let indexPages: Set<NoteType> = [.home, .positions, .glossary]
        let notes = self.notes
        mechanismUse = Dictionary(uniqueKeysWithValues: mechanisms.map { mechanism in
            (mechanism.id, mechanism.backlinks.count { notes[$0].map { !indexPages.contains($0.type) } ?? false })
        })
    }

    func note(_ id: String) -> Note? { notes[id] }

    /// The "discuss later" marks not yet discussed (Inbox notes of kind discuss, status new), newest first.
    var openDiscussions: [Note] {
        notes.values.filter { $0.inbox?.kind == .discuss && $0.inbox?.isOpen == true }
            .sorted { $0.id > $1.id }       // Inbox names start with the date and time
    }

    func position(_ id: String) -> Position? { positions[id] }

    /// The notes that link to this one, in the server's order (by id); ids the vault does not know are left out.
    func backlinks(of id: String) -> [Note] { (notes[id]?.backlinks ?? []).compactMap { notes[$0] } }

    /// The notes a position names as its evidence.
    func evidence(of position: Position) -> [Note] { position.evidence.compactMap { notes[$0] } }

    /// The title of a note id, or the id itself when the vault does not know it.
    func title(_ id: String) -> String { notes[id]?.title ?? id }

    func mechanismUses(_ id: String) -> Int { mechanismUse[id] ?? 0 }

    func events(inYear year: Int) -> [Note] { eventsByYear[year] ?? [] }

    /// The events timeline, one entry per year, for one region or all of them.
    func timeline(region: String? = nil) -> [EventYear] {
        let shown = events.filter { region == nil || ($0.event?.where.contains(region!) ?? false) }
        var years: [EventYear] = []
        for event in shown {
            let year = event.event?.from
            if let last = years.last, last.year == year {
                years[years.count - 1] = EventYear(year: year, events: last.events + [event])
            } else {
                years.append(EventYear(year: year, events: [event]))
            }
        }
        return years
    }

    /// What an event led to ("what followed"), as notes.
    func followed(_ event: Note) -> [Note] { event.ledTo.compactMap { notes[$0] } }

    /// The part of a note an embed shows: the blocks under the heading `anchor` up to the next heading of the same or a
    /// higher level, the heading included; the whole body without an anchor; empty when the note or heading is missing.
    func section(of id: String, anchor: String?) -> [Block] {
        guard let note = notes[id] else { return [] }
        guard let anchor else { return note.blocks }
        guard let start = note.blocks.firstIndex(where: {
            if case let .heading(_, _, found) = $0 { found == anchor } else { false }
        }), case let .heading(level, _, _) = note.blocks[start] else { return [] }
        var end = note.blocks.index(after: start)
        while end < note.blocks.endIndex {
            if case let .heading(next, _, _) = note.blocks[end], next <= level { break }
            end = note.blocks.index(after: end)
        }
        return Array(note.blocks[start..<end])
    }

    /// The positions of a topic overview's brief, or of any note, as positions (unknown ids left out).
    func positions(_ ids: [String]) -> [Position] { ids.compactMap { positions[$0] } }
}
