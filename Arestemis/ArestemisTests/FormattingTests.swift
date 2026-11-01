import Foundation
import Testing
@testable import Arestemis

/// Money, sizes, times and the two-line search summary, with a fixed clock (Sat 24 Oct 2026, 12:02:40 in Berlin).
@MainActor
struct FormattingTests {
    private let now = Clock.now
    private let calendar = Clock.berlin

    @Test func money() {
        #expect(Format.money(980) == "€980")
        #expect(Format.money(1150) == "€1,150")
        #expect(Format.money(1000) == "€1,000")
        #expect(Format.money(999.6) == "€1,000")
        #expect(Format.money(12_500) == "€12,500")
        #expect(Format.money(0) == "€0")
    }

    @Test func sizesAndRooms() {
        #expect(Format.size(42) == "42 m²")
        #expect(Format.size(42.5) == "42.5 m²")
        #expect(Format.rooms(1) == "1 room")
        #expect(Format.rooms(2) == "2 rooms")
        #expect(Format.rooms(1.5) == "1.5 rooms")
        #expect(Format.flatmates(1) == "1 flatmate" && Format.flatmates(3) == "3 flatmates")
    }

    @Test(arguments: [
        ("2026-10-24T10:02:36Z", "just now"),
        ("2026-10-24T10:03:40Z", "just now"),            // a clock a little ahead
        ("2026-10-24T10:02:00Z", "40 s ago"),
        ("2026-10-24T09:58:40Z", "4 min ago"),
        ("2026-10-24T07:02:00Z", "3 h ago"),
        ("2026-10-23T16:05:00Z", "yesterday 18:05"),
        ("2026-10-21T16:05:00Z", "Wed 18:05"),
        ("2026-10-04T08:00:00Z", "4 Oct"),
        ("2025-10-04T08:00:00Z", "4 Oct 2025"),
    ])
    func relativeTimes(timestamp: String, expected: String) {
        #expect(Format.relative(timestamp, now: now, calendar: calendar) == expected)
    }

    @Test func relativeTimeOfNothing() {
        #expect(Format.relative(nil as String?, now: now, calendar: calendar) == nil)
        #expect(Format.relative("not a time", now: now, calendar: calendar) == nil)
    }

    @Test func days() {
        #expect(Format.day("2026-12-01", now: now, calendar: calendar) == "1 Dec")
        #expect(Format.day("2027-02-01", now: now, calendar: calendar) == "1 Feb")
        #expect(Format.day("2027-12-01", now: now, calendar: calendar) == "1 Dec 2027")
        #expect(Format.day("2026-13-01", now: now, calendar: calendar) == nil)
        #expect(Format.day("2026-02-30", now: now, calendar: calendar) == nil)
        #expect(Format.day("1 Dec", now: now, calendar: calendar) == nil)
    }

    @Test func dateOnlyRoundTrips() throws {
        let date = try #require(DateOnly.parse("2026-12-01", calendar: calendar))
        #expect(DateOnly.string(date, calendar: calendar) == "2026-12-01")
        #expect(calendar.component(.hour, from: date) == 0)
    }

    // MARK: the search summary

    private func search(kinds: [Kind] = [.flat], people: Int = 1, places: [String] = ["München"], warm: Double? = nil,
                        warmMin: Double? = nil, cold: Double? = nil, from: String? = nil, until: String? = nil) -> Search {
        Search(kinds: kinds, people: people, flatmatesMax: nil,
               places: places.enumerated().map { Place(id: "p\($0.offset)", name: $0.element, region: nil, sources: [.wgGesucht]) },
               districts: [], sqmMin: nil, sqmMax: nil, roomSqmMin: nil, roomSqmMax: nil, roomsMin: nil,
               rentColdMin: nil, rentColdMax: cold, rentWarmMin: warmMin, rentWarmMax: warm,
               moveInFrom: from, moveInUntil: until, sublet: .exclude, extra: "", sources: [.wgGesucht])
    }

    @Test func summaryOfTheSampleSearch() throws {
        let hunt = try #require(try sample(Overview.self, "overview").hunt)
        let summary = SearchSummary(hunt.search.flat!, now: now, calendar: calendar)
        #expect(summary.kinds == "Flat or WG room")
        #expect(summary.details == "München, Garching · €400–1,000 warm · 1 Dec – 1 Feb")
        #expect(summary.parts.count == 3)
        // On screen a part never breaks across lines, nor a kind.
        #expect(!summary.wrappingDetails.replacingOccurrences(of: " · ", with: "").contains(" "))
        #expect(summary.wrappingKinds.components(separatedBy: " ").count == 3)       // "Flat" | "or" | "WG room"
    }

    @Test func summaryOfOtherSearches() {
        let garching = SearchSummary(search(kinds: [.wg], places: ["Garching bei München"], from: "2026-12-01"),
                                     now: now, calendar: calendar)
        #expect(garching.kinds == "WG room")
        #expect(garching.details == "Garching · from 1 Dec")

        let both = SearchSummary(search(kinds: [.wg, .flat], people: 2, warm: 1150, until: "2027-02-01"),
                                 now: now, calendar: calendar)
        #expect(both.kinds == "Flat or WG room")                                // always in the contract's order
        #expect(both.details == "München · 2 people · up to €1,150 warm · until 1 Feb")

        // The warm rent stands for the rent when both are set; the cold one shows when it is the only one.
        #expect(SearchSummary(search(warmMin: 500, cold: 700), now: now, calendar: calendar).details
                == "München · from €500 warm")
        #expect(SearchSummary(search(cold: 700), now: now, calendar: calendar).details == "München · up to €700 cold")

