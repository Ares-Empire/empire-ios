import Foundation
import Testing
@testable import Arestemis

/// The Search tab's form: from and to the contract's search, validation, and "Describe it".
@MainActor
struct SearchDraftTests {
    private let calendar = Clock.berlin

    private func sampleSearch() throws -> Search {
        try #require(try sample(Overview.self, "overview").hunt?.search)
    }

    private var munich: Place { Place(id: "wg:90", name: "München", region: "Bayern", sources: [.wgGesucht]) }

    @Test func theSampleSearchRoundTrips() throws {
        let search = try sampleSearch()
        let draft = SearchDraft(search, calendar: calendar)
        #expect(draft.kinds == [.flat, .wgEmpty] && draft.tiers.count == 1 && draft.isValid)
        #expect(draft.search(calendar: calendar) == search)
    }

    @Test func aNewSearch() {
        let draft = SearchDraft()
        #expect(draft.sources == Set(Source.allCases) && draft.sublet == .exclude && draft.furnished == .any)
        #expect(draft.problems == [.noKind, .noPlace])
        #expect(draft.hint == "Choose at least a kind and a place.")
    }

    @Test func hintsNameWhatIsMissing() {
        var draft = SearchDraft()
        draft.sources = []
        #expect(draft.hint == "Choose at least a kind, a place and a portal.")
        draft.toggle(.flat)
        draft.add(munich)
        #expect(draft.hint == "Choose at least a portal.")
        draft.sources = [.immowelt]
        #expect(draft.isValid && draft.hint == nil)
    }

    @Test func tiers() {
        var draft = SearchDraft()
        draft.toggle(.flat)
        draft.add(munich)
        draft.tiers = [SearchDraft.Tier()]
        #expect(draft.isValid && draft.search(calendar: calendar).rentTiers.isEmpty)     // an empty row is ignored
        draft.tiers[0].sqmMin = 40
        #expect(draft.problems == [.incompleteTier])
        #expect(draft.hint == "Fill in both numbers of a size tier, or remove it.")
        draft.tiers[0].rentMaxWarm = 1200
        #expect(draft.isValid && draft.search(calendar: calendar).rentTiers == [RentTier(sqmMin: 40, rentMaxWarm: 1200)])
    }

    @Test func moveInMustBeInOrder() throws {
        var draft = SearchDraft(try sampleSearch(), calendar: calendar)
        draft.moveInUntil = DateOnly.parse("2026-11-01", calendar: calendar)
        #expect(draft.problems == [.moveInOrder])
        draft.moveInUntil = nil
        #expect(draft.isValid && draft.search(calendar: calendar).moveInUntil == nil)
    }

    @Test func roomsOnlyForAFlatAndFlatmatesOnlyForAWG() throws {
        var draft = SearchDraft(try sampleSearch(), calendar: calendar)
        draft.kinds = [.wgRoom]
        #expect(draft.search(calendar: calendar).roomsMin == nil && draft.search(calendar: calendar).flatmatesMax == 1)
        draft.kinds = [.flat]
        #expect(draft.search(calendar: calendar).roomsMin == 1 && draft.search(calendar: calendar).flatmatesMax == nil)
        #expect(draft.asksRooms && !draft.asksFlatmates)
    }

    /// The flat's size for an own flat or an empty 2-person WG, the room's size for a room in a WG.
    @Test func sizesFollowTheKinds() throws {
        var draft = SearchDraft(try sampleSearch(), calendar: calendar)
        draft.roomSqmMin = 15
        #expect(draft.asksFlatSize && !draft.asksRoomSize)
        #expect(draft.search(calendar: calendar).sqmMin == 28 && draft.search(calendar: calendar).roomSqmMin == nil)
        draft.kinds = [.wgRoom]
        #expect(!draft.asksFlatSize && draft.asksRoomSize)
        #expect(draft.search(calendar: calendar).sqmMin == nil && draft.search(calendar: calendar).roomSqmMin == 15)
        draft.kinds = [.wgEmpty, .wgRoom]
        #expect(draft.search(calendar: calendar).sqmMin == 28 && draft.search(calendar: calendar).roomSqmMin == 15)
        draft.apply(PartialSearch(roomSqmMin: 18), calendar: calendar)
        #expect(draft.roomSqmMin == 18)
    }

    @Test func kindsAndPortalsKeepTheContractsOrder() {
        var draft = SearchDraft()
        draft.toggle(.wgEmpty)
        draft.toggle(.flat)
        draft.toggle(.wgRoom)
        draft.toggle(.wgRoom)
        draft.sources = [.immowelt, .wgGesucht]
        let search = draft.search(calendar: calendar)
        #expect(search.kinds == [.flat, .wgEmpty] && search.sources == [.wgGesucht, .immowelt])
    }

    @Test func placesAndDistricts() {
        var draft = SearchDraft()
        draft.add(munich)
        draft.add(munich)
        #expect(draft.places.count == 1)
        let added = draft.addDistrict("  Schwabing ")
        let repeated = draft.addDistrict("schwabing")
        let blank = draft.addDistrict("   ")
        #expect(added && !repeated && !blank)
        #expect(draft.districts == ["Schwabing"])
        draft.extra = "  Balkon \n"
        #expect(draft.search(calendar: calendar).extra == "Balkon")
    }

    @Test func describeItFillsOnlyWhatItSaid() throws {
        var draft = SearchDraft(try sampleSearch(), calendar: calendar)
        let garching = Place(id: "wg:400", name: "Garching bei München", region: "Bayern", sources: [.wgGesucht])
        let freising = Place(id: "wg:500", name: "Freising", region: "Bayern", sources: [.wgGesucht])
        draft.apply(PartialSearch(kinds: [.wgRoom], places: [garching, freising], districts: ["Schwabing", "Au"],
                                  rentMaxWarm: 700, moveInFrom: "2027-01-01", sublet: .include), calendar: calendar)
        let search = draft.search(calendar: calendar)
        #expect(search.kinds == [.wgRoom] && search.rentMaxWarm == 700 && search.sublet == .include)
        #expect(search.places.map(\.id) == ["wg:90", "wg:400", "wg:500"])
        #expect(search.districts == ["Schwabing", "Maxvorstadt", "Freimann", "Au"])
        #expect(search.moveInFrom == "2027-01-01" && search.moveInUntil == "2027-02-01")
        #expect(search.furnished == .any && search.extra == "Balkon wäre schön, kein Erdgeschoss")
        #expect(draft.sqmMin == 28 && search.sqmMin == nil)        // kept in the form, not sent for a room
        #expect(search.rentTiers == [RentTier(sqmMin: 40, rentMaxWarm: 1200)])

        draft.apply(PartialSearch(kinds: [], extra: "", sources: []), calendar: calendar)    // empty says nothing
        #expect(draft.search(calendar: calendar) == search)
    }
}
