import Foundation
import Testing
@testable import Arestemis

/// Brief 142: a listing's page reads like a listing. Every fact the search asks about is there, unknown ones without a
/// value (the page's "–", "not stated" to VoiceOver); the AI's warnings as notes to check, its reason off the page (it
/// stays on Filtered out); the description's preview line only when the server says the text is partial; Open on the
/// site as the main button, the application text as the quiet second one.
@MainActor
struct ListingPageTests {
    private let now = Clock.now
    private let calendar = Clock.berlin

    /// A listing from the contract's flat sample with some fields replaced (`NSNull()` clears one).
    private func listing(_ changes: [String: Any], from file: String = "match") throws -> Listing {
        let match = try sample(Match.self, file)
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(match.listing)) as! [String: Any]
        object.merge(changes) { _, new in new }
        return try JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func facts(_ listing: Listing, search: Search? = nil, language: AppLanguage = .english) -> [String: String?] {
        Dictionary(uniqueKeysWithValues: listing.detailFacts(search: search, now: now, calendar: calendar,
                                                             language: language).map { ($0.label, $0.value) })
    }

    // MARK: a flat's facts

    @Test func aFlatWithEveryFactKnown() throws {
        let flat = try sample(Match.self, "match").listing
        let shown = flat.detailFacts(now: now, calendar: calendar, language: .english)
        #expect(shown.allSatisfy { $0.isStated })
        #expect(shown.map(\.label) == ["Cold rent", "Size", "Rooms", "Move-in", "Furnished", "Location", "Kind", "Posted"])
        let german = flat.detailFacts(now: now, calendar: calendar, language: .german)
        #expect(german.map(\.label) == ["Kaltmiete", "Größe", "Zimmer", "Einzug", "Möbliert", "Lage", "Art", "Eingestellt"])
        #expect(german[0].value?.replacingOccurrences(of: "\u{a0}", with: " ") == "820 €")
    }

    @Test func aFlatWithUnknownsKeepsItsFactsAndReadsThemUnknown() throws {
        // The server's Immowelt listing: only the cold rent, so the big figure is cold and warm reads unknown.
        let immowelt = try sample(Match.self, "immowelt-match")
        #expect(immowelt.listing.shownRent()?.label == "cold")
        #expect(facts(immowelt.listing)["Warm rent"] == .some(nil))
        #expect(immowelt.listing.detailFacts(now: now, calendar: calendar, language: .english).first?.label == "Warm rent")

        // Nothing but the title and the rent: the facts every flat search asks about are still there, unknown.
        let bare = try listing(["sqm": NSNull(), "rooms": NSNull(), "available_from": NSNull(), "furnished": NSNull(),
                                "district": NSNull(), "address": NSNull(), "city": NSNull(), "posted": NSNull(),
                                "kind": NSNull(), "rent_cold": NSNull()])
        let shown = bare.detailFacts(now: now, calendar: calendar, language: .english)
        #expect(shown.map(\.label) == ["Cold rent", "Size", "Rooms", "Move-in", "Furnished", "Location"])
        #expect(shown.allSatisfy { !$0.isStated })
        // Kind and Posted only when known; Until only for a sublet.
        #expect(facts(bare)["Kind"] == nil && facts(bare)["Posted"] == nil && facts(bare)["Until"] == nil)

        // No rent at all: the big figure says so, and the facts have no rent of their own.
        let noRent = try listing(["rent_warm": NSNull(), "rent_cold": NSNull()])
        #expect(noRent.shownRent() == nil)
        #expect(!noRent.detailFacts(now: now, calendar: calendar).contains { $0.label.contains("rent") })
    }

    @Test func aWGRoomWithoutFlatmatesSaysItDoesNotKnow() throws {
        let room = try listing(["kind": "wg", "flatmates": NSNull(), "sqm": 16])
        let shown = facts(room)
        #expect(shown["Flatmates"] == .some(nil))
        #expect(shown["Room size"] == "16" && shown["Rooms"] == nil && shown["Kind"] == "WG room")
        let german = facts(room, language: .german)
        #expect(german["Mitbewohner"] == .some(nil) && german["Zimmergröße"] == "16")
    }

