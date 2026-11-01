import Foundation
import Observation

/// The check window after a receipt is read (brief 31): shop, date, total with its currency, card or cash, the category,
/// and the amount in euros where it matters. Every field can be changed (brief 33). The fields the engine is not sure
/// of, or did not find, come first and say so; the order is fixed when the window opens, so nothing jumps while the
/// person types. Card or cash is never guessed silently (D8): not read, Card is chosen only when a stored bank payment
/// matches, otherwise nothing is chosen and Save waits. Nothing read at all gives the same window with empty fields to
/// type in. A shop the person renamed before shows that name ("Corrected by you before"), and a category learned for
/// the shop is preset (`ReceiptCorrections.swift`).
///
/// The same window edits a saved receipt (`init(editing:)`, its page's Edit): filled from the stored values, nothing
/// marked, saved with `PhoneBackend.updateReceipt`.
@MainActor @Observable
final class ReceiptCheckModel {
    enum Field: String, CaseIterable, Identifiable, Sendable {
        case shop, date, total, method
        var id: String { rawValue }
    }

    /// How a field came from the reading.
    enum Mark: Equatable, Sendable {
        /// From the register's code or a clear line.
        case sure
        /// Read, but the engine is not sure of it.
        case unsure
        /// Not found on the receipt.
        case missing
        /// The shop's name as the person corrected it for this reading before (`ShopNames`): nothing to check.
        case corrected
    }

    /// A category the receipt can go to: one of the person's (or Not sorted, `id` nil).
    struct Choice: Identifiable, Equatable {
        let id: String?
        let name: String
        let look: CategoryLook?
    }

    /// The currencies offered when the receipt names none Aresium could decide on (an undecided "kr"), or to correct one.
    static let currencies = ["EUR", "GBP", "USD", "CHF", "SEK", "NOK", "DKK", "PLN", "CZK", "HUF"]

    let reading: ReceiptReading
    /// Editing a saved receipt (nil: checking a new reading).
    let editing: LedgerReceipt?
    @ObservationIgnored let phone: PhoneBackend
    var shop: String
    var date: Date
    var totalText: String
    /// ISO 4217; nil until chosen when the receipt's currency is undecided.
    var currency: String?
    var method: ReceiptMethod?
    var euroText = ""
    /// A category id; nil: Not sorted.
    var category: String?
    private(set) var choices: [Choice] = []
    /// The category preset for the shop: the one Aresium learned for it, else the shop list's (when the person has
    /// that category). For a saved receipt, its category as saved.
    private(set) var presetCategory: String?
    /// Who set `presetCategory`.
    private(set) var presetSource: CategorySource = .starter
    /// The shop's name as the person corrected it before for this reading (`shop` starts with it).
    private(set) var correctedShop: String?
    /// Card was chosen because a stored bank payment matches the receipt (it did not say card or cash).
    private(set) var cardBecauseOfMatch = false
    private(set) var isSaving = false
    private(set) var problem: String?
    /// The category menu's New category… (brief 60): the alert, its busy state and its name problem.
    let newCategory = NewCategoryModel()
    private let readDay: String?
    private let language: AppLanguage
    /// The values as the window opened (after `load`'s presets), to tell what the person changed.
    @ObservationIgnored private var start: Values?

    init(reading: ReceiptReading, phone: PhoneBackend, today: Date = .now, language: AppLanguage = .current) {
        self.reading = reading
        self.editing = nil
        self.phone = phone
        self.language = language
        shop = reading.shop ?? ""
        readDay = reading.date.flatMap { ReceiptDay.date($0) == nil ? nil : $0 }
        date = readDay.flatMap(ReceiptDay.date) ?? today
        totalText = reading.total.map { ReceiptAmount.field($0, language: language) } ?? ""
        currency = reading.currency?.uppercased()
        method = reading.method
        start = values
    }

