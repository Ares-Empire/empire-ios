import Foundation
import Testing
@testable import Arestemis

/// The Search tab's form: from and to the contract's search, validation, and "Describe it".
@MainActor
struct SearchDraftTests {
    private let calendar = Clock.berlin

    private func sampleSearch() throws -> Search {
        try #require(try sample(Overview.self, "overview").hunt?.search.flat)
    }

    private var munich: Place { Place(id: "wg:90", name: "München", region: "Bayern", sources: [.wgGesucht]) }

    @Test func theSampleSearchRoundTrips() throws {
        let search = try sampleSearch()
        let draft = SearchDraft(search, calendar: calendar)
        #expect(draft.type == .any && draft.people == 1 && draft.warmRent == .init(min: 400, max: 1000) && draft.isValid)
        #expect(draft.search(calendar: calendar) == search)
    }

    /// Only a place and a portal are required; everything else starts as "any".
    @Test func aNewSearch() {
        var draft = SearchDraft()
        #expect(draft.type == .any && draft.people == 1 && draft.sources == Set(Source.flatPortals) && draft.sublet == .exclude)
        #expect(draft.problems == [.noPlace] && draft.hint == "Choose a place.")
        draft.add(munich)
        #expect(draft.isValid)
        let search = draft.search(calendar: calendar)
        #expect(search.kinds == [.flat, .wg] && search.people == 1)
        #expect([search.sqmMin, search.sqmMax, search.roomSqmMin, search.roomSqmMax, search.roomsMin, search.rentColdMin,
                 search.rentColdMax, search.rentWarmMin, search.rentWarmMax].allSatisfy { $0 == nil })
        #expect(search.flatmatesMax == nil && search.moveInFrom == nil && search.moveInUntil == nil && search.extra.isEmpty)
    }

    @Test func hintsNameWhatIsMissing() {
        var draft = SearchDraft()
        draft.sources = []
        #expect(draft.hint == "Choose a place and at least one portal.")
        draft.add(munich)
        #expect(draft.hint == "Choose at least one portal.")
        draft.sources = [.immowelt]
        #expect(draft.isValid && draft.hint == nil)
    }

    @Test func eachRangeMustBeInOrder() {
        var draft = SearchDraft()
        draft.add(munich)
        draft.warmRent = .init(min: 1200, max: 900)
        #expect(draft.problems == [.warmRentOrder] && draft.hint == "The lowest warm rent is above the highest.")
        draft.warmRent.max = nil                                          // one open end is always in order
        draft.coldRent = .init(min: 800, max: 700)
        #expect(draft.problems == [.coldRentOrder])
        draft.coldRent = .init(min: 700, max: 700)
        draft.flatSize = .init(min: 60, max: 40)
        draft.roomSize = .init(min: 20, max: 12)
        #expect(draft.problems == [.flatSizeOrder, .roomSizeOrder])
        draft.type = .flat                                                // the room's size no longer applies
        #expect(draft.problems == [.flatSizeOrder])
        draft.type = .wg
        #expect(draft.problems == [.roomSizeOrder] && draft.hint == "The room's smallest size is above its largest.")
    }

    @Test func moveInMustBeInOrder() throws {
        var draft = SearchDraft(try sampleSearch(), calendar: calendar)
        draft.moveInUntil = DateOnly.parse("2026-11-01", calendar: calendar)
        #expect(draft.problems == [.moveInOrder])
        draft.moveInUntil = nil
        #expect(draft.isValid && draft.search(calendar: calendar).moveInUntil == nil)
    }

    /// The type decides which fields are sent; the form keeps the others in case the type changes back.
    @Test func fieldsFollowTheType() throws {
        var draft = SearchDraft(try sampleSearch(), calendar: calendar)
        draft.roomsMin = 2
        draft.type = .wg
        var search = draft.search(calendar: calendar)
        #expect(search.kinds == [.wg] && search.roomSqmMin == 14 && search.flatmatesMax == 2)
        #expect(search.sqmMin == nil && search.roomsMin == nil)
        #expect(draft.asksWG && !draft.asksFlat)

        draft.type = .flat
        search = draft.search(calendar: calendar)
        #expect(search.kinds == [.flat] && search.sqmMin == 28 && search.roomsMin == 2)
        #expect(search.roomSqmMin == nil && search.flatmatesMax == nil)

        draft.type = .any
        search = draft.search(calendar: calendar)
        #expect(search.kinds == [.flat, .wg] && search.sqmMin == 28 && search.roomSqmMin == 14 && search.roomsMin == 2)
    }

    @Test func theTypeFromTheContractsKinds() {
        #expect(SearchDraft.OfferType([.flat]) == .flat && SearchDraft.OfferType([.wg]) == .wg)
        #expect(SearchDraft.OfferType([.wg, .flat]) == .any && SearchDraft.OfferType([]) == .any)
    }

    @Test func peopleAndPortalsGoOutAsTheContractWants() {
        var draft = SearchDraft()
        draft.add(munich)
        draft.people = 2
        draft.sources = [.immowelt, .wgGesucht]
        let search = draft.search(calendar: calendar)
        #expect(search.people == 2 && search.sources == [.wgGesucht, .immowelt])
    }

    @Test func peopleOutsideTheRangeAreClamped() throws {
        var search = try sampleSearch()
        search.people = 9
        #expect(SearchDraft(search, calendar: calendar).people == 6)
        search.people = 0
        #expect(SearchDraft(search, calendar: calendar).people == 1)
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
        draft.apply(PartialSearch(kinds: [.wg], people: 2, places: [garching, freising], districts: ["Schwabing", "Au"],
                                  roomSqmMax: 25, rentColdMax: 600, rentWarmMax: 700, moveInFrom: "2027-01-01",
                                  sublet: .include, extra: "möbliert"), calendar: calendar)
        let search = draft.search(calendar: calendar)
        #expect(search.kinds == [.wg] && search.people == 2 && search.sublet == .include && search.extra == "möbliert")
        #expect(search.rentWarmMin == 400 && search.rentWarmMax == 700 && search.rentColdMax == 600)
        #expect(search.roomSqmMin == 14 && search.roomSqmMax == 25)
        #expect(search.places.map(\.id) == ["wg:90", "wg:400", "wg:500"])
        #expect(search.districts == ["Schwabing", "Maxvorstadt", "Freimann", "Au"])
        #expect(search.moveInFrom == "2027-01-01" && search.moveInUntil == "2027-02-01")
        #expect(draft.flatSize.min == 28 && search.sqmMin == nil)       // kept in the form, not sent for a WG

        draft.apply(PartialSearch(kinds: [], people: 9, extra: "", sources: []), calendar: calendar)  // says nothing
        #expect(draft.search(calendar: calendar) == search)
    }
}
