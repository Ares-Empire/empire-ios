import Foundation
import Testing
@testable import Arestemis

@MainActor
struct ItemFormattingTests {
    private func details() -> ItemDetails { ItemDetails(price: 80, priceKind: .fixed) }
    private func spaces(_ value: String?) -> String? { value?.replacingOccurrences(of: "\u{a0}", with: " ") }
    @Test(arguments: [AppLanguage.english, .german])
    func priceKinds(_ language: AppLanguage) {
        let de = language == .german
        var item = details()
        #expect(spaces(item.priceLine(language: language)) == (de ? "80 €" : "€80"))
        item.priceKind = .negotiable
        #expect(spaces(item.priceLine(language: language)) == (de ? "80 € VB" : "€80 VB"))
        item.price = nil; #expect(item.priceLine(language: language) == "VB")
        item.priceKind = .free; #expect(item.priceLine(language: language) == (de ? "Zu verschenken" : "Free"))
        item.priceKind = .onRequest; #expect(item.priceLine(language: language) == (de ? "Preis auf Anfrage" : "Price on request"))
        item.priceKind = .auction; item.price = 80
        #expect(spaces(item.priceLine(language: language)) == (de ? "80 € (Gebot)" : "€80 (bid)"))
        item.priceKind = nil; #expect(item.priceLine(language: language) == nil)
    }
    @Test(arguments: [AppLanguage.english, .german])
    func conditionsShippingDistanceSellerAndReserved(_ language: AppLanguage) {
        let de = language == .german
        #expect(Condition.allCases.map { $0.title(language: language) }
                == (de ? ["Neu", "Wie neu", "Gut", "In Ordnung", "Defekt"] : ["New", "Like new", "Good", "OK", "For parts"]))
        var item = details()
        item.shipping = .yes
        #expect(item.shippingLine(language: language) == (de ? "Versand" : "Shipping"))
        item.shippingCost = 6.19
        #expect(spaces(item.shippingLine(language: language)) == (de ? "Versand ab 6,19 €" : "Shipping from €6.19"))
        item.shipping = .pickupOnly
        #expect(item.shippingLine(language: language) == (de ? "Nur Abholung" : "Pickup only"))
        item.distanceKm = 5; #expect(item.distanceLine(language: language) == "5 km")
        item.distanceKm = 0.8; #expect(item.distanceLine(language: language) == (de ? "0,8 km" : "0.8 km"))
        item.seller = .private; #expect(item.sellerLine(language: language) == (de ? "Privat" : "Private"))
        item.seller = .commercial; #expect(item.sellerLine(language: language) == (de ? "Gewerblich" : "Commercial"))
        item.reserved = false; #expect(item.reservedLine(language: language) == nil)
        item.reserved = true; #expect(item.reservedLine(language: language) == (de ? "Reserviert" : "Reserved"))
    }
    @Test(arguments: [AppLanguage.english, .german])
    func factsLimitAndHuntSummary(_ language: AppLanguage) throws {
        let de = language == .german
        let matches = try sample(MatchPage.self, "item-matches").items
        #expect(matches[0].listing.itemFacts(language: language) == (de ? "Wie neu · Garching (5 km) · Nur Abholung · Privat" : "Like new · Garching (5 km) · Pickup only · Private"))
        let facts = matches[2].listing.itemDetailFacts(now: Clock.now, calendar: Clock.berlin, language: language)
        #expect(facts.map(\.label) == (de ? ["Zustand", "Übergabe", "Versandkosten", "Verkäufer", "Ort", "Eingestellt"]
                                          : ["Condition", "Delivery", "Shipping cost", "Seller", "Place", "Posted"]))
        #expect(facts.dropLast().map { spaces($0.value) } == (de ? ["Gut", "Versand", "ab 6,19 €", "Privat", "Garching"]
                                                              : ["Good", "Shipping", "from €6.19", "Private", "Garching"]))
        #expect(matches[1].overMaxLine(language: language) == (de ? "VB, 30 € über deinem Limit" : "VB, 30 € over your limit"))
        #expect(matches[0].overMaxLine(language: language) == nil)
        let overview = try sample(Overview.self, "overview")
        var item = overview.hunts[1].hunt
        #expect(item.displayName(language: language) == "Herman Miller Aeron")
        #expect(spaces(HuntSummary(item, language: language).line) == (de ? "Herman Miller Aeron · bis 450 € · Abholung oder Versand · Garching (20 km) · Kleinanzeigen" : "Herman Miller Aeron · up to €450 · Pickup or shipping · Garching (20 km) · Kleinanzeigen"))
        item.name = "Office chair"; #expect(item.displayName(language: language) == "Office chair")
        let flat = overview.hunts[0].hunt
        #expect(flat.displayName(language: language) == SearchSummary(try #require(flat.search.flat), language: language).kinds)
        #expect(HuntSummary(flat, now: Clock.now, calendar: Clock.berlin, language: language).parts
                == SearchSummary(try #require(flat.search.flat), now: Clock.now, calendar: Clock.berlin, language: language).parts)
    }
}