    /// The window for a saved receipt: its values as the person confirmed them, every field as read (nothing to check
    /// first), the category as saved.
    init(editing receipt: LedgerReceipt, phone: PhoneBackend, language: AppLanguage = .current) {
        reading = ReceiptReading(shop: receipt.shop, date: receipt.date, time: receipt.time, total: receipt.totalValue,
                                 currency: receipt.currency, method: receipt.method, from: receipt.from,
                                 rows: receipt.rows, sure: .init(shop: true, date: true, total: true, method: true))
        editing = receipt
        self.phone = phone
        self.language = language
        shop = receipt.shop ?? ""
        readDay = ReceiptDay.date(receipt.date) == nil ? nil : receipt.date
        date = ReceiptDay.date(receipt.date) ?? .now
        totalText = ReceiptAmount.field(receipt.totalValue, language: language)
        currency = receipt.currency
        method = receipt.method
        euroText = receipt.euroAmount.flatMap(Double.init).map { ReceiptAmount.field($0, language: language) } ?? ""
        category = receipt.category
        presetCategory = receipt.category
        presetSource = receipt.categorySource
        start = values
    }

    // MARK: what the window shows

    func mark(_ field: Field) -> Mark {
        if editing != nil { return .sure }
        if field == .shop, correctedShop != nil { return .corrected }
        let found: Bool, sure: Bool
        switch field {
        case .shop: (found, sure) = (reading.shop?.isEmpty == false, reading.sure.shop)
        case .date: (found, sure) = (readDay != nil, reading.sure.date)
        case .total: (found, sure) = (reading.total != nil, reading.sure.total)
        case .method: (found, sure) = (reading.method != nil, reading.sure.method)
        }
        return !found ? .missing : sure ? .sure : .unsure
    }

    /// The fields to check first: not sure or not found, in the window's order.
    var fieldsToCheck: [Field] { Field.allCases.filter { [.unsure, .missing].contains(mark($0)) } }
    /// The fields read clearly (and a shop the person corrected before).
    var fieldsRead: [Field] { Field.allCases.filter { [.sure, .corrected].contains(mark($0)) } }
    /// Nothing at all was read: every field waits to be typed.
    var nothingRead: Bool { Field.allCases.allSatisfy { mark($0) == .missing } }

    /// A receipt not in euros (or one whose currency is undecided).
    var isForeign: Bool { currency != ReceiptAmount.euro }
    /// Another currency paid in cash: what it cost in euros is asked (the bank statement will never say).
    var needsEuros: Bool { isForeign && method == .cash }

    var total: Double? { ReceiptAmount.typed(totalText) }
    var euros: Double? { ReceiptAmount.typed(euroText) }

    /// What Save still waits for, in one line; nil when it can save.
    var missing: String? {
        if total == nil { return language.string("Type the total.") }
        if currency == nil { return language.string("Choose the currency.") }
        if method == nil { return language.string("Choose card or cash.") }
        if needsEuros && euros == nil { return language.string("Type what it cost in euros.") }
        return nil
    }

    var canSave: Bool { missing == nil && !isSaving }

    /// Editing: the values that decide its bank payment changed, so saving matches it again (`ReceiptEdit`). Said
    /// above Save when it was joined or will be a card receipt (a cash receipt joins nothing).
    var matchesAgainNote: String? {
        guard let editing, let draft = draft() else { return nil }
        let after = draft.receipt(id: editing.id, created: editing.created)
        guard ReceiptEdit.matchesAgain(editing, after), editing.paymentID != nil || after.method == .card else { return nil }
        return language.string("Aresium looks for its bank payment again when you save.")
    }

    /// The line under a field that is not sure or not found.
    func note(_ field: Field) -> String? {
        switch (field, mark(field)) {
        case (_, .sure): nil
        case (_, .corrected):
            // Only while it still shows that name: one typed over it is the person's own again.
            shop == correctedShop ? language.string("Corrected by you before.") : nil
        case (.method, .missing) where cardBecauseOfMatch:
            language.string("Not on the receipt. Card is chosen because a bank payment matches.")
        case (_, .missing): language.string("Not found on the receipt.")
        case (_, .unsure): language.string("Aresium is not sure about this.")
        }
    }

    // MARK: Cancel

    /// The values the person can change, compared by what they mean (the day, the amounts as numbers).
    private struct Values: Equatable {
        let shop: String
        let day: String
        let total: String
        let currency: String?
        let method: ReceiptMethod?
        let euros: String
        let category: String?
    }

