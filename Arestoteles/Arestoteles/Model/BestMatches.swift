import Foundation
import Observation

/// The Search tab's best matches: the server's passages for the query (`GET /search`), found by their words and by
/// their meaning (Patrik asked for search "kinda like Google"), shown above the device's own results.
///
/// - Asked once typing pauses (`Timing.pause`) and the query has at least three letters; a newer query cancels the
///   request before it. The device's results never wait for it.
/// - While a newer query is on its way the last answer stays on screen (nothing jumps); a quiet placeholder only when
///   there is nothing to show and the server takes longer than `Timing.slow`.
/// - No connection, an error, a 503 or no answer within `Timing.timeout`: no best matches, nothing said; the device's
///   results stand alone.
/// - `listing` merges both: up to eight passages that still exist in the app's vault (an answer from an older vault
///   commit is fine), then the device's sentences without those passages, then its notes and terms.
@MainActor @Observable
final class BestMatches {
    struct Timing: Sendable {
        var pause: Duration = .milliseconds(400)
        var slow: Duration = .milliseconds(600)
        var timeout: Duration = .seconds(5)
    }

    /// At most this many rows; a few more are asked for, in case some passages are no longer in the app's vault.
    static let shown = 8
    static let asked = 12
    /// The contract's limit for `q`.
    static let maximumLength = 200

    /// The query asked of the server (trimmed); nil while the field holds too little.
    private(set) var query: String?
    /// The last answer; it stays while a newer query is on its way.
    private(set) var answer: SearchAnswer?
    /// A request for `query` waits for the pause or the server.
    private(set) var isWaiting = false
    /// It has waited longer than `Timing.slow`.
    private(set) var isSlow = false

    @ObservationIgnored private var answered: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    private let timing: Timing
    private let fetch: @MainActor (String) async throws -> SearchAnswer

    init(timing: Timing = Timing(), fetch: @escaping @MainActor (String) async throws -> SearchAnswer) {
        self.timing = timing
        self.fetch = fetch
    }

    /// The search field changed: ask for the new query once typing pauses (the same query again asks nothing).
    func update(_ text: String) {
        let next = Self.asked(text)
        if let next, next == query, isWaiting || answered == next { return }
        if next == nil, query == nil, answer == nil, !isWaiting { return }
        task?.cancel()
        query = next
        isSlow = false
        guard let next else {
            answer = nil
            answered = nil
            isWaiting = false
            return
        }
        isWaiting = true
        task = Task { [timing, fetch] in
            do { try await Task.sleep(for: timing.pause) } catch { return }
            let slow = Task {
                do { try await Task.sleep(for: timing.slow) } catch { return }
                if query == next, isWaiting { isSlow = true }
            }
            let found = await Self.first(within: timing.timeout) { try await fetch(next) }
            slow.cancel()
            guard !Task.isCancelled, query == next else { return }
            isWaiting = false
            isSlow = false
            answer = found
            answered = found == nil ? nil : next
        }
    }

    /// Forgets everything (logout).
    func reset() {
        task?.cancel()
        task = nil
        query = nil
        answer = nil
        answered = nil
        isWaiting = false
        isSlow = false
    }

    /// Waits for the request in flight (tests).
    func settle() async { await task?.value }

    /// What the Search tab shows for `text` (the field as typed) and the type filter.
    func listing(_ text: String, type: NoteType?, search: VaultSearch, index: VaultIndex) -> SearchListing {
        Self.listing(text, type: type, answer: answer, waiting: isWaiting, slow: isSlow, search: search, index: index)
    }

    /// The merge, pure: a type filter narrows the search to notes, so passages (the server's and the device's) are only
    /// for "Everything".
    static func listing(_ text: String, type: NoteType?, answer: SearchAnswer?, waiting: Bool, slow: Bool,
                        search: VaultSearch, index: VaultIndex) -> SearchListing {
        var listing = SearchListing(results: search.results(text, type: type))
        guard type == nil else { return listing }
        listing.best = rows(answer?.results ?? [], index: index)
        listing.sentences = remaining(search.sentences(text), after: listing.best)
        listing.waiting = waiting && listing.best.isEmpty
        listing.placeholder = slow && listing.best.isEmpty
        return listing
    }

