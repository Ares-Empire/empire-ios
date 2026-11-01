import Foundation

/// A category's home for totals; payment direction only controls which choices are offered.
nonisolated enum CategorySide: String, Codable, Sendable, CaseIterable {
    case spend, income

    init(direction: ReceiptDirection) { self = direction == .in ? .income : .spend }
    init(amount: Double) { self = amount > 0 ? .income : .spend }
    var direction: ReceiptDirection { self == .income ? .in : .out }
}

/// The person's categories in phone mode, by id (what the store keeps) and by name (what the dashboard and the Switch/Add
/// choices use). Default and built-in categories are named in the app's language from the engine's list; one's own keep
/// the name as typed. Names are unique in both languages (`checkedName`), so a name always leads back to one id.
nonisolated struct PhoneCategoryList: Equatable, Sendable {
    let catalog: CategoryCatalog
    let chosen: [ChosenCategory]
    var language: AppLanguage = .current

    /// Names the dashboard itself uses for its own entries; one's own category may not take them. "Cash" / "Bargeld"
    /// is the Cash page since the withdrawals' category became "Cash withdrawals" / "Abhebungen" (brief 33).
    static let reservedNames = ["Uncategorised", "Refunds", "Other", "Tax", "Cash", "Bargeld"]

    /// The ids payments may be sorted into: the chosen ones in their order, then the built-in own transfers (always
    /// there, never listed).
    var sortingIDs: [String] { chosen.map(\.id) + [CategoryCatalog.ownTransfers] }

    func isChosen(_ id: String) -> Bool { chosen.contains { $0.id == id } }

    /// Personal names override the catalog in both languages; unnamed defaults follow the app language.
    func name(of id: String) -> String? {
        if let name = chosen.first(where: { $0.id == id })?.name { return name }
        return catalog.category(id)?.name(in: language)
    }

    /// The id behind a name the dashboard shows (a chosen category or own transfers).
    func id(named name: String) -> String? {
        sortingIDs.first { self.name(of: $0) == name }
    }

    /// A category's icon and colour: one's own as stored with it (`OwnCategoryLook`), the others the engine's.
    func look(of id: String) -> CategoryLook {
        if ChosenCategory.isCustom(id), let look = chosen.first(where: { $0.id == id })?.look { return look }
        return catalog.look(id)
    }

    /// Transfers (own transfers, savings) count as neither spending nor income.
    func isTransfer(_ id: String) -> Bool { catalog.category(id)?.kind == "transfer" }

    /// Defaults take their home side from the catalog; one's own keep it in the store. Transfers have no side.
    func side(of id: String) -> CategorySide? {
        if ChosenCategory.isCustom(id) {
            return chosen.first { $0.id == id }?.side.flatMap(CategorySide.init(rawValue:))
        }
        return catalog.category(id).flatMap { CategorySide(rawValue: $0.kind) }
    }

    func hasOtherSide(_ id: String) -> Bool { chosen.first { $0.id == id }?.otherSide == true }

    /// Categories for this direction: its home categories, transfers when requested, then the other home's additions.
    /// Each part keeps the chosen order. The engine orders its tiles by all-time totals; membership is identical.
    /// Not sorted is represented by nil in receipt/cash menus and appended there after these ids.
    func offered(for direction: ReceiptDirection, includingTransfers: Bool = true) -> [String] {
        let home = CategorySide(direction: direction)
        let own = chosen.map(\.id).filter { side(of: $0) == home }
        let transfers = includingTransfers ? sortingIDs.filter(isTransfer) : []
        let added = chosen.map(\.id).filter { side(of: $0) != nil && side(of: $0) != home && hasOtherSide($0) }
        return own + transfers + added
    }

    /// The list `buildDashboardSource` gets: every category payments may be in, named and with its look.
    var sourceCategories: [SourceCategory] {
        sortingIDs.compactMap { id in
            guard let name = name(of: id) else { return nil }
            let look = look(of: id)
            return SourceCategory(name: name, icon: look.icon, color: look.color, excludeFromTotals: isTransfer(id),
                                  side: side(of: id)?.rawValue, otherSide: hasOtherSide(id) ? true : nil)
        }
    }

    /// The name of the built-in "Not sorted", for the question where an unticked category's payments go.
    var notSortedName: String {
        catalog.category(CategoryCatalog.notSorted)?.name(in: language) ?? language.string("Not sorted")
    }

    /// Shared comparison for creation, reuse and rename, in either language and ignoring case and accents.
    static func sameName(_ lhs: String, _ rhs: String) -> Bool {
        lhs.compare(rhs, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
    }

    /// Finds an available category by its own name or either original default name. Built-ins and page names refuse.
    func reusableID(named typed: String) throws -> String? {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LedgerError.emptyName }
        let refused = catalog.builtIns.flatMap { [$0.name.en, $0.name.de] } + Self.reservedNames
        guard !refused.contains(where: { Self.sameName($0, name) }) else { throw LedgerError.nameTaken }
        if let own = chosen.first(where: { $0.name.map { Self.sameName($0, name) } == true }) { return own.id }
        return catalog.defaults.first { Self.sameName($0.name.en, name) || Self.sameName($0.name.de, name) }?.id
    }

    /// A new or renamed category, excluding this category's own current and original names from collisions.
    func checkedName(_ typed: String, excluding id: String? = nil) throws -> String {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw LedgerError.emptyName }
        let ownNames = catalog.defaults.filter { $0.id == id }.flatMap { [$0.name.en, $0.name.de] }
            + chosen.filter { $0.id == id }.compactMap(\.name)
        let reserved = Self.reservedNames.filter { reserved in !ownNames.contains { Self.sameName($0, reserved) } }
        let taken = catalog.defaults.filter { $0.id != id }.flatMap { [$0.name.en, $0.name.de] }
            + catalog.builtIns.flatMap { [$0.name.en, $0.name.de] }
            + chosen.filter { $0.id != id }.compactMap(\.name) + reserved
        guard !taken.contains(where: { Self.sameName($0, name) }) else { throw LedgerError.nameTaken }
        return name
    }

    /// The picker's list: the default categories by group, in the engine's order, each with whether it is ticked.
    var groups: [CategoryGroup] {
        var groups: [CategoryGroup] = []
        for category in catalog.defaults {
            let item = CategoryGroup.Item(id: category.id, name: name(of: category.id) ?? category.name(in: language), look: look(of: category.id),
                                          chosen: isChosen(category.id), side: side(of: category.id),
                                          otherSide: hasOtherSide(category.id),
                                          originalName: chosen.first { $0.id == category.id }?.name == nil ? nil : category.name(in: language))
            if let index = groups.firstIndex(where: { $0.id == category.group }) { groups[index].items.append(item) }
            else { groups.append(CategoryGroup(id: category.group, title: CategoryGroup.title(category.group, language: language),
                                               items: [item])) }
        }
        return groups
    }

    /// One's own categories, in the order they were added.
    var custom: [CategoryGroup.Item] {
        chosen.filter { ChosenCategory.isCustom($0.id) }.map {
            CategoryGroup.Item(id: $0.id, name: $0.name ?? "", look: look(of: $0.id), chosen: true, side: side(of: $0.id),
                               otherSide: $0.otherSide)
        }
    }
}

