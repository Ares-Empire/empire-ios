import Foundation
import Observation

// Cash (brief 33 part B, D9 in ares-empire/docs/ARESIUM-FOR-OTHERS.md; the engine is brief 32's): cash that never came
// from the bank, entered by hand (spent or received); where a cash payment was paid from; and one Cash page with every
// movement of the wallet. A hand entry is kept as a receipt (`LedgerReceipt`: kind manual, cash, its direction, no rows,
// never joined to a bank payment), so storage, export and deleting need nothing of their own. The engine counts entries
// with the receipts (`buildDashboardSource`'s `receipts`) and builds the page's numbers (`Dashboard.cash`); the page is
// a view and counts in no total.

/// What the Add cash window saves.
nonisolated struct CashEntryDraft: Equatable, Sendable {
    var direction: ReceiptDirection
    /// In euros (entries have no other currency: the engine counts cash in euros only).
    var amount: Double
    /// `YYYY-MM-DD`.
    var date: String
    /// Spent: where or what for; received: from whom or what for.
    var what: String?
    /// A category id; nil: Not sorted.
    var category: String?
    /// Spent: the withdrawal or received entry it was paid from; nil: automatic.
    var paidFrom: String?

    func receipt(id: String = UUID().uuidString, created: Date = .now) -> LedgerReceipt {
        let what = what?.trimmingCharacters(in: .whitespacesAndNewlines)
        return LedgerReceipt(id: id, date: date, time: nil, shop: what.flatMap { $0.isEmpty ? nil : $0 },
                             total: ReceiptAmount.stored(amount), currency: ReceiptAmount.euro, euroAmount: nil,
                             method: .cash, category: category, categorySource: category == nil ? .none : .manual,
                             rows: [], from: "text", paymentID: nil, created: created, direction: direction,
                             kind: .manual, paidFrom: direction == .out ? paidFrom : nil)
    }
}

/// A source a cash payment can be paid from: a withdrawal or cash received, with what it still holds.
nonisolated struct CashSource: Identifiable, Equatable, Sendable {
    let id: String
    let kind: CashMovement.Kind
    let date: String
    let amount: Double
    let place: String
    let left: Double

    init(_ movement: CashMovement) {
        id = movement.id
        kind = movement.kind
        date = movement.date
        amount = movement.amount
        place = movement.place
        left = movement.left ?? 0
    }
}

/// The Cash page's logic over the engine's `cash`, pure so tests pin it.
nonisolated struct CashPage: Equatable {
    let cash: CashView

    /// A month's numbers (none: all zero).
    func month(_ key: String) -> CashMonth { cash.months[key] ?? .none }

    /// The months with a movement, newest first (Overview).
    var monthKeys: [String] { cash.months.keys.sorted(by: >) }

    /// A month's movements, newest first (on one day, money out above the money in it took from).
    func movements(in month: String) -> [CashMovement] {
        Array(cash.movements.filter { $0.month == month }.reversed())
    }

    func movement(_ id: String) -> CashMovement? { cash.movements.first { $0.id == id } }

    /// The sources a payment on `day` can be paid from: withdrawals and cash received on or before it, newest first
    /// (`besides`: the entry itself).
    func sources(onOrBefore day: String, besides id: String? = nil) -> [CashSource] {
        cash.movements.filter { $0.isSource && $0.date <= day && $0.id != id }.reversed().map(CashSource.init)
    }

    /// How far back Automatic looks for a source (the engine's `CASH_LOOKBACK_DAYS`, `receipts/count.ts`). Paid from lists
    /// those sources first and the older ones behind "Show older": a year of monthly withdrawals that all still hold
    /// money made one long list (Claude, 2026-10-28).
    static let lookbackDays = 92

    /// Paid from's sources (newest first) split for the list: the ones Automatic could take (at most `lookbackDays` before
    /// `day`) and the older ones. A chosen older source stays with the first, so the choice is always in sight.
    static func split(_ sources: [CashSource], before day: String, selected: String?) -> (recent: [CashSource], older: [CashSource]) {
        guard let end = dayNumber(day) else { return (sources, []) }
        var recent: [CashSource] = [], older: [CashSource] = []
        for source in sources {
            if source.id != selected, let start = dayNumber(source.date), end - start > lookbackDays {
                older.append(source)
            } else {
                recent.append(source)
            }
        }
        return (recent, older)
    }

    /// Days since 1970 for a `YYYY-MM-DD` day (the engine's `dayNumber`), nil when it is not one.
    private static func dayNumber(_ day: String) -> Int? {
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        return Int((date.timeIntervalSince1970 / 86_400).rounded())
    }
}

