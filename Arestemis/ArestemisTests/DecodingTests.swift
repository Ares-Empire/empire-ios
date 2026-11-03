import Foundation
import Testing
@testable import Arestemis

/// Every sample answer of the contract (Samples/ = Arestemis/docs/samples/) decodes into the app's models.
@MainActor
struct DecodingTests {
    @Test(arguments: ArestemisSamples.files)
    func everySampleDecodesAndRoundTrips(file: String) throws {
        switch file {
        case "overview": try roundTrip(Overview.self, file)
        case "matches": try roundTrip(MatchPage.self, file)
        case "match": try roundTrip(Match.self, file)
        case "rejected": try roundTrip(RejectedPage.self, file)
        case "settings": try roundTrip(Settings.self, file)
        case "places": try roundTrip([Place].self, file)
        case "hunts": try roundTrip([Hunt].self, file)
        case "item-matches", "watch-matches", "price-matches": try roundTrip(MatchPage.self, file)
        case "prices-9", "prices-10": try roundTrip(Prices.self, file)
        case "ebay-match", "ikea-match", "vinted-match", "immowelt-match": try roundTrip(Match.self, file)
        case "kinds": try roundTrip([OfferedKind].self, file)
        default: Issue.record("No model for \(file)")
        }
    }

    private func roundTrip<T: Codable & Equatable>(_ type: T.Type, _ file: String) throws {
        let decoded = try sample(type, file)
        #expect(try JSONDecoder().decode(type, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test func overviewSample() throws {
        let overview = try sample(Overview.self, "overview")
        #expect(overview.version == 2 && overview.me.name == "Patrik")
        let hunt = try #require(overview.hunt)
        #expect(hunt.id == 1 && hunt.kind == .flat && hunt.active)
        #expect(hunt.search.flat!.kinds == [.flat, .wg] && hunt.search.flat!.people == 1)
        #expect(hunt.search.flat!.places.map(\.id) == ["wg:90", "wg:400"])
        #expect(hunt.search.flat!.places[1].sources == [.wgGesucht, .kleinanzeigen, .immowelt, .immoscout24])
        #expect(hunt.search.flat!.rentWarmMin == 400 && hunt.search.flat!.rentWarmMax == 1000 && hunt.search.flat!.rentColdMax == nil)
        #expect(hunt.search.flat!.sqmMin == 28 && hunt.search.flat!.sqmMax == nil && hunt.search.flat!.roomsMin == nil)
        #expect(hunt.search.flat!.roomSqmMin == 14 && hunt.search.flat!.roomSqmMax == nil)
        #expect(hunt.search.flat!.flatmatesMax == 2 && hunt.search.flat!.sublet == .exclude)
        #expect(hunt.search.flat!.moveInFrom == "2026-12-01" && hunt.search.flat!.moveInUntil == "2027-02-01")
        #expect(overview.sources.map(\.source.rawValue) == ["wg_gesucht", "kleinanzeigen", "immowelt", "immoscout24", "ebay",
                                                             "mydealz", "bikemarkt", "ikea_preowned", "vinted"])
        #expect(overview.sources.allSatisfy { $0.state == .ok })
        #expect(overview.sources.allSatisfy { $0.note == nil })
        #expect(overview.counts == .init(new: 7, today: 8, saved: 1, applied: 1))
        #expect(overview.latest.map(\.id) == [41, 40, 38])
        #expect(overview.lastScan == "2026-10-24T10:02:00Z")
    }

    @Test func matchSamples() throws {
        let match = try sample(Match.self, "match")
        #expect(match.state == .new && match.huntID == 1 && match.application == nil && match.warnings.isEmpty)
        #expect(match.listing.source == .immoscout24 && match.listing.sourceName == "ImmoScout24")
        #expect(match.listing.rentWarm == 980 && match.listing.rentCold == 820 && match.listing.sqm == 42)
        #expect(match.listing.kind == .flat && match.listing.furnished == false && match.listing.imageURL == nil)
        #expect(match.listing.availableFrom == "2026-12-01" && match.listing.availableUntil == nil)

        let page = try sample(MatchPage.self, "matches")
        #expect(!page.more && page.items.map(\.state) == [.new, .saved, .applied])
        #expect(page.items[1].application?.mode == .ai && page.items[1].warnings == ["Floor not stated with certainty"])
        #expect(page.items[2].listing.kind == .wg && page.items[2].listing.flatmates == 1)
    }

    @Test func otherSamples() throws {
        let rejected = try sample(RejectedPage.self, "rejected").items
        #expect(rejected.map(\.id) == [12, 11])
        #expect(rejected[0].listing.availableUntil == "2027-03-31" && rejected[0].reason == "Sublet: limited until 31 Mar 2027.")
        let settings = try sample(Settings.self, "settings")
        #expect(settings.applicationMode == .ai && settings.notify == .init(push: true, timeSensitive: true))
        #expect(settings.ownText.hasPrefix("Hallo,") && settings.applicationNotes.hasPrefix("Ich kann jeden Abend"))
        let places = try sample([Place].self, "places")
        #expect(places.map(\.name) == ["Garching bei München", "Garching an der Alz"])
    }

    /// The app sends every search field, unknown ones as null, under the contract's names.
    @Test func searchEncodesEveryFieldWithNulls() throws {
        var search = try #require(try sample(Overview.self, "overview").hunt?.search.flat)
        search.rentWarmMax = nil
        search.moveInUntil = nil
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(search)) as? [String: Any])
        #expect(Set(json.keys) == ["kinds", "people", "flatmates_max", "places", "districts", "sqm_min", "sqm_max",
                                   "room_sqm_min", "room_sqm_max", "rooms_min", "rent_cold_min", "rent_cold_max",
                                   "rent_warm_min", "rent_warm_max", "move_in_from", "move_in_until", "sublet", "extra",
                                   "sources"])
        #expect(json["rent_warm_max"] is NSNull && json["move_in_until"] is NSNull && json["sqm_max"] is NSNull)
        #expect(json["kinds"] as? [String] == ["flat", "wg"] && json["people"] as? Int == 1)
        #expect(json["rent_warm_min"] as? Double == 400)
        let place = try #require((json["places"] as? [[String: Any]])?.first)
        #expect(Set(place.keys) == ["id", "name", "region", "sources"])
    }

    @Test func settingsEncodeTheContractsNames() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample(Settings.self, "settings")))
            as? [String: Any])
        #expect(Set(json.keys) == ["application_mode", "own_text", "application_notes", "about_me", "notify"])
        let notify = try #require(json["notify"] as? [String: Any])
        #expect(Set(notify.keys) == ["push", "time_sensitive"])
    }

    /// A server from before brief 62 sends no `application_notes`: none, and they are sent from then on.
    @Test func settingsWithoutNotesDecode() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data("""
            {"application_mode": "own", "own_text": "Hallo", "about_me": "Made-up facts",
             "notify": {"push": true, "time_sensitive": false}}
            """.utf8))
        #expect(settings.applicationMode == .own && settings.ownText == "Hallo" && settings.aboutMe == "Made-up facts")
        #expect(settings.applicationNotes == "")
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        #expect(json["application_notes"] as? String == "")
    }

    // MARK: sites the app does not know yet (brief 61; kept since brief 119)

    @Test func immoScout24IsKnown() throws {
        let place = try JSONDecoder().decode(Place.self, from: Data("""
            {"id": "wg:90", "name": "München", "region": "Bayern", "sources": ["wg_gesucht", "immoscout24"]}
            """.utf8))
        #expect(place.sources == [.wgGesucht, .immoscout24] && SiteNames().name(.immoscout24) == "ImmoScout24")
    }

    @Test func placesKeepUnknownSites() throws {
        let places = try JSONDecoder().decode([Place].self, from: Data("""
            [{"id": "wg:90", "name": "München", "region": null, "sources": ["wg_gesucht", "newportal", "immowelt"]},
             {"id": "wg:91", "name": "Nowhere", "region": null, "sources": ["newportal"]}]
            """.utf8))
        #expect(places.map(\.sources) == [[.wgGesucht, Source("newportal"), .immowelt], [Source("newportal")]])
    }

    /// The hunt's search (in the overview), its sites and its places' sites; the overview's site states, which name
    /// the new site for every list.
    @Test func theOverviewKeepsUnknownSites() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("overview")) as? [String: Any])
        var hunt = try #require(object["hunt"] as? [String: Any])
        var search = try #require(hunt["search"] as? [String: Any])
        search["sources"] = ["newportal", "kleinanzeigen"]
        var places = try #require(search["places"] as? [[String: Any]])
        places[0]["sources"] = ["wg_gesucht", "newportal"]
        search["places"] = places
        hunt["search"] = search
        object["hunt"] = hunt
        var sources = try #require(object["sources"] as? [[String: Any]])
        sources.append(["source": "newportal", "name": "New Portal", "state": "ok", "checked": NSNull(), "note": NSNull()])
        object["sources"] = sources
        let overview = try JSONDecoder().decode(Overview.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(overview.hunt?.search.flat?.sources == [Source("newportal"), .kleinanzeigen])
        #expect(overview.hunt?.search.flat?.places.first?.sources == [.wgGesucht, Source("newportal")])
        #expect(overview.sources.map(\.source.rawValue) == ["wg_gesucht", "kleinanzeigen", "immowelt", "immoscout24", "ebay",
                                                             "mydealz", "bikemarkt", "ikea_preowned", "vinted", "newportal"])
        #expect(SiteNames(statuses: overview.sources).name(Source("newportal")) == "New Portal")
    }

    /// Only the site's id is open: a state the app does not know still fails, as before.
    @Test func aBrokenSiteStateStillFails() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("overview")) as? [String: Any])
        var sources = try #require(object["sources"] as? [[String: Any]])
        sources[0]["state"] = "melting"
        object["sources"] = sources
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(Overview.self, from: JSONSerialization.data(withJSONObject: object))
        }
    }

    @Test func describeItKeepsUnknownSites() throws {
        let parsed = try JSONDecoder().decode(ParsedSearch.self, from: Data("""
            {"search": {"sources": ["newportal", "immoscout24"]}, "unclear": []}
            """.utf8))
        #expect(parsed.search.sources == [Source("newportal"), .immoscout24])
        let none = try JSONDecoder().decode(ParsedSearch.self, from: Data(#"{"search": {}, "unclear": []}"#.utf8))
        #expect(none.search.sources == nil)
    }

    /// A listing from a site the app does not know shows, named by the server.
    @Test func aListingFromAnUnknownSiteDecodes() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("match")) as? [String: Any])
        var listing = try #require(object["listing"] as? [String: Any])
        listing["source"] = "newportal"
        listing["source_name"] = "New Portal"
        object["listing"] = listing
        let match = try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(match.listing.source == Source("newportal") && match.listing.sourceName == "New Portal")
        #expect(match.sourceLine(now: .now).hasPrefix("New Portal"))
    }

    /// A site the app does not know is sent back as it came, so saving a search keeps it.
    @Test func anUnknownSiteRoundTrips() throws {
        let place = Place(id: "wg:90", name: "München", region: nil, sources: [Source("newportal")])
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(place)) as? [String: Any])
        #expect(json["sources"] as? [String] == ["newportal"])
    }

    /// `Partial<Search>`: only what the sentence said; a null counts as not said.
    @Test func parseResultIsPartial() throws {
        let parsed = try JSONDecoder().decode(ParsedSearch.self, from: Data("""
            {"search": {"kinds": ["wg"], "people": 2, "rent_warm_max": 650, "move_in_from": "2026-12-01",
                        "sqm_min": null, "room_sqm_min": 15},
             "unclear": ["Which city?"]}
            """.utf8))
        #expect(parsed.search.kinds == [.wg] && parsed.search.people == 2 && parsed.search.rentWarmMax == 650)
        #expect(parsed.search.roomSqmMin == 15 && parsed.search.rentColdMax == nil)
        #expect(parsed.search.moveInFrom == "2026-12-01" && parsed.search.sqmMin == nil && parsed.search.places == nil)
        #expect(parsed.unclear == ["Which city?"])
    }

    @Test func timestampsWithAndWithoutFractions() {
        #expect(Timestamp.parse("2026-10-24T09:59:10Z") != nil)
        #expect(Timestamp.parse("2026-10-24T09:59:10.123456Z") != nil)
        #expect(Timestamp.parse("2026-10-24T11:59:10+02:00") == Timestamp.parse("2026-10-24T09:59:10Z"))
        #expect(Timestamp.parse("2026-10-24") == nil && Timestamp.parse("yesterday") == nil)
    }

    /// The sample mode moves the sample's times so they stay fresh; dates without a time stay.
    @Test func sampleShiftMovesOnlyTimestamps() throws {
        let shifted = try ArestemisSamples.shifted(ArestemisSamples.data("match"), by: 3600)
        let match = try JSONDecoder().decode(Match.self, from: shifted)
        #expect(match.found == "2026-10-24T10:59:10Z")
        #expect(match.listing.posted == "2026-10-24T10:58:00Z")
        #expect(match.listing.availableFrom == "2026-12-01")
    }
}
