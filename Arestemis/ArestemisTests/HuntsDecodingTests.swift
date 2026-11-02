import Foundation
import Testing
@testable import Arestemis

@MainActor
struct HuntsDecodingTests {
    private func decodeHunt(_ transform: (inout [String: Any]) -> Void) throws -> Hunt {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("overview")) as? [String: Any])
        var hunt = try #require(object["hunt"] as? [String: Any])
        transform(&hunt)
        object["hunt"] = hunt
        let overview = try JSONDecoder().decode(Overview.self, from: JSONSerialization.data(withJSONObject: object))
        return try #require(overview.hunt)
    }
    @Test func unknownKindKeepsItsString() throws {
        let hunt = try decodeHunt { $0["kind"] = "boat"; $0["search"] = ["length": 10] }
        #expect(hunt.kind == .unknown("boat") && hunt.search == .unsupported)
        #expect(try JSONEncoder().encode(hunt.kind) == Data(#""boat""#.utf8))
    }
    @Test(arguments: ["flat", "item"])
    func brokenSearchLeavesTheHunt(_ kind: String) throws {
        let hunt = try decodeHunt { $0["kind"] = kind; $0["search"] = ["query": 5] }
        #expect(hunt.search == .unsupported && hunt.id == 1)
    }
    @Test func oldOverviewBuildsOneCard() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("overview")) as? [String: Any])
        object.removeValue(forKey: "hunts")
        let data = try JSONSerialization.data(withJSONObject: object)
        let overview = try JSONDecoder().decode(Overview.self, from: data)
        #expect(overview.hunts.count == 1 && overview.hunts[0].hunt == overview.hunt)
        #expect(overview.hunts[0].counts == overview.counts && !overview.hunts[0].slowed)
        object["hunt"] = NSNull()
        #expect(try JSONDecoder().decode(Overview.self, from: JSONSerialization.data(withJSONObject: object)).hunts.isEmpty)
    }
    @Test func itemHuntListingAndMatch() throws {
        let overview = try sample(Overview.self, "overview")
        let hunt = try #require(overview.hunts.first { $0.hunt.kind == .item }?.hunt)
        #expect(hunt.search.item?.query == "Herman Miller Aeron" && hunt.search.item?.vbOverMax == 45)
        let page = try sample(MatchPage.self, "item-matches")
        #expect(page.items.count == 4 && page.items[0].atStart)
        #expect(page.items[1].overMax == 30 && page.items[1].listing.item?.priceKind == .negotiable)
        #expect(page.items[2].listing.item?.shippingCost == 6.19 && page.items[3].listing.item?.priceKind == .free)
        #expect(page.items.allSatisfy { $0.listing.kind == nil && $0.listing.rentWarm == nil })
    }
    @Test func futureOptionalValuesAreNil() throws {
        let details = try JSONDecoder().decode(ItemDetails.self, from: Data(#"{"condition":"excellent","price_kind":"trade","shipping":"drone","seller":"club"}"#.utf8))
        #expect(details.condition == nil && details.priceKind == nil && details.shipping == nil && details.seller == nil)
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("hunts")) as? [[String: Any]])
        var search = try #require(object[1]["search"] as? [String: Any])
        search["condition_min"] = "future"
        search["sources"] = ["newportal", "kleinanzeigen"]
        object[1]["search"] = search
        let hunts = try JSONDecoder().decode([Hunt].self, from: JSONSerialization.data(withJSONObject: object))
        #expect(hunts[1].search.item?.conditionMin == nil && hunts[1].search.item?.sources == [Source("newportal"), .kleinanzeigen])
    }
    @Test func missingAtStartMeansFalse() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("match")) as? [String: Any])
        object.removeValue(forKey: "at_start")
        object.removeValue(forKey: "over_max")
        #expect(try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object)).atStart == false)
    }
}