/// A group of the default list in the category picker.
nonisolated struct CategoryGroup: Identifiable, Equatable, Sendable {
    struct Item: Identifiable, Equatable, Sendable {
        let id: String
        let name: String
        let look: CategoryLook
        let chosen: Bool
        /// Its home side: where it is offered (brief 69); nil for transfers, which are offered both ways.
        var side: CategorySide? = nil
        /// Also offered for the other direction.
        var otherSide = false
        /// Present only while a default has a personal name.
        var originalName: String? = nil

        /// Settings can offer it for the other direction too, or take that back (brief 70): a ticked category with a
        /// side (`PhoneBackend.setOtherSide`; never a transfer).
        var canOfferOtherSide: Bool { chosen && side != nil }
        /// The side line under the name: one's own category's side, which the person chooses (`setSide`).
        var choosesSide: Bool { ChosenCategory.isCustom(id) && side != nil }
        /// The quiet line "Also for money in" (or out) under the name.
        var showsOtherSide: Bool { canOfferOtherSide && otherSide }
    }

    /// The engine's group word.
    let id: String
    let title: String
    var items: [Item]

    /// The engine names its groups in English; the app words them in its language (an unknown group keeps the engine's
    /// word).
    static func title(_ group: String, language: AppLanguage = .current) -> String {
        switch group {
        case "Everyday": language.string("Everyday")
        case "Home": language.string("Home")
        case "Getting around": language.string("Getting around")
        case "Health & care": language.string("Health & care")
        case "Free time": language.string("Free time")
        case "Shopping": language.string("Shopping")
        case "Study & work": language.string("Study & work")
        case "Money": language.string("Money")
        case "Income": language.string("Income")
        case "Other": language.string("Other")
        default: group
        }
    }
}

/// Which account a file's payments belong to: its IBAN when the file names one, PayPal for PayPal's export, else the
/// bank the engine recognised, else the table's own header (a layout the person confirmed).
nonisolated enum AccountKey {
    static func account(for file: BankFile, layout: CsvLayout? = nil, language: AppLanguage = .current) -> LedgerAccount {
        let iban = file.account?.iban.flatMap { $0.isEmpty ? nil : $0 }
        let named = file.account?.name.flatMap { $0.isEmpty ? nil : $0 }
        let name = named ?? file.bank?.name ?? (file.source == "paypal" ? "PayPal" : language.string("Bank account"))
        let id: String
        if let iban { id = "iban:" + iban.uppercased().replacingOccurrences(of: " ", with: "") }
        else if file.source == "paypal" { id = "paypal" }
        else if let bank = file.bank { id = "bank:" + bank.id + (named.map { ":" + $0 } ?? "") }
        else if let table = layout ?? file.layout {
            id = "layout:" + ([table.separator] + table.header).joined(separator: "|")
        } else { id = "file:" + file.format + (named.map { ":" + $0 } ?? "") }
        return LedgerAccount(id: id, name: name, iban: iban, bank: file.bank?.name, currency: file.account?.currency)
    }
}