    private var values: Values {
        Values(shop: shop, day: ReceiptDay.day(date), total: Self.meaning(totalText), currency: currency, method: method,
               euros: Self.meaning(euroText), category: category)
    }

    /// An amount field by its number when it reads as one ("27,65" and "27.65" are the same), else as typed.
    private static func meaning(_ text: String) -> String {
        ReceiptAmount.typed(text).map { String($0) } ?? text
    }

    /// Something was typed or changed since the window opened.
    var hasChanges: Bool { values != start }

    /// Cancel would lose something, so it asks first (brief 40): a new reading always, unless nothing at all was read
    /// (the photo is not kept, so a reading cannot be had again); a saved receipt's Edit only when something changed.
    var hasSomethingToDiscard: Bool {
        if editing != nil { return hasChanges }
        return !nothingRead || !reading.rows.isEmpty || hasChanges
    }

    // MARK: work

    /// The person's categories; for a new reading also the shop's name as they corrected it before, the category
    /// preset (the one learned for the shop, else the shop list's when the person has it), and Card when the receipt
    /// did not say card or cash but a stored bank payment matches it. Called before the window shows.
    func load() async {
        // What `load` presets is no change of the person's (it runs before the window shows).
        defer { start = values }
        let list = await loadChoices()
        guard editing == nil else { return }
        if let corrected = try? await phone.correctedShopName(read: reading.shop), corrected != reading.shop,
           shop == (reading.shop ?? "") {
            correctedShop = corrected
            shop = corrected
        }
        if let learned = try? await phone.learnedCategory(forShop: trimmedShop) {
            presetCategory = learned
            presetSource = .learned
            category = learned
        } else if let list, let id = reading.categoryId, list.isChosen(id) {
            presetCategory = id
            presetSource = .starter
            category = id
        }
        guard reading.method == nil, method == nil, let total, let currency else { return }
        let matches = (try? await phone.hasMatch(date: ReceiptDay.day(date), total: total, currency: currency,
                                                 shop: trimmedShop)) ?? false
        if matches, method == nil {
            method = .card
            cardBecauseOfMatch = true
        }
    }

    /// The person's categories, then Not sorted.
    @discardableResult
    private func loadChoices() async -> PhoneCategoryList? {
        guard let list = try? await phone.categories(language: language) else { return nil }
        choices = CashCategories.choices(list, for: .out, keeping: category)
        return list
    }

    /// The menu's New category… (brief 60): the category is made (`NewCategoryModel`), offered and picked here. It is a
    /// change of the person's, so Cancel asks first; the category stays after Cancel.
    func createCategory() async {
        await newCategory.create(in: phone, side: .spend) { id, _ in
            guard let list = await loadChoices() else { return LedgerError.notFound.localizedDescription }
            if !choices.contains(where: { $0.id == id }), let name = list.name(of: id) {
                choices.insert(.init(id: id, name: name, look: list.look(of: id)), at: max(0, choices.count - 1))
            }
            category = id
            return nil
        }
    }

    /// Keeps the receipt (and joins or asks, `PhoneBackend.saveReceipt`; editing: `updateReceipt`); nil when it could
    /// not be saved (`problem`).
    func save() async -> ReceiptSaved? {
        guard canSave, let draft = draft() else { return nil }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            if let editing { return try await phone.updateReceipt(editing.id, with: draft) }
            return try await phone.saveReceipt(draft)
        }
        catch {
            problem = error.localizedDescription
            return nil
        }
    }

    /// The receipt as the person confirmed it.
    func draft() -> ReceiptDraft? {
        guard let total, let currency, let method else { return nil }
        let day = ReceiptDay.day(date)
        let source: CategorySource = category == nil ? .none : category == presetCategory ? presetSource : .manual
        return ReceiptDraft(date: day, time: day == readDay ? reading.time : nil, shop: trimmedShop, total: total,
                            currency: currency, euroAmount: needsEuros ? euros : nil, method: method,
                            category: category, categorySource: source, rows: reading.rows, from: reading.from,
                            shopAsRead: editing == nil ? reading.shop : editing?.shopAsRead)
    }

    private var trimmedShop: String? {
        let shop = shop.trimmingCharacters(in: .whitespacesAndNewlines)
        return shop.isEmpty ? nil : shop
    }
}
