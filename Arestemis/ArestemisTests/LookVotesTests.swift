import Foundation
import Testing
@testable import Arestemis

@MainActor
struct LookVotesTests {
    private func content() throws -> SampleContent {
        try LookSample.content(SampleContent.contract(now: Clock.now))
    }

    private func match() throws -> Match {
        try #require(content().matches.first { $0.id == 34 })
    }

    private func setup() async throws -> (ArestemisStore, FakeTransport, Match, Rejected) {
        let content = try content()
        let match = try match()
        let entry = try #require(content.rejected.first { $0.id == 13 })
        let (store, transport, _) = try await makeStore()
        try transport.answer("GET /overview", encoding: content.overview)
        try transport.answer("GET /matches/34", encoding: match)
        try transport.answer("GET /rejected", encoding: RejectedPage(items: [entry]))
        await store.reloadOverview()
        await store.loadMatch(34)
        await store.loadRejected()
        await store.loadRejected(hunt: 5)
        return (store, transport, match, entry)
    }

    @Test func searchDefaultsAndAnEditedLookSurviveEncoding() throws {
        let old = try #require(sample([Hunt].self, "hunts").first { $0.id == 5 }?.search.item)
        #expect(old.look == "" && old.lookMin == 6)
        var search = old
        search.look = "Long coat, straight cut."
        search.lookMin = 8
        var draft = ItemSearchDraft(search)
        draft.priceMax = "120"
        // A draft saved and restored also retains the hidden look settings.
        draft = try JSONDecoder().decode(ItemSearchDraft.self, from: JSONEncoder().encode(draft))
        let edited = try #require(draft.search())
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(edited)) as? [String: Any])
        #expect(json["look"] as? String == search.look && json["look_min"] as? Int == 8)
        #expect(edited.priceMax == 120)
        #expect(try JSONDecoder().decode(ItemSearch.self, from: JSONEncoder().encode(edited)) == edited)
        let defaults = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        #expect(defaults["look"] as? String == "" && defaults["look_min"] as? Int == 6)
        var oldDraft = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(draft)) as? [String: Any])
        oldDraft.removeValue(forKey: "look")
        oldDraft.removeValue(forKey: "lookMin")
        let restored = try JSONDecoder().decode(ItemSearchDraft.self, from: JSONSerialization.data(withJSONObject: oldDraft))
        #expect(restored.look == "" && restored.lookMin == 6)
    }

    @Test func matchesAndRejectionsDecodeWithAndWithoutLookFields() throws {
        let match = try match()
        #expect(match.look?.score == 8 && match.look?.length == .long && match.look?.cut == .men && match.look?.fur == .real)
        #expect(match.vote == .up)
        #expect(match.look?.reason(language: .english) == "Long, straight cut with a broad collar.")
        #expect(match.look?.reason(language: .german) == "Langer, gerader Schnitt mit breitem Kragen.")
        #expect(try JSONDecoder().decode(Match.self, from: JSONEncoder().encode(match)) == match)
        let old = try sample(Match.self, "vinted-match")
        #expect(old.look == nil && old.vote == nil)
        #expect(try sample(RejectedPage.self, "rejected").items.allSatisfy { $0.vote == nil })
        let rejected = try #require(content().rejected.first { $0.id == 13 })
        #expect(try JSONDecoder().decode(Rejected.self, from: JSONEncoder().encode(rejected)).vote == .down)
    }

    @Test(arguments: ["up", "down", "future", "null", "number"])
    func votesDecodeLeniently(_ value: String) throws {
        let wire: Any = value == "null" ? NSNull() : value == "number" ? 7 : value
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(match())) as? [String: Any])
        object["vote"] = wire
        let decoded = try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.vote == Vote(rawValue: value))
        var entry = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(content().rejected[0])) as? [String: Any])
        entry["vote"] = wire
        #expect(try JSONDecoder().decode(Rejected.self, from: JSONSerialization.data(withJSONObject: entry)).vote == Vote(rawValue: value))
    }

    @Test func unknownLookCategoriesKeepTheScoreAndReason() throws {
        let data = Data(#"{"score":7,"length":"ankle","cut":"tailored","fur":"mixed","reason":"A broad collar.","reason_de":"Ein breiter Kragen."}"#.utf8)
        let verdict = try JSONDecoder().decode(LookVerdict.self, from: data)
        #expect(verdict.length == .unknown && verdict.cut == .unknown && verdict.fur == .unknown)
        #expect(verdict.score == 7 && verdict.reason == "A broad collar.")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(match())) as? [String: Any])
        object["look"] = NSNull()
        object["vote"] = NSNull()
        let decoded = try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.look == nil && decoded.vote == nil)
    }

    @Test(arguments: [Vote.up, .down, nil])
    func bothVoteRequestsSendTheExactPathAndExplicitNull(_ vote: Vote?) async throws {
        let transport = FakeTransport()
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        var answer = try match()
        answer.vote = vote
        try transport.answer("POST /matches/34/vote", encoding: answer)
        transport.answer("POST /rejected/13/vote", json: Data(#"{"id":13,"vote":null}"#.utf8))
        #expect(try await api.vote(vote, match: 34).vote == vote)
        try await api.vote(vote, rejected: 13)
        #expect(transport.requests.map(FakeTransport.key) == ["POST /matches/34/vote", "POST /rejected/13/vote"])
        for request in transport.requests {
            let json = try #require(try body(request))
            #expect(json.count == 1)
            if let vote { #expect(json["vote"] as? String == vote.rawValue) }
            else { #expect(json["vote"] is NSNull) }
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        }
    }

    @Test(arguments: [false, true])
    func matchVotesAreOptimisticAndRollbackOnFailure(_ fails: Bool) async throws {
        let (store, transport, original, _) = try await setup()
        let gate = RequestGate()
        transport.gates["POST /matches/34/vote"] = gate
        var answer = original
        answer.vote = .down
        if fails { transport.answer("POST /matches/34/vote", 500, json: Data(#"{"error":"Vote refused"}"#.utf8)) }
        else { try transport.answer("POST /matches/34/vote", encoding: answer) }
        let counts = store.overview?.counts
        let task = Task { await store.setVote(.down, for: 34) }
        await gate.waitUntilPaused()
        #expect(store.match(34)?.vote == .down && store.changingVotes.contains(34))
        #expect(store.match(34)?.state == .new)
        gate.resume()
        await task.value
        #expect(store.match(34)?.vote == (fails ? .up : .down))
        #expect(!store.changingVotes.contains(34) && store.overview?.counts == counts)
        #expect(store.notice?.text == (fails ? "Vote refused" : nil))
    }

    @Test(arguments: [false, true])
    func rejectedVotesUpdateEveryLoadedScopeAndRollback(_ fails: Bool) async throws {
        let (store, transport, _, original) = try await setup()
        let gate = RequestGate()
        transport.gates["POST /rejected/13/vote"] = gate
        transport.answer("POST /rejected/13/vote", fails ? 500 : 200,
                         json: Data((fails ? #"{"error":"Vote refused"}"# : #"{"id":13,"vote":"up"}"#).utf8))
        let task = Task { await store.setVote(.up, forRejected: 13) }
        await gate.waitUntilPaused()
        for scope in [nil, 5] as [Int?] {
            #expect(store.rejected(hunt: scope).items.only?.vote == .up)
        }
        gate.resume()
        await task.value
        for scope in [nil, 5] as [Int?] {
            #expect(store.rejected(hunt: scope).items.only?.vote == (fails ? original.vote : .up))
            #expect(store.rejected(hunt: scope).items.only?.id == original.id)
        }
        #expect(!store.changingRejectedVotes.contains(13))
        #expect(store.notice?.text == (fails ? "Vote refused" : nil))
    }

    @Test func tappingEachActiveVoteClearsIt() async throws {
        let (store, transport, original, _) = try await setup()
        var cleared = original
        cleared.vote = nil
        try transport.answer("POST /matches/34/vote", encoding: cleared)
        transport.answer("POST /rejected/13/vote", json: Data(#"{"id":13,"vote":null}"#.utf8))
        await store.setVote(.up, for: 34)
        await store.setVote(.down, forRejected: 13)
        #expect(store.match(34)?.vote == nil && store.rejected().items.only?.vote == nil)
        #expect(try body(transport.requests("POST /matches/34/vote").only)?["vote"] is NSNull)
        #expect(try body(transport.requests("POST /rejected/13/vote").only)?["vote"] is NSNull)
    }

    @Test func votesAreUnavailableForOtherFindingsAndSearches() async throws {
        let (store, transport, _, entry) = try await setup()
        #expect(store.canVote(on: entry))
        await store.setVote(.up, for: 41) // A flat, without a look.
        let ordinary = try sample(RejectedPage.self, "rejected").items[0]
        #expect(!store.canVote(on: ordinary))
        #expect(transport.requests.allSatisfy { !$0.url!.path.hasSuffix("/vote") })
    }

    @Test func olderRejectedRefreshDoesNotOverwriteACompletedVote() async throws {
        let (store, transport, _, _) = try await setup()
        let gate = RequestGate()
        transport.gates["GET /rejected"] = gate
        let reload = Task { await store.loadRejected() }
        await gate.waitUntilPaused()
        transport.answer("POST /rejected/13/vote", json: Data(#"{"id":13,"vote":"up"}"#.utf8))
        await store.setVote(.up, forRejected: 13)
        gate.resume()
        await reload.value
        #expect(store.rejected().items.only?.vote == .up)
    }

    @Test func aStateResponseKeepsAnIndependentVote() async throws {
        let (store, transport, original, _) = try await setup()
        let gate = RequestGate()
        transport.gates["POST /matches/34/state"] = gate
        var saved = original
        saved.state = .saved
        try transport.answer("POST /matches/34/state", encoding: saved)
        let saving = Task { await store.setState(.saved, for: 34) }
        await gate.waitUntilPaused()
        var voted = original
        voted.vote = .down
        try transport.answer("POST /matches/34/vote", encoding: voted)
        await store.setVote(.down, for: 34)
        #expect(store.match(34)?.state == .saved && store.match(34)?.vote == .down)
        gate.resume()
        await saving.value
        #expect(store.match(34)?.state == .saved && store.match(34)?.vote == .down)
    }

    @Test func aLateVoteCannotRestoreClearedAccountData() async throws {
        let (store, transport, original, _) = try await setup()
        let gate = RequestGate()
        transport.gates["POST /matches/34/vote"] = gate
        try transport.answer("POST /matches/34/vote", encoding: original)
        let voting = Task { await store.setVote(.down, for: 34) }
        await gate.waitUntilPaused()
        store.clear()
        gate.resume()
        await voting.value
        #expect(store.match(34) == nil && store.changingVotes.isEmpty && store.notice == nil)
    }

    @Test func sampleVotesUseTheSameInMemoryBackend() async throws {
        let backend = try SampleBackend(content: content())
        #expect(try await backend.vote(.down, match: 34).vote == .down)
        #expect(try await backend.vote(nil, match: 34).vote == nil)
        try await backend.vote(.up, rejected: 13)
        #expect(try await backend.rejected(hunt: 5, limit: 50).items.only?.vote == .up)
        try await backend.vote(nil, rejected: 13)
        #expect(try await backend.rejected(hunt: 5, limit: 50).items.only?.vote == nil)
    }
}
