import Foundation
import Testing
@testable import Arestemis

@MainActor
struct HuntsAPITests {
    @Test func newRoutesAndBodies() async throws {
        let transport = FakeTransport()
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        let hunt = try sample([Hunt].self, "hunts")[1]
        try transport.answer("GET /hunts", sample: "hunts")
        #expect(try await api.hunts().count == 5)
        try transport.answer("POST /hunts", encoding: hunt)
        _ = try await api.createHunt(kind: .item, name: "Office chair", search: hunt.search)
        let created = try #require(try body(transport.requests.last))
        #expect(Set(created.keys) == ["kind", "name", "search"] && created["kind"] as? String == "item")
        #expect(created["name"] as? String == "Office chair")
        #expect((created["search"] as? [String: Any])?["price_max"] as? Double == 450)
        try transport.answer("PUT /hunts/2", encoding: hunt)
        _ = try await api.updateHunt(id: 2, search: hunt.search, name: nil)
        let updated = try #require(try body(transport.requests.last))
        #expect(Set(updated.keys) == ["search", "name"] && updated["name"] is NSNull)
        // Renaming sends the name alone (PATCH), so the server does not start the search again.
        try transport.answer("PATCH /hunts/2", encoding: hunt)
        _ = try await api.renameHunt(id: 2, name: "Chair")
        let renamed = try #require(try body(transport.requests.last))
        #expect(transport.requests.last?.httpMethod == "PATCH" && Set(renamed.keys) == ["name"] && renamed["name"] as? String == "Chair")
        _ = try await api.renameHunt(id: 2, name: nil)
        #expect(try body(transport.requests.last)?["name"] is NSNull)
        transport.answer("POST /search/parse", json: Data(#"{"search":{"query":"Chair","price_max":450},"unclear":["Which size?"]}"#.utf8))
        guard case .item(let parsed) = try await api.parse(text: "An office chair", kind: .item) else {
            Issue.record("Expected an item parse result"); return
        }
        #expect(parsed.search.query == "Chair" && parsed.search.priceMax == 450 && parsed.unclear == ["Which size?"])
        #expect(try body(transport.requests.last)?["kind"] as? String == "item")
        #expect(transport.requests.last?.timeoutInterval == 60)
    }
    @Test func huntFiltersReachBothRoutes() async throws {
        let transport = FakeTransport()
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        try transport.answer("GET /matches", sample: "item-matches")
        _ = try await api.matches(hunt: 2, state: [.new], limit: 20, before: 31)
        let query = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [.init(name: "hunt", value: "2"), .init(name: "state", value: "new"),
                           .init(name: "limit", value: "20"), .init(name: "before", value: "31")])
        try transport.answer("GET /rejected", sample: "rejected")
        _ = try await api.rejected(hunt: 2, limit: 10)
        #expect(URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
                == [.init(name: "limit", value: "10"), .init(name: "hunt", value: "2")])
    }
}