/// The words for cash (English here, German in the catalog): pure, so tests pin both languages.
nonisolated enum CashWording {
    static func kind(_ kind: CashMovement.Kind, language: AppLanguage = .current) -> String {
        switch kind {
        case .withdrawal: language.string("Withdrawal")
        case .received: language.string("Received")
        case .receipt: language.string("Receipt")
        case .manual: language.string("Entry")
        }
    }

    /// A movement's title: its place, else what it is.
    static func title(_ movement: CashMovement, language: AppLanguage = .current) -> String {
        if !movement.place.isEmpty { return movement.place }
        switch movement.kind {
        case .received: return language.string("Cash received")
        case .manual: return language.string("Cash spent")
        case .withdrawal, .receipt: return kind(movement.kind, language: language)
        }
    }

    /// A hand entry's title: what was typed, else what it is.
    static func entryTitle(_ receipt: LedgerReceipt, language: AppLanguage = .current) -> String {
        if let shop = receipt.shop, !shop.isEmpty { return shop }
        return receipt.direction == .in ? language.string("Cash received") : language.string("Cash spent")
    }

    /// "26 Oct" / "26. Okt.".
    static func day(_ day: String, language: AppLanguage = .current) -> String {
        guard let date = ReceiptDay.date(day) else { return day }
        let calendar = ReceiptDay.calendar
        return date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                               timeZone: calendar.timeZone).day().month(.abbreviated))
    }

    /// "the withdrawal of 18 Oct" / "the cash received on 3 Oct", as part of a sentence.
    static func source(kind: CashMovement.Kind, date: String, language: AppLanguage = .current) -> String {
        let day = day(date, language: language)
        return kind == .withdrawal ? language.string("the withdrawal of \(day)")
                                   : language.string("the cash received on \(day)")
    }

    /// Where a payment out came from, as the engine counted it: "From the withdrawal of 18 Oct", "… and 1 more", or
    /// "From cash not recorded here" when no withdrawal or received cash covered it.
    static func paidFrom(_ movement: CashMovement, in page: CashPage, language: AppLanguage = .current) -> String? {
        guard let from = movement.paidFrom else { return nil }
        let sources = from.compactMap(page.movement)
        guard let first = sources.first else { return language.string("From cash not recorded here") }
        let named = source(kind: first.kind, date: first.date, language: language)
        return sources.count == 1 ? language.string("From \(named)")
                                  : language.string("From \(named) and \(sources.count - 1) more")
    }

    /// What a source still holds: "€40.00 left".
    static func left(_ amount: Double, language: AppLanguage = .current) -> String {
        language.string("\(ReceiptAmount.shown(amount, currency: ReceiptAmount.euro, language: language)) left")
    }

    /// Paid from's choice: "Automatic", or the source by kind and day.
    static func choice(_ source: CashSource?, language: AppLanguage = .current) -> String {
        guard let source else { return language.string("Automatic") }
        let day = day(source.date, language: language)
        return source.kind == .withdrawal ? language.string("Withdrawal of \(day)")
                                          : language.string("Cash received on \(day)")
    }

    /// The month's numbers, by name.
    static func withdrawn(_ language: AppLanguage = .current) -> String { language.string("Withdrawn") }
    static func received(_ language: AppLanguage = .current) -> String { language.string("Received") }
    static func spent(_ language: AppLanguage = .current) -> String { language.string("Spent") }
    static func unaccounted(_ language: AppLanguage = .current) -> String { language.string("Not accounted for") }
}