    @Test func untilShowsForASubletOrWhenTheSearchWantsOnlySublets() throws {
        let flat = try sample(Match.self, "match").listing
        var search = try #require(try sample(Overview.self, "overview").hunt?.search.flat)
        #expect(facts(flat, search: search)["Until"] == nil)          // sublets excluded: no end means none
        search.sublet = .only
        #expect(facts(flat, search: search)["Until"] == .some(nil))    // asked about, not given
        let sublet = try listing(["available_until": "2027-03-31"])
        #expect(facts(sublet)["Until"] == "31 Mar")
    }

    @Test func theLocationIsAsPreciseAsTheListingSays() throws {
        #expect(try listing([:]).location == "Hohenzollernstraße, Schwabing")
        #expect(try listing(["address": NSNull()]).location == "Schwabing")
        #expect(try listing(["address": NSNull(), "district": NSNull()]).location == "München")
        #expect(try listing(["address": " ", "district": NSNull(), "city": NSNull()]).location == nil)
    }

    @Test func anUnknownFactNeverReadsLikeAValue() {
        #expect(ListingFact.dash == "–")
        #expect(ListingFact.notStated(language: .english) == "not stated")
        #expect(ListingFact.notStated(language: .german) == "nicht angegeben")
        #expect(!ListingFact(label: "Rooms", value: nil).isStated && ListingFact(label: "Rooms", value: "2").isStated)
    }

    // MARK: a thing's facts

