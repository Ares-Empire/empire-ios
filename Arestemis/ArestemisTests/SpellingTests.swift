import Foundation
import Testing
@testable import Arestemis

/// Brief 178 (the server's brief 177): "Did you mean …" for a thing search's misspelled words. The answer as the contract
/// sends it, the request, the entry a suggestion replaces, and the save's flow: a suggestion holds the save, a tap
/// replaces exactly one entry, a second save with words already asked about saves, an error or a timeout saves at once,
/// and a change by hand clears the chips.
@MainActor
struct SpellingTests {
    private let zegna = Spelling.Suggestion(word: "Zenga Krawatte", suggestion: "Zegna Krawatte")
    private let ferragamo = Spelling.Suggestion(word: "Ferragammo Krawatte", suggestion: "Ferragamo Krawatte")

    /// A thing search that can be saved (shipped, so it needs no place) with these words as chips.
    private func draft(_ words: [String]) -> ItemSearchDraft {
        var draft = ItemSearchDraft()
        draft.delivery = .shipping
        for word in words { draft.add(word: word) }
        return draft
    }

    /// A server check that records what it was asked and answers `answer` (or throws `failure`).
    private nonisolated final class FakeCheck: @unchecked Sendable {
        var asked: [[String]] = []
        var answer = Spelling(suggestions: [], checked: true)
        var failure: Error?
        var delay: Duration = .zero
        var sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }

