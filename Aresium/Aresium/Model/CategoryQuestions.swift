import Foundation

/// The first Add question, shared by a payment and a selection. Names are the dashboard's localized names.
nonisolated struct RemoveCurrentQuestion: Identifiable, Equatable, Sendable {
    let id = UUID()
    let category: String
    let categories: [String]
    var selection = false

    func title(language: AppLanguage = .current) -> String {
        let current = CategoryName.shown(category, language: language)
        return selection ? language.string("Also remove them from \(current)?")
            : language.string("Also remove from \(current)?")
    }

    func message(language: AppLanguage = .current) -> String {
        let names = CategoryQuestionWording.list(categories, language: language)
        return selection ? language.string("Then they count only under \(names).")
            : language.string("Then it counts only under \(names).")
    }

    func removeTitle(language: AppLanguage = .current) -> String { language.string("Remove") }
    func keepTitle(language: AppLanguage = .current) -> String { language.string("Keep both") }
}

/// The same words for the single window and the selection's window. Extras never imply learning a shop.
nonisolated struct CategoryQuestionWording: Sendable {
    let count: Int
    let selectedCount: Int
    let shopCount: Int
    let shop: String?
    let category: String
    var added: [String] = []
    var removed: [String] = []
    var selection = false
    var changesExtras: Bool { !added.isEmpty || !removed.isEmpty }

    static func list(_ names: [String], language: AppLanguage) -> String {
        names.map { CategoryName.shown($0, language: language) }
            .formatted(.list(type: .and).locale(language.locale))
    }

    func question(language: AppLanguage = .current) -> String {
        guard changesExtras else {
            if selection { return BatchWording.question(count: count, shops: shopCount, shop: shop, language: language) }
            return language.string("Also the other payments from \(shop ?? "")?")
        }
        let adding = Self.list(added, language: language), removing = Self.list(removed, language: language)
        if let shop, shopCount == 1 {
            if removed.isEmpty { return language.string("Also add \(adding) to the other \(count) payments from \(shop)?") }
            if added.isEmpty { return language.string("Also remove \(removing) from the other \(count) payments from \(shop)?") }
            return language.string("Also add \(adding) and remove \(removing) for the other \(count) payments from \(shop)?")
        }
        if removed.isEmpty { return language.string("Also add \(adding) to the other \(count) payments from these \(shopCount) shops?") }
        if added.isEmpty { return language.string("Also remove \(removing) from the other \(count) payments from these \(shopCount) shops?") }
        return language.string("Also add \(adding) and remove \(removing) for the other \(count) payments from these \(shopCount) shops?")
    }

    func message(language: AppLanguage = .current) -> String? {
        guard !changesExtras, let shop else { return nil }
        return language.string("From now on, payments from \(shop) go to \(category).")
    }

    func allTitle(language: AppLanguage = .current) -> String {
        if changesExtras { return language.string("All \(count + selectedCount)") }
        return language.string("Move \(count) more")
    }

    func onlyTitle(language: AppLanguage = .current) -> String {
        selection ? language.string("Only these") : language.string("Only this one")
    }
}
