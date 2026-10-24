import Foundation
import Testing
@testable import Arestoteles

/// The Search tab's best matches: asked once typing pauses, a newer query cancels the older request, failures and
/// timeouts show nothing, a placeholder only for a slow server; merged with the device's results (passages that left
/// the app's vault are left out, the device does not repeat a passage shown above). The request itself: the contract's
/// route with the login's token, 401 and 403 through the login.
@MainActor
struct BestMatchesTests {
    /// A server in memory for `BestMatches`: records the queries, answers the sample, can take its time or fail.
    @MainActor
    final class FakeServer {
        var asked: [String] = []
        var cancelled: [String] = []
        var delay: [String: Duration] = [:]
        var failing: Set<String> = []

        func search(_ query: String) async throws -> SearchAnswer {
            asked.append(query)
            if let delay = delay[query] {
                do { try await Task.sleep(for: delay) } catch {
                    cancelled.append(query)
                    throw error
                }
            }
            if failing.contains(query) { throw HTTPError.server(503, nil) }
            return try sample(SearchAnswer.self, "search")
        }
    }

    /// An answer for "printers sold" on the sample vault, written here (not the sample file, which the server's own
    /// sample replaces): a position, passages with the words, passages by meaning only.
    static let printersSold = SearchAnswer(commit: "a1b2c3d", meaning: true, results: [
        SearchHit(note: "Printing press", block: 1, position: "Printing press#2", heading: "My position",
                  text: "Printers were businessmen first; they printed what sold.",
                  sentence: "Printers were businessmen first; they printed what sold.", match: .both),
        SearchHit(note: "Information wants to be cheap", block: 2, heading: "My take",
                  text: "The printers were businessmen first: they printed Luther because Luther sold.",
                  sentence: "The printers were businessmen first: they printed Luther because Luther sold.", match: .both),
        SearchHit(note: "Spread of print", block: 2, heading: "Trade routes, not borders",
                  text: "Printers went where paper, money and readers were.",
                  sentence: "Printers went where paper, money and readers were.", match: .words),
        SearchHit(note: "Martin Luther", block: 0, text: "Monk and professor in Wittenberg.",
                  sentence: "Monk and professor in Wittenberg.", match: .meaning),
        SearchHit(note: "Reformation", block: 2, item: 0, heading: "Mechanisms at work",
                  text: "Information wants to be cheap: pamphlets outsold books",
                  sentence: "Information wants to be cheap: pamphlets outsold books", match: .meaning),
    ])

    private func matches(_ server: FakeServer) -> BestMatches {
        BestMatches(timing: .quick) { query in try await server.search(query) }
    }

    // MARK: - asking

    @Test func askedOnceTypingPausesWithThreeLetters() async throws {
        let server = FakeServer()
        let matches = matches(server)
        matches.update("p")
        matches.update("pr")
        #expect(matches.query == nil && !matches.isWaiting)
        for typed in ["pri", "prin", "print"] { matches.update(typed) }
        #expect(matches.query == "print" && matches.isWaiting)
        await matches.settle()
        let expected = try sample(SearchAnswer.self, "search")
        #expect(server.asked == ["print"])
        #expect(matches.answer == expected && !matches.isWaiting && !matches.isSlow)
        // Digits count as letters (a year), spaces do not; the query is trimmed and cut to the contract's 200.
        #expect(BestMatches.asked("1517") == "1517" && BestMatches.asked(" a b ") == nil)
        #expect(BestMatches.asked("  printers sold  ") == "printers sold")
        #expect(BestMatches.asked(String(repeating: "x", count: 250))?.count == 200)
    }

    @Test func aNewerQueryCancelsTheRequestInFlight() async throws {
        let server = FakeServer()
        server.delay["print"] = .seconds(30)
        let matches = matches(server)
        matches.update("print")
        #expect(await eventually { server.asked == ["print"] })
        matches.update("printers")
        await matches.settle()
        #expect(server.asked == ["print", "printers"])
        #expect(await eventually { server.cancelled == ["print"] })
        #expect(matches.query == "printers" && matches.answer != nil && !matches.isWaiting)
    }

    @Test func theSameQueryIsNotAskedAgainUnlessItFailed() async throws {
        let server = FakeServer()
        let matches = matches(server)
        matches.update("print")
        await matches.settle()
        matches.update("print ")
        matches.update(" print")
        await matches.settle()
        #expect(server.asked == ["print"])

        server.failing = ["zebra"]
        matches.update("zebra")
        await matches.settle()
        matches.update("zebra ")
        await matches.settle()
        #expect(server.asked == ["print", "zebra", "zebra"])
    }