        var ask: @Sendable ([String]) async throws -> Spelling {
            { words in
                self.asked.append(words)
                if self.delay > .zero { try await self.sleep(self.delay) }
                if let failure = self.failure { throw failure }
                return self.answer
            }
        }
    }

    // MARK: the contract

    private func untimedCheck() -> SpellingCheck {
        let clock = TestClock()
        return SpellingCheck(sleep: { try await clock.sleep(for: $0) })
    }

    @Test func theAnswersDecode() throws {
        let found = try JSONDecoder().decode(Spelling.self, from: ArestemisSamples.spellingSuggestion)
        #expect(found == Spelling(suggestions: [zegna], checked: true))
        let unchecked = try JSONDecoder().decode(Spelling.self, from: ArestemisSamples.spellingUnchecked)
        #expect(unchecked == Spelling(suggestions: [], checked: false))
        // Lenient: nothing said is nothing to show.
        #expect(try JSONDecoder().decode(Spelling.self, from: Data("{}".utf8)) == Spelling(suggestions: [], checked: false))
        // Kept as it came.
        #expect(try JSONDecoder().decode(Spelling.self, from: JSONEncoder().encode(found)) == found)
    }

    @Test func theWordsAreSentAsTheContractSays() async throws {
        let transport = FakeTransport()
        transport.answer("POST /search/spelling", json: ArestemisSamples.spellingSuggestion)
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        let answer = try await api.spelling(words: ["Zenga Krawatte", "Kiton Krawatte"])
        #expect(answer.suggestions == [zegna] && answer.checked)
        let request = try #require(transport.requests("POST /search/spelling").only)
        #expect(try body(request)?["words"] as? [String] == ["Zenga Krawatte", "Kiton Krawatte"])
        #expect(request.timeoutInterval == 5)
    }

    @Test func onlySuggestionsForTheWordsAsTheyAreApply() {
        let answer = Spelling(suggestions: [
            zegna,
            Spelling.Suggestion(word: "Kiton Krawatte", suggestion: "KITON krawatte"),      // only the case: no change
            Spelling.Suggestion(word: "Hermès Krawatte", suggestion: "Hermes Krawatte"),     // a word not sent
            Spelling.Suggestion(word: "Zenga Krawatte", suggestion: "Zegna Tie"),            // a second for one word
            ferragamo,
        ], checked: true)
        #expect(answer.applicable(to: ["Zenga Krawatte", "Kiton Krawatte", "Ferragammo Krawatte"]) == [zegna, ferragamo])
        // In the words' order, not the answer's.
        #expect(answer.applicable(to: ["Ferragammo Krawatte", "Zenga Krawatte"]) == [ferragamo, zegna])
        #expect(Spelling(suggestions: [zegna], checked: false).applicable(to: ["Zenga Krawatte"]).isEmpty)
    }

    // MARK: the entry a suggestion replaces

    @Test func aSuggestionReplacesExactlyItsEntry() {
        var words = draft(["Zenga Krawatte", "Kiton Krawatte", "Ferragammo Krawatte"])
        let replaced1 = words.replace(word: "Ferragammo Krawatte", with: "Ferragamo Krawatte")
        #expect(replaced1)
        #expect(words.words == ["Zenga Krawatte", "Kiton Krawatte", "Ferragamo Krawatte"])
        let replaced2 = words.replace(word: "Zenga Krawatte", with: " Zegna Krawatte ")
        #expect(replaced2)
        #expect(words.words == ["Zegna Krawatte", "Kiton Krawatte", "Ferragamo Krawatte"])
        // A word the search does not have, or no word at all, changes nothing.
        let replaced3 = words.replace(word: "Hermès Krawatte", with: "Hermes Krawatte")
        #expect(!replaced3)
        let replaced4 = words.replace(word: "Kiton Krawatte", with: " ")
        #expect(!replaced4)
        #expect(words.words == ["Zegna Krawatte", "Kiton Krawatte", "Ferragamo Krawatte"])

        // The word still typed (sent as the last entry) is replaced where it is.
        var typed = draft(["Kiton Krawatte"])
        typed.type("Zenga Krawatte")
        #expect(typed.sentWords == ["Kiton Krawatte", "Zenga Krawatte"])
        let replaced5 = typed.replace(word: "Zenga Krawatte", with: "Zegna Krawatte")
        #expect(replaced5)
        #expect(typed.words == ["Kiton Krawatte"] && typed.typedWord == "Zegna Krawatte")

        // A correction that is there already: the misspelled entry goes, the other stays where it is.
        var repeated = draft(["Zegna Krawatte", "Zenga Krawatte", "Kiton Krawatte"])
        let replaced6 = repeated.replace(word: "Zenga Krawatte", with: "zegna krawatte")
        #expect(replaced6)
        #expect(repeated.words == ["Zegna Krawatte", "Kiton Krawatte"])
    }

    // MARK: the save's flow

    @Test func aSuggestionHoldsTheSave() async {
        let check = untimedCheck()
        let server = FakeCheck()
        server.answer = Spelling(suggestions: [zegna], checked: true)
        let words = ["Zenga Krawatte", "Kiton Krawatte"]
        #expect(await !check.beforeSaving(words, ask: server.ask))
        #expect(server.asked == [words])
        #expect(check.suggestions == [zegna] && !check.isChecking)
        // The chips stay while the words do.
        check.wordsChanged(words)
        #expect(check.suggestions == [zegna])
    }

    @Test func aTapReplacesExactlyOneEntryAndASecondSaveSaves() async {
        let check = untimedCheck()
        let server = FakeCheck()
        server.answer = Spelling(suggestions: [zegna, ferragamo], checked: true)
        var form = draft(["Zenga Krawatte", "Kiton Krawatte", "Ferragammo Krawatte"])
        #expect(await !check.beforeSaving(form.sentWords, ask: server.ask))
        #expect(check.suggestions == [zegna, ferragamo])

        // The extra word's chip: only that entry changes, the main words' chip stays.
        check.take(ferragamo, in: &form)
        #expect(form.words == ["Zenga Krawatte", "Kiton Krawatte", "Ferragamo Krawatte"])
        #expect(check.suggestions == [zegna])
        check.wordsChanged(form.sentWords)                  // the form's onChange after the tap
        #expect(check.suggestions == [zegna])

        // Save again: the words were asked about (the corrected one is the server's own), so it saves without asking.
        #expect(await check.beforeSaving(form.sentWords, ask: server.ask))
        #expect(server.asked.count == 1)
        #expect(form.search()?.query == "Zenga Krawatte" && form.search()?.moreQueries == ["Kiton Krawatte", "Ferragamo Krawatte"])

        // The main words' chip, then Save: also without asking again.
        check.take(zegna, in: &form)
        #expect(form.words == ["Zegna Krawatte", "Kiton Krawatte", "Ferragamo Krawatte"] && check.suggestions.isEmpty)
        #expect(await check.beforeSaving(form.sentWords, ask: server.ask))
        #expect(server.asked.count == 1)
    }

    @Test func noSuggestionAnErrorOrATimeoutSavesAtOnce() async {
        let words = ["Zenga Krawatte"]
        // No suggestion, and a check that could not run.
        for answer in [Spelling(suggestions: [], checked: true), Spelling(suggestions: [zegna], checked: false)] {
            let server = FakeCheck()
            server.answer = answer
            let check = untimedCheck()
            #expect(await check.beforeSaving(words, ask: server.ask))
            #expect(check.suggestions.isEmpty && server.asked == [words])
        }
        // A failure: saved, and not asked again in this form.
        let failing = FakeCheck()
        failing.failure = HTTPError.server(503, nil)
        let check = untimedCheck()
        #expect(await check.beforeSaving(words, ask: failing.ask))
        #expect(await check.beforeSaving(words, ask: failing.ask))
        #expect(failing.asked == [words] && check.suggestions.isEmpty)

        #expect(SpellingCheck.limit == .seconds(5))
    }

    @Test func timeoutReturnsWithinBudget() async {
        let words = ["Zenga Krawatte"]
        // Too slow: saved once the limit has passed, without its answer.
        let slow = FakeCheck()
        slow.answer = Spelling(suggestions: [zegna], checked: true)
        slow.delay = .seconds(30)
        let limited = SpellingCheck(limit: .milliseconds(50))
        let started = ContinuousClock.now
        #expect(await limited.beforeSaving(words, ask: slow.ask))
        #expect(ContinuousClock.now - started < .seconds(5))
        #expect(limited.suggestions.isEmpty && !limited.isChecking)
        // The form waits five seconds at most.
        #expect(SpellingCheck.limit == .seconds(5))
    }

    @Test func timeoutCancelsTheCheckWithoutItsSuggestions() async {
        let clock = TestClock()
        let slow = FakeCheck()
        slow.answer = Spelling(suggestions: [zegna], checked: true)
        slow.delay = .seconds(30)
        slow.sleep = { try await clock.sleep(for: $0) }
        let limited = SpellingCheck(limit: .milliseconds(50), sleep: { try await clock.sleep(for: $0) })
        let saving = Task { await limited.beforeSaving(["Zenga Krawatte"], ask: slow.ask) }
        await clock.sleeping(for: .seconds(30))
        await clock.sleeping(for: .milliseconds(50))
        #expect(limited.isChecking)
        clock.advance(by: .milliseconds(50))
        #expect(await saving.value)
        #expect(limited.suggestions.isEmpty && !limited.isChecking)
        #expect(SpellingCheck.limit == .seconds(5))
    }

    @Test func aChangeByHandClearsTheChipsAndItsWordsAreAskedNext() async {
        let check = untimedCheck()
        let server = FakeCheck()
        server.answer = Spelling(suggestions: [zegna], checked: true)
        var form = draft(["Zenga Krawatte", "Kiton Krawatte"])
        #expect(await !check.beforeSaving(form.sentWords, ask: server.ask))
        form.add(word: "Hermès Krawatte")
        check.wordsChanged(form.sentWords)
        #expect(check.suggestions.isEmpty)
        // The next save asks about the new word alone (the server has no suggestion for it) and saves.
        server.answer = Spelling(suggestions: [], checked: true)
        #expect(await check.beforeSaving(form.sentWords, ask: server.ask))
        #expect(server.asked == [["Zenga Krawatte", "Kiton Krawatte"], ["Hermès Krawatte"]])
        server.answer = Spelling(suggestions: [Spelling.Suggestion(word: "Ferragammo Krawatte",
                                                                   suggestion: "Ferragamo Krawatte")], checked: true)
        form.add(word: "Ferragammo Krawatte")
        #expect(await !check.beforeSaving(form.sentWords, ask: server.ask))
        // Removing a word clears them too.
        form.removeWord(at: 0)
        check.wordsChanged(form.sentWords)
        #expect(check.suggestions.isEmpty)
        #expect(server.asked.last == ["Ferragammo Krawatte"])
    }

    @Test func theCheckIsBusyWhileItRunsThroughTheStore() async throws {
        let transport = FakeTransport()
        transport.answer("POST /search/spelling", json: ArestemisSamples.spellingSuggestion)
        let gate = RequestGate()
        transport.gates["POST /search/spelling"] = gate
        let (store, _, _) = try await makeStore(transport: transport)
        let check = untimedCheck()
        let ask: @Sendable ([String]) async throws -> Spelling = { [store] words in try await store.spelling(words) }
        let saving = Task { await check.beforeSaving(["Zenga Krawatte"], ask: ask) }
        await gate.waitUntilPaused()
        #expect(check.isChecking)
        // A second tap meanwhile saves nothing.
        let again = await check.beforeSaving(["Zenga Krawatte"], ask: ask)
        #expect(!again)
        gate.resume()
        let saved = await saving.value
        #expect(!saved)
        #expect(!check.isChecking && check.suggestions == [zegna])
        #expect(transport.requests("POST /search/spelling").count == 1)
    }

    // MARK: the sample

    @Test func theSampleSuggestsAsTheServerWould() async throws {
        let sample = try SampleBackend()
        let answer = try await sample.spelling(words: ["Zenga Krawatte", "Kiton Krawatte", "Ferragammo  Krawatte"])
        #expect(answer.checked)
        #expect(answer.suggestions == [zegna, Spelling.Suggestion(word: "Ferragammo  Krawatte",
                                                                  suggestion: "Ferragamo  Krawatte")])
        let unchecked = try await SampleBackend(options: .init(spelling: "unchecked")).spelling(words: ["Zenga Krawatte"])
        #expect(unchecked == Spelling(suggestions: [], checked: false))
        await #expect(throws: (any Error).self) {
            _ = try await SampleBackend(options: .init(spelling: "failed")).spelling(words: ["Zenga Krawatte"])
        }
        let options = LaunchOptions(arguments: ["-sampleData", "-sampleSpelling", "slow"])
        #expect(options.spelling == "slow")
    }

    // MARK: the chips' words

    @Test(arguments: [AppLanguage.english, .german])
    func theHeadingIsTheUberallFormsOwn(_ language: AppLanguage) {
        #expect(language.string("Did you mean…") == (language == .german ? "Meintest du …" : "Did you mean…"))
    }
}
