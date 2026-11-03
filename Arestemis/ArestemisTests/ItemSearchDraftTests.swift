import Foundation
import Testing
@testable import Arestemis

@MainActor
struct ItemSearchDraftTests {
    private func valid() -> ItemSearchDraft {
        var draft = ItemSearchDraft()
        draft.words = ["Office chair"]
        draft.delivery = .shipping
        return draft
    }
    @Test func validatesAndConvertsEveryField() throws {
        var draft = valid()
        draft.exclude = ["broken"]
        draft.priceMin = "100,5"
        draft.priceMax = "450"
        draft.conditionMin = .good
        draft.forParts = true
        draft.radiusKm = "25"
        draft.seller = .private
        draft.extra = "  size B  "
        let search = try #require(draft.search())
        #expect(search.query == "Office chair" && search.exclude == ["broken"] && search.priceMin == 100.5)
        #expect(search.priceMax == 450 && search.vbOverMax == 45 && search.conditionMin == .good && search.forParts)
        #expect(search.delivery == .shipping && search.places.isEmpty && search.radiusKm == 25)
        #expect(search.seller == .private && search.extra == "size B" && search.sources == [.kleinanzeigen])
        #expect(ItemSearchDraft(search).search() == search)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(search)) as? [String: Any])
        #expect(Set(object.keys) == ["query", "more_queries", "exclude", "price_min", "price_max", "vb_over_max", "condition_min",
                                     "for_parts", "auctions", "delivery", "places", "radius_km", "seller", "extra",
                                     "sources"])
        draft.priceMin = ""
        draft.priceMax = ""
        draft.conditionMin = nil
        let clearedSearch = try #require(draft.search())
        let cleared = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(clearedSearch)) as? [String: Any])
        #expect(cleared["price_min"] is NSNull && cleared["price_max"] is NSNull && cleared["condition_min"] is NSNull)
    }
    @Test func limitsAndMalformedNumbers() throws {
        var d = valid()
        #expect(d.isValid)
        d.words = ["a"]; #expect(d.problems.contains(.words))
        d.words = [String(repeating: "a", count: 100)]; #expect(d.isValid)
        d.words[0] += "a"; #expect(d.problems.contains(.words)); d.words = ["Chair"]
        d.exclude = Array(repeating: "word", count: 21); #expect(d.problems.contains(.exclude))
        d.exclude = [String(repeating: "a", count: 41)]; #expect(d.problems.contains(.exclude)); d.exclude = []
        d.priceMin = "100"; d.priceMax = "90"; #expect(d.problems.contains(.priceOrder))
        d.priceMin = "abc"; #expect(d.problems.contains(.priceMin) && d.search() == nil)
        d.priceMax = "nan"; #expect(d.problems.contains(.priceMax)); d.priceMin = ""; d.priceMax = ""
        d.vbOverMax = "-1"; #expect(d.problems.contains(.vbOverMax)); d.vbOverMax = "0"
        d.radiusKm = "201"; #expect(d.problems.contains(.radius)); d.radiusKm = "-1"; #expect(!d.isValid)
        d.radiusKm = "200"; #expect(d.isValid); d.radiusKm = "0"; #expect(d.isValid)
        d.conditionMin = .forParts; #expect(d.problems.contains(.condition)); d.conditionMin = nil
        d.extra = String(repeating: "a", count: 1001); #expect(d.problems.contains(.extra)); d.extra = ""
        d.sources = []; #expect(d.problems.contains(.sources))
    }
    @Test func deliveryNeedsPlacesExceptShipping() throws {
        var draft = valid()
        draft.delivery = .pickup; #expect(draft.problems.contains(.places))
        draft.delivery = .either; #expect(draft.problems.contains(.places))
        let place = try #require(try sample([Place].self, "places").first)
        draft.places = Array(repeating: place, count: 5); #expect(draft.isValid)
        draft.places.append(place); #expect(draft.problems.contains(.places))
    }
    @Test func vbDefaultTracksMaximumUntilEdited() throws {
        var draft = valid()
        draft.priceMax = "455"; #expect(draft.vbOverMax == "46" && !draft.vbOverMaxTouched)
        draft.priceMax = "100"; #expect(draft.vbOverMax == "10")
        draft.vbOverMax = "0"
        draft.priceMax = "500"; #expect(draft.vbOverMax == "0" && draft.vbOverMaxTouched)
        let restored = try JSONDecoder().decode(ItemSearchDraft.self, from: JSONEncoder().encode(draft))
        #expect(restored == draft && restored.vbOverMaxTouched)
    }
    @Test func fillingMergesAndKeepsUnsaidFields() throws {
        var draft = valid()
        draft.extra = "Fictional preference"
        draft.exclude = ["broken"]
        let place = try #require(try sample([Place].self, "places").first)
        draft.apply(PartialItemSearch(query: "Aeron", exclude: ["broken", "replica"], priceMax: 450,
                                      conditionMin: .likeNew, forParts: false, delivery: .either, places: [place],
                                      radiusKm: 20, seller: .private, extra: "", sources: []))
        #expect(draft.words == ["Office chair", "Aeron"] && draft.exclude == ["broken", "replica"] && draft.vbOverMax == "45")
        #expect(draft.extra == "Fictional preference" && draft.sources == [.kleinanzeigen] && draft.places == [place])
        draft.apply(PartialItemSearch(vbOverMax: 0, places: [place]))
        draft.apply(PartialItemSearch(priceMax: 500))
        #expect(draft.vbOverMax == "0" && draft.places == [place])
        let partial = try JSONDecoder().decode(PartialItemSearch.self, from: Data(#"{"query":null,"exclude":null}"#.utf8))
        let previous = draft
        draft.apply(partial); #expect(draft == previous)
    }
    @Test func draftsAreSeparateForHuntsNewKindsAndAccounts() throws {
        let defaults = try #require(UserDefaults(suiteName: "arestemis-113-\(UUID())"))
        let kept = KeptSearchDraft(defaults: defaults)
        defer { kept.clear() }
        var first = valid(); first.priceMin = "invalid"
        var second = valid(); second.words = ["Desk"]
        kept.keep(first, saved: nil, account: "a", huntID: 2)
        kept.keep(second, saved: nil, account: "a", huntID: 4)
        kept.keep(second, saved: nil, account: "a")
        var flat = SearchDraft(); flat.extra = "Flat edits"
        kept.keep(flat, saved: nil, account: "a")
        #expect(kept.restore(ItemSearchDraft.self, saved: nil, account: "a", huntID: 2) == first)
        #expect(kept.restore(ItemSearchDraft.self, saved: nil, account: "a", huntID: 4) == second)
        #expect(kept.restore(ItemSearchDraft.self, saved: nil, account: "a") == second)
        #expect(kept.restore(SearchDraft.self, saved: nil, account: "a") == flat)
        #expect(kept.restore(ItemSearchDraft.self, saved: nil, account: "b", huntID: 2) == ItemSearchDraft())
        kept.drop(account: "a", huntID: 2, kind: .item)
        #expect(kept.restore(ItemSearchDraft.self, saved: nil, account: "a", huntID: 2) == ItemSearchDraft())
        #expect(kept.restore(ItemSearchDraft.self, saved: nil, account: "a", huntID: 4) == second)
        let baseline = try #require(second.search())
        kept.keep(first, saved: ItemSearchDraft(baseline), account: "a", huntID: 4)
        var changed = baseline; changed.query = "Table"
        #expect(kept.restore(saved: ItemSearchDraft(changed), account: "a", huntID: 4) == ItemSearchDraft(changed))
    }
}