/// The categories a receipt or entry can go to, by which way the money went: spending categories for money out,
/// income ones for money in (one's own may be either, so they are in both; transfers in neither), then Not sorted. Nil:
/// every category the person has (a scanned receipt, as before).
@MainActor
enum CashCategories {
    static func choices(_ list: PhoneCategoryList, for direction: ReceiptDirection?, keeping selected: String? = nil) -> [ReceiptCheckModel.Choice] {
        var ids = direction.map { list.offered(for: $0, includingTransfers: false) }
            ?? list.chosen.map(\.id).filter { !list.isTransfer($0) }
        // A transfer explicitly requested by name stays selected when its receipt or entry is edited later.
        if let selected, list.isChosen(selected), list.isTransfer(selected), !ids.contains(selected) { ids.append(selected) }
        return ids.compactMap { id in
            guard let name = list.name(of: id) else { return nil }
            return ReceiptCheckModel.Choice(id: id, name: name, look: list.look(of: id))
        } + [ReceiptCheckModel.Choice(id: nil, name: list.notSortedName, look: nil)]
    }
}

/// The Cash row's and the months' lines (pure, so tests pin both languages).
nonisolated enum CashRowWording {
    /// The dashboard row: the cash no receipt or entry accounts for, or what the page holds when everything is. In plain
    /// words, "€300.00 without receipts" (brief 215, the first-run review's finding 14: "not accounted for" read like a
    /// warning to a newcomer with withdrawals and no receipts; the Cash page explains its own heading).
    static func line(unaccounted: Double, language: AppLanguage = .current) -> String {
        guard unaccounted >= 0.005 else { return language.string("Withdrawals, cash received and spent") }
        return language.string("\(Money.precise(unaccounted, language: language)) without receipts")
    }

    /// A month in Overview: "Withdrawn €100.00 · Spent €43.40 · €56.60 without receipts" (the parts that are not 0).
    static func monthLine(_ month: CashMonth, language: AppLanguage = .current) -> String {
        var parts: [String] = []
        if month.withdrawn > 0 { parts.append(language.string("Withdrawn \(Money.precise(month.withdrawn, language: language))")) }
        if month.received > 0 { parts.append(language.string("Received \(Money.precise(month.received, language: language))")) }
        if month.spent > 0 { parts.append(language.string("Spent \(Money.precise(month.spent, language: language))")) }
        if month.unaccounted >= 0.005 { parts.append(line(unaccounted: month.unaccounted, language: language)) }
        return parts.joined(separator: " · ")
    }
}

// MARK: - the Add cash window

/// Add cash (and Edit on an entry's page): spent or received, the amount in euros, the day, what (or from whom), the
/// category (spending categories for spent, income ones for received, and Not sorted) and, for spent, Paid from.
/// Saved as a receipt of kind manual (`PhoneBackend.addCashEntry` / `updateCashEntry`).
@MainActor @Observable
final class CashEntryModel: Identifiable {
    let id = UUID()
    /// Editing a saved entry (nil: a new one).
    let editing: LedgerReceipt?
    @ObservationIgnored let phone: PhoneBackend
    var direction: ReceiptDirection {
        didSet {
            guard direction != oldValue else { return }
            if !choices.contains(where: { $0.id == category }) { category = nil }
            if direction == .in { paidFrom = nil }
        }
    }
    var amountText = ""
    var date: Date
    var what = ""
    /// A category id; nil: Not sorted.
    var category: String?
    /// Spent: the source chosen in Paid from; nil: automatic.
    var paidFrom: String?
    private(set) var spendChoices: [ReceiptCheckModel.Choice] = []
    private(set) var incomeChoices: [ReceiptCheckModel.Choice] = []
    /// Paid from's sources for the day chosen (nil until loaded).
    private(set) var sources: [CashSource]?
    private(set) var isSaving = false
    private(set) var problem: String?
    /// The category menu's New category… (brief 60): the alert, its busy state and its name problem.
    let newCategory = NewCategoryModel()
    private let language: AppLanguage
    /// The values as the window opened, to tell what the person changed.
    @ObservationIgnored private var start: Values?

    init(direction: ReceiptDirection = .out, phone: PhoneBackend, today: Date = .now, language: AppLanguage = .current) {
        editing = nil
        self.phone = phone
        self.language = language
        self.direction = direction
        date = today
        start = values
    }

    /// The window for a saved entry, filled from it.
    init(editing entry: LedgerReceipt, phone: PhoneBackend, language: AppLanguage = .current) {
        editing = entry
        self.phone = phone
        self.language = language
        direction = entry.direction
        amountText = ReceiptAmount.field(entry.totalValue, language: language)
        date = ReceiptDay.date(entry.date) ?? .now
        what = entry.shop ?? ""
        category = entry.category
        paidFrom = entry.paidFrom
        start = values
    }

