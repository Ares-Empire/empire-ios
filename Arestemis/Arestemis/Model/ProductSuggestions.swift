import Foundation

/// The server's optional choices on a completed `400 field: product` preview refusal (brief 163).
nonisolated struct ProductSuggestions: Equatable, Sendable {
    let names: [String]
    let itemSearch: ProductItemSearch?

    nonisolated init(names: [String] = [], itemSearch: ProductItemSearch? = nil) {
        self.names = Array(names.prefix(4))
        self.itemSearch = itemSearch
    }
}

/// Only the documented `item_search` fields: the original query and details, opening an unsaved Things form.
nonisolated struct ProductItemSearch: Codable, Hashable, Sendable {
    let query: String
    let extra: String

    @MainActor var draft: ItemSearchDraft {
        var draft = ItemSearchDraft()
        draft.words = [query]
        draft.extra = extra
        return draft
    }

    @MainActor func title(language: AppLanguage = .current) -> String {
        language.string("All offers for ‘\(query)’ → Things search")
    }
}

#if DEBUG
/// Invented data for `-productSample family|generic|chip|things`; no requests leave sample mode.
enum ProductSuggestionSample {
    static let family = "Meridian Laptop"
    static let generic = "Portable computer"
    static let details = "16 GB RAM"
    static let names = ["Meridian Air 14", "Meridian Pro 16", "Meridian Studio 16 with OLED display, 16 GB memory and 1 TB storage in silver",
                        "Meridian Flex 13"]

    /// The server's family and generic refusal, in its English as the samples (`docs/samples/product-refusal*.json`).
    static func refusal(product: String, details: String) -> FieldRefusal {
        FieldRefusal(field: "product", message: "Name one specific product.",
                     productSuggestions: ProductSuggestions(names: product == family ? names : [],
                         itemSearch: ProductItemSearch(query: product, extra: details)))
    }
}
#endif