    @Test(arguments: [AppLanguage.english, .german])
    func aThingWithoutConditionSaysItDoesNotKnow(_ language: AppLanguage) throws {
        let de = language == .german
        var match = try sample(MatchPage.self, "item-matches").items[0]
        var item = try #require(match.listing.item)
        item.condition = nil
        item.seller = nil
        item.distanceKm = nil
        match = try replacing(item, in: match)
        let search = try #require(try sample(Overview.self, "overview").hunts[1].hunt.search.item)
        #expect(search.delivery == .either)
        let shown = match.listing.itemDetailFacts(search: search, now: now, calendar: calendar, language: language)
        let byLabel = Dictionary(uniqueKeysWithValues: shown.map { ($0.label, $0.value) })
        #expect(byLabel[de ? "Zustand" : "Condition"] == .some(nil))
        #expect(byLabel[de ? "Verkäufer" : "Seller"] == .some(nil))
        // The search includes pickup, so the distance is asked about.
        #expect(byLabel[de ? "Entfernung" : "Distance"] == .some(nil))
        #expect(byLabel[de ? "Übergabe" : "Delivery"] == (de ? "Nur Abholung" : "Pickup only"))
        // Without the search (or one that only ships), an unknown distance is left out; so it is for a listing that ships.
        let alone = match.listing.itemDetailFacts(now: now, calendar: calendar, language: language)
        #expect(!alone.contains { $0.label == (de ? "Entfernung" : "Distance") })
        item.shipping = .yes
        let parcel = try replacing(item, in: match).listing.itemDetailFacts(search: search, now: now, calendar: calendar,
                                                                           language: language)
        #expect(!parcel.contains { $0.label == (de ? "Entfernung" : "Distance") })
        // A thing whose details are missing altogether still shows what every thing search asks about.
        let none = try listing(["item": NSNull(), "rent_warm": NSNull(), "rent_cold": NSNull()])
        #expect(none.itemDetailFacts(now: now, calendar: calendar, language: language).map(\.label)
                == (de ? ["Zustand", "Übergabe", "Verkäufer", "Ort", "Eingestellt"]
                       : ["Condition", "Delivery", "Seller", "Place", "Posted"]))
    }

    private func replacing(_ item: ItemDetails, in match: Match) throws -> Match {
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as! [String: Any]
        var listing = object["listing"] as! [String: Any]
        listing["item"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item))
        object["listing"] = listing
        return try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object))
    }

    // MARK: what to check, and no "Why it fits"

    @Test func theWarningsAreNotesToCheckAndTheReasonIsOffThePage() throws {
        let saved = try sample(MatchPage.self, "matches").items[1]
        #expect(saved.checks == ["Floor not stated with certainty"])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as! [String: Any]
        object["warnings"] = ["  Rent may be cold rent ", "", "Rent may be cold rent", "Floor not stated"]
        let messy = try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(messy.checks == ["Rent may be cold rent", "Floor not stated"])

        // Nothing the page shows says why the listing fits: not the facts, the notes, the buttons or the preview line.
        let all = try sample(MatchPage.self, "matches").items + [try sample(Match.self, "immowelt-match")]
        for match in all {
            let words = match.listing.detailFacts(now: now, calendar: calendar).flatMap { [$0.label, $0.value ?? ""] }
                + match.checks + ListingButton.buttons(for: .flat, site: match.listing.sourceName).map { $0.title() }
                + [match.listing.previewLine() ?? ""]
            #expect(!words.contains(match.reason), "\(match.id)")
        }
        // The tour no longer points at it: its listing step names the facts and what to check.
        #expect(!TourStep.listing.text(.english).contains("Why it fits"))
        #expect(!TourStep.listing.text(.german).contains("Warum es passt"))
        #expect(AppLanguage.german.string("To check") == "Zu prüfen")
        // Filtered out keeps its reason: why the listing was turned down.
        let rejected = try sample(RejectedPage.self, "rejected").items
        #expect(rejected.allSatisfy { !$0.reason.isEmpty })
    }

    // MARK: the description

    @Test(arguments: [AppLanguage.english, .german])
    func onlyAPartialDescriptionHasThePreviewLine(_ language: AppLanguage) throws {
        let partial = try sample(Match.self, "immowelt-match").listing
        #expect(partial.descriptionPartial && partial.sourceName == "Immowelt")
        #expect(partial.previewLine(language: language) == (language == .german
            ? "Nur ein Auszug. Den ganzen Text zeigt Immowelt."
            : "Only a preview. The whole text is on Immowelt."))
        // The whole text: no line. Nothing to call a preview: no line either.
        #expect(try sample(Match.self, "match").listing.previewLine(language: language) == nil)
        #expect(try listing(["description_partial": true, "description": "  "]).previewLine(language: language) == nil)
        // The site by the server's name.
        let other = try listing(["description_partial": true, "source_name": "Kleinanzeigen"])
        #expect(other.previewLine(language: language)?.contains("Kleinanzeigen") == true)
    }

    @Test func descriptionPartialIsReadLeniently() throws {
        let match = try sample(Match.self, "match")
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(match.listing)) as! [String: Any]
        #expect(object["description_partial"] as? Bool == false)            // always sent back
        func decoded(_ value: Any?) throws -> Bool {
            var changed = object
            changed["description_partial"] = value
            if value == nil { changed.removeValue(forKey: "description_partial") }
            return try JSONDecoder().decode(Listing.self, from: JSONSerialization.data(withJSONObject: changed))
                .descriptionPartial
        }
        #expect(try decoded(nil) == false)                  // a server from before brief 141
        #expect(try decoded(NSNull()) == false)
        #expect(try decoded("yes") == false)                // not a boolean: the whole text, the listing still reads
        #expect(try decoded(true) == true)
        // The server's own samples carry it on every listing, an Immowelt one true.
        let server = try JSONDecoder().decode(MatchPage.self, from: serverSample("matches"))
        #expect(server.items.contains { $0.listing.source == .immowelt && $0.listing.descriptionPartial })
        #expect(server.items.filter { $0.listing.source != .immowelt }.allSatisfy { !$0.listing.descriptionPartial })
    }

    private final class Token {}
    private func serverSample(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    // MARK: the buttons

    @Test(arguments: [AppLanguage.english, .german])
    func openOnTheSiteIsTheMainButton(_ language: AppLanguage) {
        let de = language == .german
        let flat = ListingButton.buttons(for: .flat, site: "ImmoScout24")
        #expect(flat == [.openOnSite("ImmoScout24"), .applicationText])
        #expect(flat.map { $0.title(language: language) }
                == (de ? ["Bei ImmoScout24 öffnen", "Bewerbungstext"] : ["Open on ImmoScout24", "Application text"]))
        #expect(flat.map(\.isMain) == [true, false])
        #expect(flat.map(\.symbol) == [nil, "doc.text"])
        // A thing has no application: Open stays its one main button. A watch's change and an alarm open their page.
        #expect(ListingButton.buttons(for: .item, site: "eBay") == [.openOnSite("eBay")])
        #expect(ListingButton.buttons(for: .watch, site: "x") == [.openPage])
        #expect(ListingButton.buttons(for: .price, site: "x") == [.openInShop])
        #expect(ListingButton.openPage.title(language: language) == (de ? "Seite öffnen" : "Open page"))
        #expect(ListingButton.openInShop.title(language: language) == (de ? "Im Shop öffnen" : "Open in shop"))
        #expect(SearchKind.all.allSatisfy { ListingButton.buttons(for: $0, site: "x").first?.isMain == true })
    }
}
