import Foundation
import Testing
import UserNotifications
@testable import Arestemis

@MainActor
struct HuntsStoreTests {
    @Test func changingOneHuntIsOptimisticAndRollsBack() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        let original = store.hunts
        transport.answer("POST /hunts/2/active", 409, json: Data(#"{"error":"At most 10 hunts can run at once. Pause one first."}"#.utf8))
        let gate = RequestGate(); transport.gates["POST /hunts/2/active"] = gate
        let action = Task { await store.setActive(id: 2, active: false) }
        await gate.waitUntilPaused()
        #expect(store.hunts[1].hunt.active == false && store.hunts[0] == original[0])
        gate.resume(); await action.value
        #expect(store.hunts == original)
        #expect(store.notice?.text == "At most 10 hunts can run at once. Pause one first.")
    }
    @Test(arguments: ["save", "rename", "delete"])
    func changesRollbackOnlyTheirHunt(_ operation: String) async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        let original = store.hunts
        let route = operation == "delete" ? "DELETE /hunts/2" : "PUT /hunts/2"
        transport.answer(route, 400, json: Data(#"{"error":"Fictional refusal"}"#.utf8))
        let gate = RequestGate(); transport.gates[route] = gate
        let action = Task {
            if operation == "delete" { return await store.deleteHunt(id: 2) }
            if operation == "rename" { return await store.renameHunt(id: 2, name: "Chair") }
            var search = try #require(original[1].hunt.search.item); search.priceMax = 300
            return await store.saveHunt(id: 2, kind: .item, name: nil, search: .item(search)) != nil
        }
        await gate.waitUntilPaused()
        #expect(store.hunts[0] == original[0])
        if operation == "delete" { #expect(!store.hunts.contains { $0.id == 2 }) }
        else if operation == "rename" { #expect(store.hunts[1].hunt.name == "Chair") }
        else { #expect(store.hunts[1].hunt.search.item?.priceMax == 300) }
        gate.resume(); #expect(try await action.value == false)
        #expect(store.hunts == original && store.searchError == "Fictional refusal" && store.notice?.text == "Fictional refusal")
    }
    @Test func failedCreationRemovesPendingCardAndKeepsTheServerSentence() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        let original = store.hunts
        transport.answer("POST /hunts", 409, json: Data(#"{"error":"This account has 30 hunts. Delete one first."}"#.utf8))
        let gate = RequestGate(); transport.gates["POST /hunts"] = gate
        let action = Task { await store.saveHunt(id: nil, kind: .item, name: nil, search: original[1].hunt.search) }
        await gate.waitUntilPaused()
        #expect(store.hunts.count == 9 && store.hunts.last?.id == -1)
        gate.resume(); #expect(await action.value == nil)
        #expect(store.hunts == original && store.searchError == "This account has 30 hunts. Delete one first.")
    }
    @Test func sampleActionsAndFiltersStayPerHunt() async throws {
        let backend = try SampleBackend()
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: backend, sample: true)
        await store.reloadOverview()
        let originalFlat = try #require(store.card(1)?.hunt)
        let item = store.hunts[1].hunt
        #expect(await store.renameHunt(id: 2, name: "  Chair  "))
        #expect(store.hunts[1].hunt.name == "Chair" && store.card(1)?.hunt == originalFlat)
        #expect(await store.renameHunt(id: 2, name: nil) && store.hunts[1].hunt.name == nil)
        await store.setActive(id: 2, active: false)
        #expect(store.hunts[1].sources.isEmpty && !store.hunts[1].hunt.active)
        await store.setActive(id: 2, active: true)
        #expect(store.hunts[1].sources == [.kleinanzeigen, .ebay])
        store.selectedHuntID = 2
        await store.loadMatches(.all)
        #expect(store.matches(.all).map(\.id) == [32, 31, 30, 29, 28])
        await store.loadRejected(); #expect(store.rejected.isEmpty)
        await store.loadApplication(for: 31)
        #expect(store.application(31).error == "Application texts are for flats.")
        let new = try #require(await store.saveHunt(id: nil, kind: .item, name: "Second chair", search: item.search))
        #expect(new.id == 9 && !new.active && store.hunts.count == 9)
        #expect(await store.deleteHunt(id: 2))
        #expect(store.selectedHuntID == nil && store.card(1)?.hunt == originalFlat && !store.hunts.contains { $0.id == 2 })
        #expect(store.match(31) == nil && store.match(41) != nil && store.application(31).error == nil)
        await store.loadMatches(.all)
        #expect(store.matches(.all).allSatisfy { $0.huntID != 2 } && store.matches(.all).contains { $0.huntID == 1 })
    }
    @Test func staleFilteredPagesDoNotReplaceTheNewSelection() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        try transport.answer("GET /matches", sample: "item-matches")
        store.selectedHuntID = 2
        let gate = RequestGate(); transport.gates["GET /matches"] = gate
        let load = Task { await store.loadMatches(.all) }
        await gate.waitUntilPaused()
        store.selectedHuntID = 1
        try transport.answer("GET /matches", sample: "matches")
        await store.loadMatches(.all)
        gate.resume(); await load.value
        #expect(store.matches(.all).map(\.id) == [41, 40, 38] && store.list(.all).ids == [41, 40, 38])
        #expect(store.match(31) == nil && !store.list(.all).isLoading)
        let queries = transport.requests("GET /matches").compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "hunt" }?.value }
        #expect(queries == ["2", "1"])
    }
    @Test func sampleLimitsHaveTheContractSentences() async throws {
        let backend = try SampleBackend(options: .init(noHunt: true))
        let search = try sample([Hunt].self, "hunts")[1].search
        for i in 0..<30 {
            let hunt = try await backend.createHunt(kind: .item, name: "Chair \(i)", search: search)
            if i < 10 { _ = try await backend.setActive(id: hunt.id, active: true) }
        }
        do { _ = try await backend.createHunt(kind: .item, name: nil, search: search); Issue.record("Expected 30 hunt limit") }
        catch HTTPError.server(let code, let sentence) {
            #expect(code == 409 && sentence == "This account has 30 hunts. Delete one first.")
        }
        do { _ = try await backend.setActive(id: 11, active: true); Issue.record("Expected active hunt limit") }
        catch HTTPError.server(let code, let sentence) {
            #expect(code == 409 && sentence == "At most 10 hunts can run at once. Pause one first.")
        }
        _ = try await backend.setActive(id: 1, active: false)
        #expect(try await backend.setActive(id: 11, active: true).active)
        try await backend.deleteHunt(id: 30)
        #expect(try await backend.createHunt(kind: .item, name: nil, search: search).id == 31)
    }
    @Test func itemPushHasOnlyOpenListing() throws {
        let item = try #require(MatchNotification.categories.first { $0.identifier == "ARESTEMIS_ITEM" })
        #expect(item.actions.map(\.identifier) == [MatchNotification.openListingAction])
        #expect(item.actions.map(\.title) == ["Open listing"])
        #expect(MatchNotification.link(url: URL(string: "arestemis://match/31"), action: item.actions[0].identifier)
                == ArestemisLink(match: 31, then: .openListing))
        let options = LaunchOptions(arguments: ["-sampleData", "-sampleHunt", "2"])
        #expect(options.sample && options.sampleHunt == 2)
    }
}
