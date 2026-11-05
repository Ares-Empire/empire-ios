import Foundation
import Testing
@testable import Arestemis

@MainActor
struct ProductSuggestionsTests {
    private let route = ProductItemSearch(query: "Meridian Laptop", extra: "16 GB RAM")

    private func refusal(_ names: [String] = ["Meridian Air 14"]) -> FieldRefusal {
        FieldRefusal(field: "product", message: "Name one product.",
                     productSuggestions: ProductSuggestions(names: names, itemSearch: route))
    }

    @Test(arguments: [false, true], [false, true])
    func optionalFieldsDecode(names: Bool, itemSearch: Bool) async throws {
        var json: [String: Any] = ["error": "Name one product.", "field": "product"]
        if names { json["suggestions"] = ["Meridian Air 14", "Meridian Pro 16"] }
        if itemSearch { json["item_search"] = ["query": route.query, "extra": route.extra] }
        let transport = FakeTransport(fallback: (400, try JSONSerialization.data(withJSONObject: json)))
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        do {
            _ = try await api.productPreview(product: route.query, details: route.extra)
            Issue.record("Expected a product refusal")
        } catch let error as FieldRefusal {
            #expect(error.field == "product" && error.message == "Name one product.")
            #expect(error.productSuggestions?.names == (names || itemSearch ? (names ? ["Meridian Air 14", "Meridian Pro 16"] : []) : nil))
            #expect(error.productSuggestions?.itemSearch == (itemSearch ? route : nil))
        }
        let sent = try body(transport.requests.only)
        #expect(sent?["product"] as? String == route.query && sent?["details"] as? String == route.extra)
    }

