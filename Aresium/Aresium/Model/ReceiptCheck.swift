import Foundation
import Observation

/// The check window after a receipt is read (brief 31): shop, date, total, card or cash, the category, and the currency
/// and the amount in euros where they matter. The fields the engine is not sure of, or did not find, come first and say
/// so; the order is fixed when the window opens, so nothing jumps while the person types. Card or cash is never
/// guessed silently (D8): not read, Card is chosen only when a stored bank payment matches, otherwise nothing is chosen
/// and Save waits. Nothing read at all gives the same window with empty fields to type in.
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
    /// The shop list's category for the shop, when the person has that category.
    private(set) var presetCategory: String?
    /// Card was chosen because a stored bank payment matches the receipt (it did not say card or cash).
    private(set) var cardBecauseOfMatch = false
    private(set) var isSaving = false
    private(set) var problem: String?
    private let readDay: String?
    private let language: AppLanguage

    init(reading: ReceiptReading, phone: PhoneBackend, today: Date = .now, language: AppLanguage = .current) {
        self.reading = reading
        self.phone = phone
        self.language = language
        shop = reading.shop ?? ""
        readDay = reading.date.flatMap { ReceiptDay.date($0) == nil ? nil : $0 }
        date = readDay.flatMap(ReceiptDay.date) ?? today
        totalText = reading.total.map { ReceiptAmount.field($0, language: language) } ?? ""
        currency = reading.currency?.uppercased()
        method = reading.method
    }

    // MARK: what the window shows

    func mark(_ field: Field) -> Mark {
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
    var fieldsToCheck: [Field] { Field.allCases.filter { mark($0) != .sure } }
    /// The fields read clearly.
    var fieldsRead: [Field] { Field.allCases.filter { mark($0) == .sure } }
    /// Nothing at all was read: every field waits to be typed.
    var nothingRead: Bool { Field.allCases.allSatisfy { mark($0) == .missing } }

    /// The currency row shows for a receipt not in euros (or one whose currency is undecided).
    var showsCurrency: Bool { currency != ReceiptAmount.euro }
    /// Another currency paid in cash: what it cost in euros is asked (the bank statement will never say).
    var needsEuros: Bool { showsCurrency && method == .cash }

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

    /// The line under a field that is not sure or not found.
    func note(_ field: Field) -> String? {
        switch (field, mark(field)) {
        case (_, .sure): nil
        case (.method, .missing) where cardBecauseOfMatch:
            language.string("Not on the receipt. Card is chosen because a bank payment matches.")
        case (_, .missing): language.string("Not found on the receipt.")
        case (_, .unsure): language.string("Aresium is not sure about this.")
        }
    }

    // MARK: work

    /// The person's categories (and the shop list's one preset when they have it), and Card when the receipt did not
    /// say card or cash but a stored bank payment matches it.
    func load() async {
        if let list = try? await phone.categories(language: language) {
            choices = list.chosen.compactMap { chosen in
                list.name(of: chosen.id).map { Choice(id: chosen.id, name: $0, look: list.look(of: chosen.id)) }
            } + [Choice(id: nil, name: list.notSortedName, look: nil)]
            if let id = reading.categoryId, list.isChosen(id) {
                presetCategory = id
                category = id
            }
        }
        guard reading.method == nil, method == nil, let total, let currency else { return }
        let matches = (try? await phone.hasMatch(date: ReceiptDay.day(date), total: total, currency: currency,
                                                 shop: trimmedShop)) ?? false
        if matches, method == nil {
            method = .card
            cardBecauseOfMatch = true
        }
    }

    /// Keeps the receipt (and joins or asks, `PhoneBackend.saveReceipt`); nil when it could not be saved (`problem`).
    func save() async -> ReceiptSaved? {
        guard canSave, let draft = draft() else { return nil }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do { return try await phone.saveReceipt(draft) }
        catch {
            problem = error.localizedDescription
            return nil
        }
    }

    /// The receipt as the person confirmed it.
    func draft() -> ReceiptDraft? {
        guard let total, let currency, let method else { return nil }
        let day = ReceiptDay.day(date)
        let source: CategorySource = category == nil ? .none : category == presetCategory ? .starter : .manual
        return ReceiptDraft(date: day, time: day == readDay ? reading.time : nil, shop: trimmedShop, total: total,
                            currency: currency, euroAmount: needsEuros ? euros : nil, method: method,
                            category: category, categorySource: source, rows: reading.rows, from: reading.from)
    }

    private var trimmedShop: String? {
        let shop = shop.trimmingCharacters(in: .whitespacesAndNewlines)
        return shop.isEmpty ? nil : shop
    }
}