        let twins = SearchSummary(search(places: ["Garching bei München", "Garching an der Alz"]), now: now, calendar: calendar)
        #expect(twins.details == "Garching bei München, Garching an der Alz")

        let many = SearchSummary(search(places: ["München", "Freising", "Dachau", "Erding", "Augsburg"]), now: now,
                                 calendar: calendar)
        #expect(many.details == "München, Freising, Dachau +2")

        #expect(SearchSummary(search(places: []), now: now, calendar: calendar).parts.isEmpty)
    }

    @Test func placeShortNames() {
        let names = ["Garching bei München": "Garching", "Frankfurt am Main": "Frankfurt", "Halle (Saale)": "Halle",
                     "Weil im Schönbuch": "Weil", "München": "München", "Neumarkt in der Oberpfalz": "Neumarkt"]
        for (name, short) in names {
            #expect(Place(id: name, name: name, region: nil, sources: []).shortName == short)
        }
    }

    // MARK: a listing's lines

    @Test func listingLines() throws {
        let page = try sample(MatchPage.self, "matches")
        #expect(page.items[0].listing.facts == "42 m² · 2 rooms · Schwabing")
        #expect(page.items[2].listing.facts == "19 m² · WG room · Hochbrück")
        #expect(page.items[0].listing.shownRent?.amount == "€980" && page.items[0].listing.shownRent?.label == "warm")
        #expect(page.items[1].listing.shownRent?.amount == "€1,150")
        #expect(page.items[0].sourceLine(now: now, calendar: calendar) == "ImmoScout24 · 3 min ago")
        let rejected = try sample(RejectedPage.self, "rejected").items[0].listing
        #expect(rejected.factsWithRent == "€950 warm · 30 m² · 1 room · Maxvorstadt")
    }

    @Test func detailFacts() throws {
        let page = try sample(MatchPage.self, "matches")
        let flat = page.items[0].listing.detailFacts(now: now, calendar: calendar)
        #expect(flat.map(\.label) == ["Size", "Rooms", "Kind", "Move-in", "Furnished", "District", "Posted"])
        #expect(flat.map(\.value) == ["42", "2", "Flat", "1 Dec", "No", "Schwabing", "4 min ago"])
        #expect(flat[0].unit == "m²" && flat[0].numeric && !flat[2].numeric)
        let wg = page.items[2].listing.detailFacts(now: now, calendar: calendar)
        #expect(wg.map(\.label) == ["Size", "Flatmates", "Kind", "Move-in", "Furnished", "District", "Posted"])
        let sublet = try sample(RejectedPage.self, "rejected").items[0].listing.detailFacts(now: now, calendar: calendar)
        #expect(sublet.first { $0.label == "Until" }?.value == "31 Mar")
    }

    @Test func portalLinksAreOnlyWebAddresses() throws {
        let listing = try sample(Match.self, "match").listing
        #expect(listing.portalURL?.host() == "www.immobilienscout24.de")
        for url in ["javascript:alert(1)", "arestemis://match/1", "file:///etc/hosts", "not a url", "https://"] {
            let other = try JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: [
                "source": "wg_gesucht", "source_name": "WG-Gesucht", "url": url, "title": "T", "description": ""]))
            #expect(other.portalURL == nil, "\(url)")
        }
    }
}

// MARK: - German (ares-empire/docs/LANGUAGES.md): words from the String Catalog, numbers and dates in de_DE

extension FormattingTests {
    @Test func germanMoneySizesAndRooms() {
        let de = AppLanguage.german
        #expect(Format.money(1150, language: de) == "1.150\u{a0}€")
        #expect(Format.moneyRange(400, 1000, language: de) == "400–1.000\u{a0}€")
        #expect(Format.size(42.5, language: de) == "42,5 m²")
        #expect(Format.rooms(1, language: de) == "1 Zimmer" && Format.rooms(2.5, language: de) == "2,5 Zimmer")
        #expect(Format.flatmates(1, language: de) == "1 Mitbewohner")
    }

    @Test(arguments: [
        ("2026-10-24T10:02:36Z", "gerade eben"),
        ("2026-10-24T09:58:40Z", "vor 4 Min."),
        ("2026-10-24T07:02:00Z", "vor 3 Std."),
        ("2026-10-23T16:05:00Z", "gestern 18:05"),
        ("2026-10-21T16:05:00Z", "Mi 18:05"),
        ("2026-10-04T08:00:00Z", "4. Okt."),
        ("2025-10-04T08:00:00Z", "4. Okt. 2025"),
    ])
    func germanRelativeTimes(timestamp: String, expected: String) {
        #expect(Format.relative(timestamp, now: now, calendar: calendar, language: .german) == expected)
    }

    @Test func germanSummary() throws {
        let hunt = try #require(try sample(Overview.self, "overview").hunt)
        let summary = SearchSummary(hunt.search.flat!, now: now, calendar: calendar, language: .german)
        #expect(summary.kinds == "Wohnung oder WG-Zimmer")
        #expect(summary.details == "München, Garching · 400–1.000\u{a0}€ warm · 1. Dez. – 1. Feb.")
        let both = SearchSummary(search(kinds: [.wg, .flat], people: 2, warm: 1150, until: "2027-02-01"),
                                 now: now, calendar: calendar, language: .german)
        #expect(both.details == "München · 2 Personen · bis 1.150\u{a0}€ warm · bis 1. Feb.")
        #expect(SearchSummary(search(cold: 700), now: now, calendar: calendar, language: .german).details
                == "München · bis 700\u{a0}€ kalt")
    }
}