    @Test func tooLittleTypedClearsTheAnswer() async throws {
        let matches = matches(FakeServer())
        matches.update("print")
        await matches.settle()
        #expect(matches.answer != nil)
        matches.update("pr")
        #expect(matches.answer == nil && matches.query == nil && !matches.isWaiting)
    }

    @Test func theAnswerStaysWhileTheNextIsOnItsWay() async throws {
        let server = FakeServer()
        server.delay["printers"] = .milliseconds(200)
        let matches = matches(server)
        matches.update("print")
        await matches.settle()
        matches.update("printers")
        #expect(matches.answer != nil && matches.isWaiting)
        await matches.settle()
        #expect(matches.answer != nil && !matches.isWaiting)
    }

    // MARK: - failures, timeouts, the placeholder

    @Test func aFailureShowsNothing() async throws {
        let server = FakeServer()
        server.failing = ["printers"]
        let matches = matches(server)
        matches.update("print")
        await matches.settle()
        matches.update("printers")
        await matches.settle()
        // The earlier answer goes too: only the device's results remain.
        #expect(matches.answer == nil && !matches.isWaiting && !matches.isSlow)
    }

    @Test func noAnswerInTimeShowsNothingAndCancelsTheRequest() async throws {
        let server = FakeServer()
        server.delay["print"] = .seconds(30)
        let matches = matches(server)
        let start = ContinuousClock.now
        matches.update("print")
        await matches.settle()
        #expect(ContinuousClock.now - start < .seconds(5))
        #expect(matches.answer == nil && !matches.isWaiting && !matches.isSlow)
        #expect(server.cancelled == ["print"])
    }

