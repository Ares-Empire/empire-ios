import Foundation
import Observation

/// The search over the found listings (brief 133; the server's side is brief 132, `GET /matches?q=`): of every search, or
/// of one (its page's icon). Asked once typing pauses and at least two letters are typed; a newer query cancels the older
/// one. The server ranks; the results keep its order, best match first. While a newer query is asked, the last results
/// stay on screen.
@MainActor @Observable
final class ListingSearch {
    /// The server's bounds for `q` (trimmed, 2–100 characters).
    nonisolated static let minimumLength = 2
    nonisolated static let maximumLength = 100
    /// How many listings one answer brings (the server's default is 30, its most 100).
    nonisolated static let limit = 50
    /// The pause in typing before the server is asked.
    nonisolated static let delay: Duration = .milliseconds(300)

    /// What the page shows.
    enum Phase: Equatable {
        /// Fewer than two letters: the hint.
        case typing
        /// Asked, nothing to show yet.
        case searching
        /// Results (perhaps of the words before, while newer ones are asked).
        case found
        /// The server found nothing for these words.
        case nothingFound(String)
        /// The request failed: the sentence, with Try again.
        case failed(String)
    }

    /// The search this one is limited to; nil = every search.
    let hunt: Int?
    /// What the field holds.
    private(set) var text = ""
    /// Best match first, for `searched`.
    private(set) var results: [Match] = []
    /// More listings match than were returned.
    private(set) var more = false
    /// The words the results are for.
    private(set) var searched: String?
    private(set) var isSearching = false
    private(set) var error: String?

    /// The words of the latest request (asked, answered or failed).
    @ObservationIgnored private var asked: String?
    @ObservationIgnored private var task: Task<Void, Never>?
    private let delay: Duration
    private let fetch: (String) async throws -> MatchPage

    init(hunt: Int?, delay: Duration = ListingSearch.delay, fetch: @escaping (String) async throws -> MatchPage) {
        self.hunt = hunt
        self.delay = delay
        self.fetch = fetch
    }

    /// The words to ask for: trimmed, at most 100 characters; nil below two.
    nonisolated static func words(_ text: String) -> String? {
        let trimmed = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.count >= minimumLength ? trimmed : nil
    }

    var phase: Phase {
        guard let words = Self.words(text) else { return .typing }
        if let error { return .failed(error) }
        if !results.isEmpty { return .found }
        if !isSearching, searched == words { return .nothingFound(words) }
        return .searching
    }

    /// The field changed: once typing pauses, the server is asked for its words (unless they are the words already
    /// asked, as after a space typed at the end).
    func update(_ text: String) {
        self.text = text
        let words = Self.words(text)
        guard words != asked else { return }
        task?.cancel()
        asked = words
        guard let words else {
            results = []
            more = false
            searched = nil
            isSearching = false
            error = nil
            return
        }
        ask(words, after: delay)
    }

    /// Try again: the same words, at once.
    func retry() {
        guard let words = asked else { return }
        task?.cancel()
        ask(words, after: .zero)
    }

    /// Waits for the request in flight (tests).
    func settle() async { await task?.value }

    private func ask(_ words: String, after pause: Duration) {
        isSearching = true
        error = nil
        task = Task { [fetch] in
            if pause > .zero { try? await Task.sleep(for: pause) }
            guard !Task.isCancelled else { return }
            do {
                let page = try await fetch(words)
                guard !Task.isCancelled else { return }
                results = page.items
                more = page.more
                searched = words
            } catch is CancellationError {
                // Dropped (a login that ended meanwhile): nothing to say.
                if !Task.isCancelled { isSearching = false }
                return
            } catch {
                guard !Task.isCancelled else { return }
                results = []
                more = false
                searched = nil
                self.error = error.localizedDescription
            }
            isSearching = false
        }
    }
}
