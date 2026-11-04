import Foundation
import Testing
@testable import Arestemis

/// The Arestemis server's own sample answers (copies of `~/Arestemis/docs/samples/`, made by its contract tests) decode
/// with the app's models. The app's `Samples/` are hand-made for sample mode; these pin the real contract. Copy them
/// again when the server's contract changes.
@MainActor
struct ServerSamplesTests {
    private final class Token {}

    private func data(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    @Test func overviewWithEveryHunt() throws {
        let overview = try JSONDecoder().decode(Overview.self, from: data("overview"))
        #expect(!overview.hunts.isEmpty)
        #expect(overview.hunts.contains { $0.hunt.kind == .item })
        #expect(overview.hunts.allSatisfy { card in
            if case .unsupported = card.hunt.search { return false }
            return true
        })
    }

    @Test func huntsOfBothKinds() throws {
        let hunts = try JSONDecoder().decode([Hunt].self, from: data("hunts"))
        #expect(Set(hunts.map(\.kind)) == [.flat, .item])
    }

    /// Brief 148: a thing search with several search words; the overview's one without them reads as none.
    @Test func aThingSearchWithSeveralWords() throws {
        let hunts = try JSONDecoder().decode([Hunt].self, from: data("hunts"))
        let chairs = try #require(hunts.first { $0.kind == .item })
        #expect(chairs.search.item?.words == ["Herman Miller Aeron", "Steelcase Leap", "Steelcase Gesture"])
        #expect(HuntText.automaticTitle(chairs.search, language: .german) == "Herman Miller Aeron + 2")
        #expect(HuntText(chairs).title == chairs.name)
        let overview = try JSONDecoder().decode(Overview.self, from: data("overview"))
        #expect(overview.hunts.compactMap(\.hunt.search.item).allSatisfy { $0.moreQueries.isEmpty })
    }

    @Test func matchesWithThingDetails() throws {
        let page = try JSONDecoder().decode(MatchPage.self, from: data("matches"))
        let things = page.items.filter { $0.listing.item != nil }
        #expect(!things.isEmpty)
        #expect(things.contains { $0.atStart })
    }

    /// Brief 167: used matches keep normal Item details and the public monitor as parent, beside new-goods prices.
    @Test func everywhereWithUsedMatchesKeepsTheServerContract() throws {
        let card = try JSONDecoder().decode(HuntCard.self, from: data("price-everywhere-used"))
        let search = try #require(card.hunt.search.price)
        #expect(search.mode == .everywhere && search.includeUsed && search.sourcesOff == ["mydealz"])
        #expect(search.delivery == .shipping && search.radiusKm == 20 && search.places.isEmpty)
        let draft = PriceSearchDraft(search, name: card.hunt.name)
        #expect(draft.search() == search && draft.isConfirmed)
        let page = try JSONDecoder().decode(MatchPage.self, from: data("price-used"))
        let match = try #require(page.items.only)
        #expect(match.huntID == card.id && match.isThing && !match.isPriceChange)
        #expect(match.listing.item?.priceKind == .auction && match.listing.item?.price == 62)
        #expect(match.listing.item?.bids == 3 && match.listing.item?.shippingCost == 4.99)
        #expect(card.price?.price == 215 && search.alarm?.below == 220)
    }

    /// `GET /kinds`: the three kinds with their sites in the server's order; eBay offered for things, not set up (no
    /// keys in the sample), with auctions; mydealz and Vinted not set up either (no exit in the sample) and shipping
    /// only, IKEA Preowned pickup only (brief 129); the flat portals set up, without auctions, both ways; a page watch
    /// without sites (brief 130).
    @Test func kindsAndTheirSites() throws {
        let kinds = try JSONDecoder().decode([OfferedKind].self, from: data("kinds"))
        #expect(kinds.map(\.kind) == [.flat, .item, .price, .watch])
        #expect(kinds[2].name == "Price monitor" && kinds[2].sources.isEmpty)
        #expect(kinds[3].name == "Watch a website" && kinds[3].sources.isEmpty)
        #expect(SearchKind.choices(offered: kinds) == [.flat, .item, .price, .watch])
        #expect(kinds[0].sources.map(\.source) == Source.flatPortals
                && kinds[0].sources.allSatisfy { $0.ready && !$0.auctions && $0.delivery == .both })
        let sites = kinds[1].sources
        #expect(sites.map(\.source.rawValue) == ["kleinanzeigen", "ebay", "mydealz", "bikemarkt", "ikea_preowned", "vinted"])
        #expect(sites.map(\.name) == ["Kleinanzeigen", "eBay", "mydealz", "MTB-News Bikemarkt", "IKEA Preowned", "Vinted"])
        #expect(sites.map(\.ready) == [true, false, false, true, true, false])
        #expect(sites.map(\.auctions) == [false, true, false, false, false, false])
        #expect(sites.map(\.delivery) == [.both, .both, .shipping, .both, .pickup, .shipping])
        var form = SiteChoices(kind: .item, kinds: kinds, chosen: [.kleinanzeigen], names: SiteNames(), delivery: .either)
        #expect(form.line(language: .english) == "eBay, mydealz and Vinted are not set up yet."
                && !form.showsAuctions(chosen: [.kleinanzeigen]))
        // Pickup: mydealz and Vinted are named for their delivery, not for being unset.
        form = SiteChoices(kind: .item, kinds: kinds, chosen: [.kleinanzeigen], names: SiteNames(), delivery: .pickup)
        #expect(form.line(language: .english) == "eBay is not set up yet. mydealz and Vinted only ship.")
        form = SiteChoices(kind: .item, kinds: kinds, chosen: [.kleinanzeigen], names: SiteNames(), delivery: .shipping)
        #expect(form.line(language: .english) == "eBay, mydealz and Vinted are not set up yet. IKEA Preowned is pickup only.")
    }

    /// The overview names every site the server reads, the new ones included.
    @Test func everySiteInTheOverview() throws {
        let overview = try JSONDecoder().decode(Overview.self, from: data("overview"))
        let names = SiteNames(statuses: overview.sources)
        #expect(names.name(Source("ikea_preowned")) == "IKEA Preowned" && names.name(Source("vinted")) == "Vinted")
        #expect(names.name(Source("bikemarkt")) == "MTB-News Bikemarkt" && names.name(Source("mydealz")) == "mydealz")
    }

    /// An eBay auction: its site named by the server, the current bid, the bid count and the end.
    @Test func anEBayAuction() throws {
        let match = try JSONDecoder().decode(Match.self, from: data("ebay-match"))
        #expect(match.listing.source == .ebay && match.listing.sourceName == "eBay")
        let item = try #require(match.listing.item)
        #expect(item.priceKind == .auction && item.price == 62 && item.bids == 3)
        #expect(item.auctionEnd == Timestamp.parse("2026-11-02T14:00:00Z"))
        let overview = try JSONDecoder().decode(Overview.self, from: data("overview"))
        #expect(SiteNames(statuses: overview.sources).name(.ebay) == "eBay")
        let things = overview.hunts.compactMap { $0.hunt.search.item }
        #expect(!things.isEmpty && things.allSatisfy { $0.auctions })
    }

    /// Page watches (brief 130): an `ok` watch with what its page says now and a `blocked` one with the server's note,
    /// both without sites, and a found change from `"page"` with its lines; the other kinds have no page.
    @Test func pageWatchesAndAFoundChange() throws {
        let overview = try JSONDecoder().decode(Overview.self, from: data("overview"))
        let watches = overview.hunts.filter { $0.hunt.kind == .watch }
        #expect(watches.map { $0.page?.read } == [.ok, .blocked])
        #expect(watches.allSatisfy { $0.sources.isEmpty && $0.hunt.search.watch != nil })
        #expect(overview.hunts.filter { $0.hunt.kind != .watch }.allSatisfy { $0.page == nil })
        #expect(!overview.sources.contains { $0.source == .page })
        let ok = try #require(watches.first)
        let text = WatchCardText(ok.page, language: .english)
        #expect(text.fact != nil && text.note == nil && text.times != nil)
        let blocked = WatchCardText(watches[1].page, language: .english)
        #expect(blocked.fact == nil && blocked.note?.hasSuffix("Editing the watch tries again.") == true)
        #expect(HuntText(ok.hunt, page: ok.page, language: .english).title == ok.hunt.name)

        let page = try JSONDecoder().decode(MatchPage.self, from: data("matches"))
        // A monitor's alarm comes from "page" too; a watch's change is the one with the page's lines.
        let change = try #require(page.items.first { $0.listing.page != nil })
        #expect(change.isPageChange && !change.isThing && change.listing.item == nil)
        #expect(change.listing.page?.added.isEmpty == false && change.listing.page?.removed.isEmpty == false)
        #expect(change.watchNowLine(language: .english) != nil && change.watchTitle == WatchText.keepingAmounts(change.reason))
        #expect(page.items.filter { $0.listing.source != .page }.allSatisfy { $0.listing.page == nil })
        #expect(page.items.filter { $0.listing.page == nil && $0.listing.source == .page }.allSatisfy { $0.isPriceChange })
    }

    @Test func theOtherAnswers() throws {
        _ = try JSONDecoder().decode(Match.self, from: data("match"))
        _ = try JSONDecoder().decode(RejectedPage.self, from: data("rejected"))
        _ = try JSONDecoder().decode(Settings.self, from: data("settings"))
        _ = try JSONDecoder().decode([Place].self, from: data("places"))
    }
}