    @Test func thePlaceholderOnlyForASlowServer() async throws {
        let server = FakeServer()
        server.delay["print"] = .milliseconds(250)
        let matches = matches(server)
        matches.update("print")
        #expect(!matches.isSlow)
        #expect(await eventually { matches.isSlow })
        await matches.settle()
        #expect(!matches.isSlow && matches.answer != nil)

        // A quick answer never shows it.
        let quick = self.matches(FakeServer())
        var everSlow = false
        quick.update("print")
        while quick.isWaiting {
            everSlow = everSlow || quick.isSlow
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(!everSlow && quick.answer != nil)
    }

    @Test func resetForgetsEverything() async throws {
        let server = FakeServer()
        server.delay["printers"] = .seconds(30)
        let matches = matches(server)
        matches.update("print")
        await matches.settle()
        matches.update("printers")
        matches.reset()
        await matches.settle()
        #expect(matches.query == nil && matches.answer == nil && !matches.isWaiting && !matches.isSlow)
    }

    // MARK: - the merge

    @Test func bestMatchesComeFirstAndTheDeviceDropsTheirSentences() throws {
        let vault = try sampleVault()
        let search = VaultSearch(vault: vault)
        let index = VaultIndex(vault: vault)
        let listing = BestMatches.listing("printers sold", type: nil, answer: Self.printersSold,
                                          waiting: false, slow: false, search: search, index: index)
        #expect(listing.best.map(\.title) == ["Printing press", "Information wants to be cheap", "Spread of print",
                                              "Martin Luther", "Reformation"])
        #expect(listing.best.map(\.place) == ["Printing press · My position", "Information wants to be cheap · My take",
                                              "Spread of print · Trade routes, not borders", "Martin Luther",
                                              "Reformation · Mechanisms at work"])
        // A position opens its page, a passage its note at that block; meaning-only rows mark no words.
        #expect(listing.best.map(\.route) == [.position("Printing press#2"),
                                              .note(NoteLink(note: "Information wants to be cheap", block: 2)),
                                              .note(NoteLink(note: "Spread of print", block: 2)),
                                              .note(NoteLink(note: "Martin Luther", block: 0)),
                                              .note(NoteLink(note: "Reformation", block: 2))])
        #expect(listing.best.map(\.marksWords) == [true, true, true, false, false])
        // The device found two sentences; the one shown above is not repeated.
        #expect(search.sentences("printers sold").map(\.passage.note) == ["Information wants to be cheap", "Printing press"])
        #expect(listing.sentences.map { "\($0.passage.note)|\($0.passage.block)" } == ["Printing press|6"])
        #expect(listing.results == search.results("printers sold") && !listing.results.isEmpty)
        #expect(!listing.isEmpty && !listing.placeholder && !listing.waiting)
    }

    @Test func passagesNoLongerInTheVaultAreLeftOut() throws {
        let index = try sampleIndex()
        func hit(_ note: String, _ block: Int, item: Int? = nil, position: String? = nil) -> SearchHit {
            SearchHit(note: note, block: block, item: item, position: position, text: "x", sentence: "x", match: .both)
        }
        let rows = BestMatches.rows([
            hit("Gone", 0),                                         // the note is gone
            hit("Gutenberg Bible", 5),                              // the block is gone
            hit("Printing press", 0),                               // a heading now
            hit("Printing press", 9, item: 4),                      // the list is shorter
            hit("Printing press", 3, item: 0),                      // an item of a paragraph
            hit("Printing press", 1, position: "Printing press#9"), // the position is gone
            hit("Positions", 2, position: "Printing press#1"),      // the position stands on another note
            hit("Printing press", 3),
            hit("Printing press", 3),                               // a repeat
            hit("Printing press", 9, item: 0),
            hit("Printing press", 1, position: "Printing press#1"),
            hit("Spread of print", 3),                              // a callout
        ], index: index)
        #expect(rows.map(\.id) == ["Printing press|3|-1|", "Printing press|9|0|", "Printing press|1|-1|Printing press#1",
                                   "Spread of print|3|-1|"])

        // At most eight.
        let passages = try sampleVault().notes.flatMap(Lookup.passages(of:))
        let many = passages.map { hit($0.note, $0.block, item: $0.item) }
        #expect(Set(many.map { "\($0.note)|\($0.block)|\($0.item ?? -1)" }).count > BestMatches.shown)
        #expect(BestMatches.rows(many, index: index).count == BestMatches.shown)
    }

    @Test func aTypeFilterShowsTheDevicesNotesOnly() throws {
        let vault = try sampleVault()
        let search = VaultSearch(vault: vault)
        let listing = BestMatches.listing("reformation", type: .event, answer: try sample(SearchAnswer.self, "search"),
                                          waiting: true, slow: true, search: search, index: VaultIndex(vault: vault))
        #expect(listing.best.isEmpty && listing.sentences.isEmpty && !listing.placeholder && !listing.waiting)
        #expect(listing.results == search.results("reformation", type: .event))
    }

    @Test func nothingFoundWaitsForTheServer() throws {
        let vault = try sampleVault()
        let search = VaultSearch(vault: vault)
        let index = VaultIndex(vault: vault)
        // A question in other words: nothing on the device, the server still busy.
        let waiting = BestMatches.listing("wer hat gedruckt", type: nil, answer: nil, waiting: true, slow: false,
                                          search: search, index: index)
        #expect(waiting.isEmpty && waiting.waiting && !waiting.placeholder)
        let slow = BestMatches.listing("wer hat gedruckt", type: nil, answer: nil, waiting: true, slow: true,
                                       search: search, index: index)
        #expect(slow.placeholder)
        let done = BestMatches.listing("wer hat gedruckt", type: nil, answer: nil, waiting: false, slow: false,
                                       search: search, index: index)
        #expect(done.isEmpty && !done.waiting && !done.placeholder)
        // With best matches on screen, no placeholder and no waiting, whatever the next request does.
        let shown = BestMatches.listing("wer hat gedruckt", type: nil, answer: Self.printersSold,
                                        waiting: true, slow: true, search: search, index: index)
        #expect(!shown.best.isEmpty && !shown.placeholder && !shown.waiting)
    }

    // MARK: - the answer and the request

    @Test func theContractsAnswerDecodes() throws {
        let answer = try JSONDecoder().decode(SearchAnswer.self, from: Data("""
            {"commit": "8db2491", "meaning": true, "results": [
              {"note": "Printing press", "block": 4, "item": 2, "position": null, "heading": "Spread",
               "text": "Within 50 years **presses** stood in more than 200 towns.",
               "sentence": "Within 50 years presses stood in more than 200 towns.", "match": "both"},
              {"note": "Printing press", "block": 1, "item": null, "position": "Printing press#1", "heading": null,
               "text": "A position.", "sentence": "A position.", "match": "rhyme"}]}
            """.utf8))
        #expect(answer.commit == "8db2491" && answer.meaning)
        #expect(answer.results.first == SearchHit(note: "Printing press", block: 4, item: 2, heading: "Spread",
                                                  text: "Within 50 years **presses** stood in more than 200 towns.",
                                                  sentence: "Within 50 years presses stood in more than 200 towns.",
                                                  match: .both))
        // A way of matching the app does not know reads as words.
        #expect(answer.results.last?.position == "Printing press#1" && answer.results.last?.match == .words)
    }

    @Test func theRequestIsTheContractsRoute() async throws {
        let transport = FakeTransport()
        try transport.answer("GET /search", sample: "search")
        let api = ArestotelesAPI(transport: transport, token: { "fictional-token" })
        let expected = try sample(SearchAnswer.self, "search")
        let answer = try await api.search("C++ & Kriege? Wie", limit: 12)
        #expect(answer == expected)
        let request = try #require(transport.requests.only)
        // Everything but the unreserved characters is encoded, so "+" and "&" stay part of the query.
        #expect(request.url?.absoluteString
                == "https://www.ares-empire.de/api/arestoteles/search?q=C%2B%2B%20%26%20Kriege%3F%20Wie&limit=12")
        #expect(request.httpMethod == "GET" && request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        #expect(request.timeoutInterval == 5)
    }

    @Test func theStoreAsksWithTheLoginAndALimit() async throws {
        let h = try await makeStore()
        try h.transport.answer("GET /search", sample: "search")
        await h.store.refresh()
        h.store.bestMatches.update("printers sold")
        await h.store.bestMatches.settle()
        let expected = try sample(SearchAnswer.self, "search")
        #expect(h.store.bestMatches.answer == expected)
        let url = try #require(h.transport.requests("GET /search").only?.url)
        #expect(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
                == [URLQueryItem(name: "q", value: "printers sold"), URLQueryItem(name: "limit", value: "12")])
    }

    @Test func a503OrNoConnectionSaysNothing() async throws {
        let h = try await makeStore()
        await h.store.refresh()
        h.transport.answer("GET /search", 503, json: Data(#"{"error":"Still loading."}"#.utf8))
        h.store.bestMatches.update("printers")
        await h.store.bestMatches.settle()
        #expect(h.store.bestMatches.answer == nil && h.session.isSignedIn)
        #expect(!h.store.isOffline && h.store.loadError == nil && h.store.notice == nil)

        h.transport.failure = URLError(.notConnectedToInternet)
        h.store.bestMatches.update("printers sold")
        await h.store.bestMatches.settle()
        #expect(h.store.bestMatches.answer == nil && h.session.isSignedIn && h.store.vault != nil)
        #expect(!h.store.isOffline && h.store.notice == nil)
    }

    @Test func a401EndsTheLoginA403ClosesTheApp() async throws {
        let h = try await makeStore()
        await h.store.refresh()
        h.transport.answer("GET /search", 401, json: Data(#"{"error":"Token rejected."}"#.utf8))
        h.store.bestMatches.update("printers")
        await h.store.bestMatches.settle()
        #expect(!h.session.isSignedIn && h.store.vault == nil && h.store.bestMatches.query == nil)

        let denied = try await makeStore()
        await denied.store.refresh()
        denied.transport.answer("GET /search", 403, json: Data(#"{"error":"No arestoteles service."}"#.utf8))
        denied.store.bestMatches.update("printers")
        await denied.store.bestMatches.settle()
        #expect(denied.session.access == .denied("No arestoteles service.") && denied.store.vault == nil)
    }

    @Test func theSampleAnswersEveryQueryWithPassagesOfTheSampleVault() async throws {
        let session = EmpireSession(app: .arestoteles, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = VaultStore(session: session, backend: try SampleBackend(), persistence: MemoryPersistence(),
                               spotlight: NoSpotlight(), savedAccount: { nil }, sample: true,
                               searchTiming: BestMatches.Timing(pause: .milliseconds(20), timeout: .seconds(5)))
        await store.update()
        store.bestMatches.update("anything at all")
        await store.bestMatches.settle()
        let answer = try #require(store.bestMatches.answer)
        // Every passage exists in the sample vault, so none is left out.
        #expect(!answer.results.isEmpty)
        #expect(BestMatches.rows(answer.results, index: store.index).count
                == min(answer.results.count, BestMatches.shown))
    }
}