    /// The categories offered: spending ones for spent, income ones for received, then Not sorted.
    var choices: [ReceiptCheckModel.Choice] { direction == .out ? spendChoices : incomeChoices }

    var amount: Double? { ReceiptAmount.typed(amountText) }
    var day: String { ReceiptDay.day(date) }

    /// What Save still waits for, in one line; nil when it can save.
    var missing: String? { amount == nil ? language.string("Type the amount.") : nil }
    var canSave: Bool { missing == nil && !isSaving }

    /// Paid from's current choice in words: the source, or Automatic (also for a source after the day chosen, which
    /// `draft` leaves out).
    var paidFromName: String {
        CashWording.choice(sources?.first { $0.id == paidFrom }, language: language)
    }

    /// The person's categories, split by how they count; one's own may be either, so they are in both.
    func load() async {
        guard await loadChoices() else { return }
        if !self.choices.contains(where: { $0.id == category }) {
            // A saved category no longer offered is dropped by the window, not by the person.
            if start?.category == category { start?.category = nil }
            category = nil
        }
        await loadSources()
    }

    /// Both lists from the person's categories; false when they could not be read.
    private func loadChoices() async -> Bool {
        guard let list = try? await phone.categories(language: language) else { return false }
        spendChoices = CashCategories.choices(list, for: .out, keeping: category)
        incomeChoices = CashCategories.choices(list, for: .in, keeping: category)
        return true
    }

    /// The menu's New category… (brief 60), for spent and received alike (the new category takes this window's side): the
    /// category is made (`NewCategoryModel`), offered and picked here. Cancel asks first; the category stays after it.
    func createCategory() async {
        await newCategory.create(in: phone, side: CategorySide(direction: direction)) { id, _ in
            guard await loadChoices(), let list = try? await phone.categories(language: language) else { return LedgerError.notFound.localizedDescription }
            if !choices.contains(where: { $0.id == id }), let name = list.name(of: id) {
                let choice = ReceiptCheckModel.Choice(id: id, name: name, look: list.look(of: id))
                if direction == .out { spendChoices.insert(choice, at: max(0, spendChoices.count - 1)) }
                else { incomeChoices.insert(choice, at: max(0, incomeChoices.count - 1)) }
            }
            category = id
            return nil
        }
    }

    // MARK: Cancel

    /// The values the person can change, compared by what they mean (the day, the amount as a number).
    private struct Values: Equatable {
        var direction: ReceiptDirection
        var amount: String
        var day: String
        var what: String
        var category: String?
        var paidFrom: String?
    }

    private var values: Values {
        Values(direction: direction, amount: ReceiptAmount.typed(amountText).map { String($0) } ?? amountText, day: day,
               what: what, category: category, paidFrom: paidFrom)
    }

    /// Something was typed or changed since the window opened: Cancel asks before discarding it, and a new entry's
    /// swipe down is held back (brief 40).
    var hasChanges: Bool { values != start }

    /// Paid from's sources on or before the day chosen (the entry itself left out).
    func loadSources() async {
        sources = (try? await phone.cashSources(onOrBefore: day, besides: editing?.id)) ?? []
    }

    /// The draft as typed; nil while the amount is missing. A Paid from source after the day is left out (it cannot
    /// have paid for it).
    func draft() -> CashEntryDraft? {
        guard let amount else { return nil }
        let source = direction == .out ? paidFrom : nil
        let valid = source.flatMap { id in sources.map { list in list.contains { $0.id == id } } } ?? true
        return CashEntryDraft(direction: direction, amount: amount, date: day, what: what, category: category,
                              paidFrom: valid ? source : nil)
    }

    /// Keeps the entry; nil when it could not be saved (`problem`).
    func save() async -> LedgerReceipt? {
        guard canSave, let draft = draft() else { return nil }
        isSaving = true
        problem = nil
        defer { isSaving = false }
        do {
            if let editing { return try await phone.updateCashEntry(editing.id, with: draft) }
            return try await phone.addCashEntry(draft)
        } catch {
            problem = error.localizedDescription
            return nil
        }
    }
}