    /// The server's passages that still exist in the app's vault, best first, without repeats, at most `shown`.
    static func rows(_ hits: [SearchHit], index: VaultIndex) -> [BestMatch] {
        var seen: Set<String> = []
        var rows: [BestMatch] = []
        for hit in hits where rows.count < shown {
            guard let note = index.note(hit.note), exists(hit, in: note, index: index) else { continue }
            let row = BestMatch(hit: hit, title: note.title)
            if seen.insert(row.id).inserted { rows.append(row) }
        }
        return rows
    }

    /// The passage is still there in the app's vault: the position exists on that note, or the block is a passage
    /// (and a list has that item).
    static func exists(_ hit: SearchHit, in note: Note, index: VaultIndex) -> Bool {
        if let position = hit.position { return index.position(position)?.note == note.id }
        guard note.blocks.indices.contains(hit.block) else { return false }
        switch note.blocks[hit.block] {
        case let .list(_, items): return hit.item.map(items.indices.contains) ?? true
        case let .table(_, rows): return hit.item.map(rows.indices.contains) ?? true
        case .paragraph, .quote, .callout: return hit.item == nil
        case .heading, .positions, .embed, .sectionLink, .rule, .unknown: return false
        }
    }

    /// The device's sentences without those of the passages already shown as best matches.
    static func remaining(_ sentences: [VaultSearch.SentenceHit], after best: [BestMatch]) -> [VaultSearch.SentenceHit] {
        let shown = Set(best.filter { $0.hit.position == nil }.map { passageKey($0.hit.note, $0.hit.block, $0.hit.item) })
        return sentences.filter { !shown.contains(passageKey($0.passage.note, $0.passage.block, $0.passage.item)) }
    }

    private static func passageKey(_ note: String, _ block: Int, _ item: Int?) -> String { "\(note)|\(block)|\(item ?? -1)" }

    /// The query as it is asked: trimmed, at most `maximumLength` characters; nil below three letters or digits.
    static func asked(_ text: String) -> String? {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count(where: { $0.isLetter || $0.isNumber }) >= 3 ? trimmed : nil
    }

    /// The operation's answer, or nil when it fails or takes longer than `limit` (it is then cancelled).
    private static func first(within limit: Duration,
                              _ operation: @escaping @MainActor () async throws -> SearchAnswer) async -> SearchAnswer? {
        await withTaskGroup(of: SearchAnswer?.self) { group in
            group.addTask { try? await operation() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}

/// One of the server's passages as the Search tab shows it.
struct BestMatch: Equatable, Identifiable {
    let hit: SearchHit
    /// The note's title in the app's vault.
    let title: String

    var id: String { "\(hit.note)|\(hit.block)|\(hit.item ?? -1)|\(hit.position ?? "")" }
    /// Where it stands: "Printing press · 1. How print spread".
    var place: String { [title, hit.heading].compactMap { $0 }.joined(separator: " · ") }
    /// The query's words are marked in its sentence, unless it was found by its meaning alone.
    var marksWords: Bool { hit.match != .meaning }
    /// A tap opens the position's page, or the note scrolled to the passage, marked.
    var route: Route { hit.position.map(Route.position) ?? .note(NoteLink(note: hit.note, block: hit.block)) }
}

/// What the Search tab shows for a query, in order.
struct SearchListing {
    var best: [BestMatch] = []                          // the server's passages
    var sentences: [VaultSearch.SentenceHit] = []       // the device's, without the passages above
    var results: [VaultSearch.Result] = []              // the device's notes and glossary terms
    /// The server may still send passages: "Nothing found" waits.
    var waiting = false
    /// The server is slow and there is nothing of it yet: a quiet line where its passages will come.
    var placeholder = false

    var isEmpty: Bool { best.isEmpty && sentences.isEmpty && results.isEmpty }
}
