import Foundation
import Observation

/// `POST /search/spelling` (the Arestemis repo's brief 177, this app's brief 178; Patrik, 2026-11-05, after a thing
/// search for "Zenga Krawatte" where the brand is Zegna: "a false suggestion isn't that bad"): the server's guess at a
/// misspelled brand, model or product word among a thing search's words. The user decides: a suggestion is a chip under
/// the words, taken with a tap or left as it is; nothing is changed or saved by itself.
nonisolated struct Spelling: Codable, Equatable, Sendable {
    nonisolated struct Suggestion: Codable, Equatable, Hashable, Sendable {
        /// The entry exactly as it was sent ("Zenga Krawatte"): the main words or one of the more words.
        let word: String
        /// The whole entry with only the misspelled word corrected ("Zegna Krawatte").
        let suggestion: String
    }

    var suggestions: [Suggestion]
    /// False when the server could not check (its AI unavailable, limited or too slow); `suggestions` is then empty.
    var checked: Bool

    init(suggestions: [Suggestion], checked: Bool) {
        self.suggestions = suggestions
        self.checked = checked
    }

    /// Lenient: a missing list is empty, a missing `checked` is false (nothing to show either way).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        suggestions = try c.decodeIfPresent([Suggestion].self, forKey: .suggestions) ?? []
        checked = try c.decodeIfPresent(Bool.self, forKey: .checked) ?? false
    }

    /// The suggestions that apply to `words`: checked, about one of them as written, and different from it (a
    /// suggestion the server would drop too). At most one per word, in the words' order.
    @MainActor func applicable(to words: [String]) -> [Suggestion] {
        guard checked else { return [] }
        var found: [Suggestion] = []
        for word in words where !found.contains(where: { $0.word == word }) {
            guard let suggestion = suggestions.first(where: {
                $0.word == word && SearchWords.lengths.contains(Self.trimmed($0.suggestion).count)
                    && SearchWords.key($0.suggestion) != SearchWords.key(word)
            }) else { continue }
            found.append(suggestion)
        }
        return found
    }

    private static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
}

/// A thing form's spelling check (brief 178), from opening the form until it closes. Saving asks the server about the
/// words not asked about yet, waiting at most `limit`; with a suggestion the save waits and the chips show under the
/// words ("Did you mean…", the Überall form's look). A chip's tap puts its suggestion in place of exactly that entry;
/// Save again saves the words as they are then, without asking again about words already asked about. A change of the
/// words by hand removes the chips; its new words are asked about at the next save. An error, a timeout,
/// `checked: false` or no suggestion saves at once, without a word.
@MainActor @Observable
final class SpellingCheck {
    /// The longest a save waits for the server's answer (it answers within about 4 s, usually under one).
    static let limit: Duration = .seconds(5)

    /// The suggestions shown under the words, in the words' order.
    private(set) var suggestions: [Spelling.Suggestion] = []
    /// A check is on its way: the save button shows its busy state.
    private(set) var isChecking = false
    /// The words asked about already in this form (`SearchWords.key`), whatever the answer, and the suggestions shown.
    @ObservationIgnored private var asked: Set<String> = []
    /// The words the chips belong to, as they are now (a chip's tap changes one of them, a change by hand clears them).
    @ObservationIgnored private var shownFor: [String] = []
    @ObservationIgnored private let limit: Duration

    init(limit: Duration = SpellingCheck.limit) {
        self.limit = limit
    }

    /// Before saving `words` (the search's `query` and `more_queries`, as they will be sent): true when the save goes
    /// on now; false when the server suggested a correction (the chips show and the save waits), or while a check is
    /// on its way. `ask` is the server's check (`ArestemisStore.spelling`); it must end when its task is cancelled, as
    /// a request does.
    func beforeSaving(_ words: [String], ask: @escaping @Sendable ([String]) async throws -> Spelling) async -> Bool {
        guard !isChecking else { return false }
        let new = unasked(words)
        guard !new.isEmpty else { return true }
        isChecking = true
        let answer = await Self.answer(new, within: limit, ask: ask)
        isChecking = false
        asked.formUnion(new.map(SearchWords.key))
        let found = answer?.applicable(to: words) ?? []
        guard !found.isEmpty else { return true }
        // A suggestion taken is the server's own word: not asked about again.
        asked.formUnion(found.map { SearchWords.key($0.suggestion) })
        suggestions = found
        shownFor = words
        return false
    }

    /// The words as they are now (the form calls it on every change): the chips stay through their own taps and go
    /// at any other change.
    func wordsChanged(_ words: [String]) {
        guard !suggestions.isEmpty, words != shownFor else { return }
        suggestions = []
        shownFor = []
    }

    /// A chip's tap: its entry takes the suggestion (`ItemSearchDraft.replace`) and its chip goes; the others stay.
    func take(_ suggestion: Spelling.Suggestion, in draft: inout ItemSearchDraft) {
        guard let index = suggestions.firstIndex(of: suggestion) else { return }
        suggestions.remove(at: index)
        draft.replace(word: suggestion.word, with: suggestion.suggestion)
        shownFor = suggestions.isEmpty ? [] : draft.sentWords
    }

    /// The words not asked about yet, each once.
    private func unasked(_ words: [String]) -> [String] {
        var keys = asked
        return words.filter { keys.insert(SearchWords.key($0)).inserted }
    }

    /// The server's answer, or nil after `limit`, a failure or a cancelled save.
    private nonisolated static func answer(_ words: [String], within limit: Duration,
                                           ask: @escaping @Sendable ([String]) async throws -> Spelling) async -> Spelling? {
        await withTaskGroup(of: Spelling?.self) { group in
            group.addTask { try? await ask(words) }
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