    @Test func choicesAreBoundedAndOnlyProductRefusalsHaveThem() throws {
        let data = Data(#"{"error":"Choose one","field":"product","suggestions":["Model 1","Model 2","Model 3","Model 4","Model 5"]}"#.utf8)
        #expect(FieldRefusal(status: 400, data: data)?.productSuggestions?.names == ["Model 1", "Model 2", "Model 3", "Model 4"])
        #expect(FieldRefusal(status: 503, data: data) == nil)
        let page = Data(#"{"error":"No single price","field":"url","suggestions":["Model 1"],"item_search":{"query":"Original","extra":"Blue"}}"#.utf8)
        #expect(FieldRefusal(status: 400, data: page)?.productSuggestions == nil)
        let old = Data(#"{"message":"Old refusal","field":"product"}"#.utf8)
        #expect(FieldRefusal(status: 400, data: old) == FieldRefusal(field: "product", message: "Old refusal"))
        let malformed = Data(#"{"error":"Choose one","field":"product","suggestions":false,"item_search":{"query":"Incomplete"}}"#.utf8)
        #expect(FieldRefusal(status: 400, data: malformed) == FieldRefusal(field: "product", message: "Choose one"))
        let success = Data(#"{"identity":{"name":"Model 1"},"future_field":true}"#.utf8)
        let preview = try JSONDecoder().decode(ProductPreview.self, from: success)
        #expect(preview.identity.name == "Model 1" && preview.offers.isEmpty && preview.sites.isEmpty)
    }

    @Test func emptyChoicesStillOfferThingsButUnavailableAndCancelledDoNot() async throws {
        let model = ProductPreviewModel(pause: .zero, spacing: .zero) { words in
            switch words.product {
            case "Generic": throw refusal([])
            case "Cancelled": throw CancellationError()
            default: throw HTTPError.server(503, "Try later.")
            }
        }
        model.update(product: "Generic", details: "")
        await model.settle()
        #expect(model.suggestions(for: ProductWords(product: "Generic")) == ProductSuggestions(itemSearch: route))
        model.update(product: "Down", details: "")
        #expect(model.fieldRefusal == nil && model.answer == nil)
        await model.settle()
        #expect(model.phase == .failed("Try later.") && model.fieldRefusal == nil)
        model.update(product: "Cancelled", details: "")
        await model.settle()
        #expect(model.phase == .idle && model.fieldRefusal == nil)
        model.ask(nil)
        #expect(model.query == nil && model.suggestions(for: ProductWords(product: "Generic")) == nil)
    }

    @Test func aChipKeepsDetailsClearsConfirmationAndAsksAgain() async throws {
        var asked: [ProductPreviewQuery] = []
        let model = ProductPreviewModel(pause: .zero, spacing: .zero) { words in
            asked.append(words)
            return ProductPreview(identity: ProductIdentity(name: words.product))
        }
        var draft = PriceSearchDraft()
        draft.product = route.query
        draft.details = route.extra
        draft.name = "Laptop prices"
        draft.sourcesOff = ["example"]
        draft.confirm(ProductIdentity(name: "Old identity"), for: draft.words)
        model.update(product: draft.product, details: draft.details)
        await model.settle()
        model.select("Meridian Air 14", in: &draft)
        #expect(draft.product == "Meridian Air 14" && draft.details == route.extra && draft.name == "Laptop prices")
        #expect(draft.sourcesOff == ["example"] && draft.identity == nil && draft.identityWords == nil)
        // It may be saved at once (brief 180), but never with the old product.
        #expect(draft.isValid && draft.search()?.identity == nil && model.phase == .reading && model.answer == nil)
        await model.settle()
        draft.confirm(try #require(model.answer).identity, for: try #require(model.query))
        #expect(draft.isValid && draft.search()?.identity?.name == "Meridian Air 14")
        // Selecting even the same words requires a fresh preview.
        model.select("Meridian Air 14", in: &draft)
        #expect(!draft.isConfirmed && model.answer == nil)
        await model.settle()
        #expect(asked.map(\.product) == [route.query, "Meridian Air 14", "Meridian Air 14"])
        draft.confirm(try #require(model.answer).identity, for: draft.words)
        // The preview compares trimmed words; surrounding spaces must not strand an otherwise confirmed draft.
        draft.product += " "
        draft.details += " "
        #expect(draft.isConfirmed)
        draft.details = "Blue"
        draft.details = route.extra
        #expect(draft.identity == nil && !draft.isConfirmed)
        // The page's existing validation is independent of product confirmation.
        draft.mode = .page
        draft.url = "https://shop.example/product"
        #expect(draft.isValid && draft.search()?.mode == .page)
    }

    /// A held request lets the test change the fields before returning any kind of old answer.
    private final class Gate {
        var requests: [ProductPreviewQuery] = []
        var replies: [CheckedContinuation<ProductPreview, any Error>] = []
        var listener: (Int, CheckedContinuation<Void, Never>)?

        func fetch(_ words: ProductPreviewQuery) async throws -> ProductPreview {
            try await withCheckedThrowingContinuation { continuation in
                requests.append(words)
                replies.append(continuation)
                if let (count, listener) = listener, requests.count >= count {
                    self.listener = nil
                    listener.resume()
                }
            }
        }

        func started(_ count: Int) async {
            if requests.count >= count { return }
            await withCheckedContinuation { listener = (count, $0) }
        }
    }

    @Test(arguments: ["refused", "found", "429", "cancelled"])
    func answersForAnEarlierRevisionAreDropped(outcome: String) async throws {
        let gate = Gate()
        let model = ProductPreviewModel(pause: .zero, spacing: .zero, fetch: gate.fetch)
        model.update(product: route.query, details: route.extra)
        await gate.started(1)
        model.update(product: "Other words", details: "")
        model.update(product: route.query, details: route.extra)
        switch outcome {
        case "refused": gate.replies[0].resume(throwing: refusal())
        case "found": gate.replies[0].resume(returning: ProductPreview(identity: ProductIdentity(name: "Stale")))
        case "429": gate.replies[0].resume(throwing: HTTPError.server(429, "Wait"))
        default: gate.replies[0].resume(throwing: CancellationError())
        }
        await gate.started(2)
        #expect(model.phase == .reading && model.answer == nil && model.fieldRefusal == nil)
        gate.replies[1].resume(returning: ProductPreview(identity: ProductIdentity(name: "Current")))
        await model.settle()
        #expect(model.answer?.identity.name == "Current" && gate.requests.count == 2)
        model.ask(nil)
        #expect(model.fieldRefusal == nil && model.answer == nil)
    }

    @Test func a429RetriesAtThePacedIntervalWithoutOldChoices() async throws {
        var calls: [(ProductPreviewQuery, ContinuousClock.Instant)] = []
        let model = ProductPreviewModel(pause: .zero, spacing: .milliseconds(40)) { words in
            calls.append((words, ContinuousClock().now))
            if words.product == "Family" { throw refusal() }
            if calls.count == 2 { throw HTTPError.server(429, "Wait") }
            return ProductPreview(identity: ProductIdentity(name: words.product))
        }
        model.update(product: "Family", details: "")
        await model.settle()
        #expect(model.fieldRefusal != nil)
        model.update(product: "New words", details: "Blue")
        #expect(model.fieldRefusal == nil)
        await model.settle()
        try #require(calls.count == 3)
        #expect(calls[1].0 == calls[2].0 && calls[1].1.duration(to: calls[2].1) >= .milliseconds(40))
        #expect(model.answer?.identity.name == "New words" && model.fieldRefusal == nil)
    }

    @Test func thingsNavigationRetainsEverywhereAndOnlyPrefillsTheNormalDraft() async throws {
        let (store, transport, _) = try await makeStore()
        var draft = PriceSearchDraft()
        draft.product = route.query
        draft.details = route.extra
        draft.name = "Laptop prices"
        draft.url = "https://shop.example/original"
        draft.sourcesOff = ["example"]
        store.keepSearchDraft(draft, huntID: nil)
        let navigation = AppNavigation()
        navigation.openNewForm(.price)
        let previous = navigation.huntPath
        let requests = transport.requests.count
        navigation.openItemSearch(route)
        #expect(navigation.huntPath == previous + [.itemSearch(route)])
        let filled = route.draft
        #expect(filled.words == [route.query] && filled.extra == route.extra && filled.name.isEmpty)
        #expect(filled.priceMax.isEmpty && filled.places.isEmpty && filled.delivery == .either)
        #expect(filled.search() == nil && transport.requests.count == requests)
        navigation.huntPath.removeLast()
        #expect(navigation.huntPath == previous && store.searchDraft(PriceSearchDraft.self, huntID: nil) == draft)
        // A comma is part of this server query, not a request to split it into several search words.
        #expect(ProductItemSearch(query: "Laptop, compact", extra: "Blue").draft.words == ["Laptop, compact"])
    }

    @Test func comparisonUsesKindAndKeepsUnknownKinds() throws {
        let comparison = PriceSite(id: "future", name: "Example", kind: .comparison, state: .unreadable)
        #expect(comparison.isComparison && EverywhereWords.state(comparison.state, language: .english) == "can't be read now")
        #expect(!PriceSite(id: "idealo", name: "idealo", kind: .shop).isComparison)
        let unknown = try JSONDecoder().decode(PriceSite.self, from: Data(#"{"id":"future","kind":"outlet","state":"new"}"#.utf8))
        #expect(!unknown.isComparison && unknown.kind == .unknown("outlet") && unknown.state == .unknown("new"))
    }

    @Test(arguments: [AppLanguage.english, .german])
    func routeWords(language: AppLanguage) {
        #expect(route.title(language: language) == (language == .german
            ? "Alle Angebote zu „Meridian Laptop“ → Dinge-Suche" : "All offers for ‘Meridian Laptop’ → Things search"))
        #expect(language.string("Price comparison") == (language == .german ? "Preisvergleich" : "Price comparison"))
    }
}
