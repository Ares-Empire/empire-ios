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
        default: Issue.record("No model for \(file)")
        }
    }

    private func roundTrip<T: Codable & Equatable>(_ type: T.Type, _ file: String) throws {
        let decoded = try sample(type, file)
        #expect(try JSONDecoder().decode(type, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test func overviewSample() throws {
        let overview = try sample(Overview.self, "overview")
        #expect(overview.version == 1 && overview.me.name == "Patrik")
        let hunt = try #require(overview.hunt)
        #expect(hunt.id == 1 && hunt.kind == "flat" && hunt.active)
        #expect(hunt.search.kinds == [.flat, .wgEmpty])
        #expect(hunt.search.places.map(\.id) == ["wg:90", "wg:400"])
        #expect(hunt.search.places[1].sources == [.wgGesucht, .kleinanzeigen])
        #expect(hunt.search.rentTiers == [RentTier(sqmMin: 40, rentMaxWarm: 1200)])
        #expect(hunt.search.rentMaxWarm == 1000 && hunt.search.sqmMin == 28 && hunt.search.roomsMin == 1)
        #expect(hunt.search.roomSqmMin == nil)
        #expect(hunt.search.flatmatesMax == 1 && hunt.search.sublet == .exclude && hunt.search.furnished == .any)
        #expect(hunt.search.moveInFrom == "2026-12-01" && hunt.search.moveInUntil == "2027-02-01")
        #expect(overview.sources.map(\.state) == [.ok, .ok, .ok])
        #expect(overview.sources.last?.note == "Only München")
        #expect(overview.counts == .init(new: 1, today: 2, saved: 1, applied: 1))
        #expect(overview.latest.map(\.id) == [41, 40, 38])
        #expect(overview.lastScan == "2026-10-24T10:02:00Z")
    }

    @Test func matchSamples() throws {
        let match = try sample(Match.self, "match")
        #expect(match.state == .new && match.huntID == 1 && match.application == nil && match.warnings.isEmpty)
        #expect(match.listing.source == .wgGesucht && match.listing.sourceName == "WG-Gesucht")
        #expect(match.listing.rentWarm == 980 && match.listing.rentCold == 820 && match.listing.sqm == 42)
        #expect(match.listing.kind == .flat && match.listing.furnished == false && match.listing.imageURL == nil)
        #expect(match.listing.availableFrom == "2026-12-01" && match.listing.availableUntil == nil)

        let page = try sample(MatchPage.self, "matches")
        #expect(!page.more && page.items.map(\.state) == [.new, .saved, .applied])
        #expect(page.items[1].application?.mode == .ai && page.items[1].warnings == ["Floor not stated with certainty"])
        #expect(page.items[2].listing.kind == .wgEmpty && page.items[2].listing.flatmates == 1)
    }

    @Test func otherSamples() throws {
        let rejected = try sample(RejectedPage.self, "rejected").items
        #expect(rejected.map(\.id) == [12, 11])
        #expect(rejected[0].listing.availableUntil == "2027-03-31" && rejected[0].reason == "Sublet: limited until 31 Mar 2027.")
        let settings = try sample(Settings.self, "settings")
        #expect(settings.applicationMode == .ai && settings.notify == .init(push: true, timeSensitive: true))
        #expect(settings.ownText.hasPrefix("Hallo,"))
        let places = try sample([Place].self, "places")
        #expect(places.map(\.name) == ["Garching bei München", "Garching an der Alz"])
    }

    /// The app sends every search field, unknown ones as null, under the contract's names.
    @Test func searchEncodesEveryFieldWithNulls() throws {
        var search = try #require(try sample(Overview.self, "overview").hunt?.search)
        search.rentMaxWarm = nil
        search.moveInUntil = nil
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(search)) as? [String: Any])
        #expect(Set(json.keys) == ["kinds", "places", "districts", "rent_max_warm", "rent_tiers", "sqm_min", "room_sqm_min",
                                   "rooms_min", "flatmates_max", "move_in_from", "move_in_until", "sublet", "furnished",
                                   "extra", "sources"])
        #expect(json["rent_max_warm"] is NSNull && json["move_in_until"] is NSNull && json["room_sqm_min"] is NSNull)
        #expect(json["kinds"] as? [String] == ["flat", "wg_empty"])
        #expect((json["rent_tiers"] as? [[String: Any]])?.first?["sqm_min"] as? Double == 40)
        let place = try #require((json["places"] as? [[String: Any]])?.first)
        #expect(Set(place.keys) == ["id", "name", "region", "sources"])
    }

    @Test func settingsEncodeTheContractsNames() throws {
        let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample(Settings.self, "settings")))
            as? [String: Any])
        #expect(Set(json.keys) == ["application_mode", "own_text", "about_me", "notify"])
        let notify = try #require(json["notify"] as? [String: Any])
        #expect(Set(notify.keys) == ["push", "time_sensitive"])
    }

    /// `Partial<Search>`: only what the sentence said; a null counts as not said.
    @Test func parseResultIsPartial() throws {
        let parsed = try JSONDecoder().decode(ParsedSearch.self, from: Data("""
            {"search": {"kinds": ["wg_room"], "rent_max_warm": 650, "move_in_from": "2026-12-01", "sqm_min": null,
                        "room_sqm_min": 15},
             "unclear": ["Which city?"]}
            """.utf8))
        #expect(parsed.search.kinds == [.wgRoom] && parsed.search.rentMaxWarm == 650 && parsed.search.roomSqmMin == 15)
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
