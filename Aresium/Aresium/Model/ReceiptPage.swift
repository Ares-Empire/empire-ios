import Foundation
import Observation

/// How a receipt reads on its page and in lists (pure, so tests pin both languages).
nonisolated enum ReceiptPageWording {
    /// The shop, or "Receipt" when none was read or typed; a hand entry what was typed, or "Cash spent" / "Cash
    /// received".
    static func title(_ receipt: LedgerReceipt, language: AppLanguage = .current) -> String {
        if receipt.kind == .manual { return CashWording.entryTitle(receipt, language: language) }
        return receipt.shop ?? language.string("Receipt")
    }

    /// Where a receipt stands, in one line; a hand entry says what it is.
    static func standing(_ receipt: LedgerReceipt, language: AppLanguage = .current) -> String {
        guard receipt.kind == .manual else { return ReceiptWording.state(receipt.state, language: language) }
        return receipt.direction == .in ? language.string("Cash received") : language.string("Cash, entered by hand")
    }

    static func method(_ method: ReceiptMethod, language: AppLanguage = .current) -> String {
        method == .card ? language.string("Card") : language.string("Cash")
    }

    /// "26 Oct 2026" / "26. Okt. 2026".
    static func shortDate(_ day: String, language: AppLanguage = .current) -> String {
        guard let date = ReceiptDay.date(day) else { return day }
        let calendar = ReceiptDay.calendar
        return date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                               timeZone: calendar.timeZone).day().month(.abbreviated).year())
    }

    /// The row's line: "26 Oct 2026 · Card", with where it stands for lists that mix them (Settings → Receipts); a
    /// hand entry says what it is.
    static func line(_ receipt: LedgerReceipt, withState: Bool, language: AppLanguage = .current) -> String {
        var parts = [shortDate(receipt.date, language: language)]
        if withState || receipt.kind == .manual { parts.append(standing(receipt, language: language)) }
        else { parts.append(method(receipt.method, language: language)) }
        return parts.joined(separator: " · ")
    }

    /// The amount from the wallet's side, in the receipt's currency: money going out ("−€27.65", "−£12.40"), cash
    /// received coming in ("+€50.00").
    static func amount(_ receipt: LedgerReceipt, language: AppLanguage = .current) -> String {
        let sign = receipt.direction == .in ? 1.0 : -1.0
        if receipt.isEuro { return Money.transaction(sign * receipt.totalValue, language: language) }
        return (sign < 0 ? "−" : "+") + ReceiptAmount.shown(receipt.totalValue, currency: receipt.currency, language: language)
    }

    /// A cash receipt in another currency: what it cost in euros ("€14.56 in euros").
    static func euros(_ receipt: LedgerReceipt, language: AppLanguage = .current) -> String? {
        guard !receipt.isEuro, receipt.method == .cash, let euros = receipt.euros else { return nil }
        return language.string("\(ReceiptAmount.shown(euros, currency: ReceiptAmount.euro, language: language)) in euros")
    }
}

/// How the dashboard's payment list names receipt and entry rows: a receipt (its shop) with where it stands, a hand
/// entry with what it is, and a withdrawal's covered row ("Accounted for": the part of it spent with receipts or entries
/// and counted in their categories) in the app's language (the engine names it in English). `movement`: the row's cash
/// movement on the Cash page, which tells a hand entry from a cash receipt.
nonisolated enum ReceiptRowWording {
    static func title(_ transaction: Transaction, movement: CashMovement? = nil, language: AppLanguage = .current) -> String {
        if transaction.coveredBy != nil { return language.string("Accounted for") }
        if transaction.receiptId != nil, transaction.place.isEmpty {
            if transaction.amount > 0 { return language.string("Cash received") }
            return movement?.kind == .manual ? language.string("Cash spent") : language.string("Receipt")
        }
        return transaction.place
    }

    static func line(_ transaction: Transaction, movement: CashMovement? = nil, language: AppLanguage = .current) -> String {
        if transaction.coveredBy != nil { return language.string("Counted where it was spent") }
        if transaction.receiptId != nil {
            if transaction.amount > 0 { return language.string("Cash received") }
            if movement?.kind == .manual { return language.string("Cash, entered by hand") }
            return ReceiptWording.state(transaction.isWaitingReceipt ? .waiting : .cash, language: language)
        }
        return transaction.city
    }
}

/// A receipt's page (from its dashboard row, a withdrawal's covered row, Settings → Receipts): its category with
/// Change, Edit (the check window filled from the stored receipt, brief 33), joining and unjoining by hand, and Delete.
/// Every change is saved at once and the dashboard built again. While one of them works (`working`), its button shows
/// the spinner and the others are greyed (brief 40).
@MainActor @Observable
final class ReceiptPageModel: Identifiable {
    /// Edit's sheet: the check window, then, when the corrected values have bank payments to ask about, the question.
    struct Editing: Identifiable {
        enum Phase {
            case checking(ReceiptCheckModel)
            case asking(ReceiptQuestion)
            /// A hand entry: the Add cash window filled from it.
            case entry(CashEntryModel)
        }
        let id = UUID()
        var phase: Phase
    }

    /// What the page is doing after a tap, so that button shows the spinner.
    enum Work: Equatable {
        case edit, paidFrom, category, unjoin, delete
        /// Join with a payment…: the payment tapped.
        case join(String)
    }

    let id: String
    @ObservationIgnored let phone: PhoneBackend
    private(set) var receipt: LedgerReceipt?
    /// The Cash page's data, for a cash receipt's or entry's Paid from (or what a received entry still holds).
    private(set) var cash: CashPage?
    /// The bank payment it is joined to.
    private(set) var payment: LedgerPayment?
    private(set) var choices: [ReceiptCheckModel.Choice] = []
    /// "Join with a payment…": the payments offered (nil until asked for).
    private(set) var joinOptions: [ReceiptOption]?
    /// The work under way (nil: none).
    private(set) var working: Work?
    var isWorking: Bool { working != nil }
    private(set) var problem: String?
    /// Deleted: the page closes.
    private(set) var isDeleted = false
    /// Edit's sheet while it is open.
    private(set) var editing: Editing?
    @ObservationIgnored private let changed: () async -> Void

    init(id: String, phone: PhoneBackend, changed: @escaping () async -> Void) {
        self.id = id
        self.phone = phone
        self.changed = changed
    }

    var categoryName: String? {
        guard let receipt else { return nil }
        return choices.first { $0.id == receipt.category }?.name
    }

    var categoryColor: String {
        guard let category = receipt?.category, let look = choices.first(where: { $0.id == category })?.look
        else { return PhoneDashboard.uncategorised.color }
        return look.color
    }

    func load() async {
        do {
            receipt = try await phone.receipt(id)
            payment = try await receipt?.paymentID.asyncMap { try await phone.payment($0) } ?? nil
            let list = try await phone.categories()
            // A hand entry offers the categories of its direction; a scanned receipt every category, as before.
            choices = CashCategories.choices(list, for: receipt?.kind == .manual ? receipt?.direction : nil)
            cash = receipt?.method == .cash ? try await phone.cash().map(CashPage.init) : nil
            if receipt == nil { problem = LedgerError.receiptNotFound.localizedDescription }
        } catch {
            problem = error.localizedDescription
        }
    }

    // MARK: cash

    /// Cash going out (a cash receipt, a spent entry): it has Paid from.
    var hasPaidFrom: Bool { receipt?.method == .cash && receipt?.direction == .out }

    /// This receipt's movement on the Cash page (nil for a card receipt or one in another currency).
    var movement: CashMovement? { cash?.movement(id) }

    /// Paid from's choice in words: Automatic, or the source chosen.
    var paidFromChoice: String {
        CashWording.choice(receipt?.paidFrom.flatMap { cash?.movement($0) }.map(CashSource.init))
    }

    /// Where the engine took the cash from: "From the withdrawal of 18 Oct", "From cash not recorded here".
    var paidFromLine: String? {
        guard let movement, let cash else { return nil }
        return CashWording.paidFrom(movement, in: cash)
    }

    /// Paid from's choices: withdrawals and cash received on or before the receipt's day, newest first.
    var sources: [CashSource] {
        guard let receipt, let cash else { return [] }
        return cash.sources(onOrBefore: receipt.date, besides: id)
    }

    func setPaidFrom(_ source: String?) async {
        guard source != receipt?.paidFrom else { return }
        await work(.paidFrom) { try await self.phone.setPaidFrom(self.id, to: source) }
    }

    func setCategory(_ category: String?) async {
        guard category != receipt?.category else { return }
        await work(.category) { try await self.phone.setReceiptCategory(self.id, to: category) }
    }

    func loadJoinOptions() async {
        do { joinOptions = try await phone.joinOptions(for: id) }
        catch { problem = error.localizedDescription }
    }

    func join(_ paymentID: String) async {
        await work(.join(paymentID)) { try await self.phone.join(receipt: self.id, to: paymentID) }
        joinOptions = nil
    }

    func unjoin() async {
        await work(.unjoin) { try await self.phone.unjoin(receipt: self.id) }
    }

    func delete() async {
        await work(.delete, reload: false) { try await self.phone.deleteReceipt(self.id) }
        if problem == nil { isDeleted = true }
    }

    // MARK: Edit

    /// Opens Edit: the check window with the receipt as stored now.
    func beginEdit() async {
        guard editing == nil, !isWorking else { return }
        working = .edit
        problem = nil
        defer { working = nil }
        do {
            guard let stored = try await phone.receipt(id) else { throw LedgerError.receiptNotFound }
            if stored.kind == .manual {
                let entry = CashEntryModel(editing: stored, phone: phone)
                await entry.load()
                editing = Editing(phase: .entry(entry))
                return
            }
            let check = ReceiptCheckModel(editing: stored, phone: phone)
            await check.load()
            editing = Editing(phase: .checking(check))
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Save in Edit: kept (`PhoneBackend.updateReceipt`); with bank payments to ask about, the question follows in the
    /// same sheet, else it closes and the page shows the receipt as it is now.
    func saveEdit(_ check: ReceiptCheckModel) async {
        guard let saved = await check.save() else { return }
        if case let .question(question) = saved {
            editing?.phase = .asking(question)
        } else {
            await finishEdit()
        }
    }

    /// Save in an entry's Edit: kept, and the sheet closes.
    func saveEntry(_ entry: CashEntryModel) async {
        guard await entry.save() != nil else { return }
        await finishEdit()
    }

    /// "Is this the same payment?" after Edit: a payment, or nil ("None of these": it waits).
    func answerEdit(_ question: ReceiptQuestion, with paymentID: String?) async {
        problem = nil
        do {
            try await phone.answer(question, with: paymentID)
            await finishEdit()
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Edit's sheet closed (Cancel, or the question swiped away: the receipt waits). Anything saved already stays.
    func endEdit() {
        guard let editing else { return }
        self.editing = nil
        // The corrected values were kept before the question: the page and the dashboard show them.
        if case .asking = editing.phase { Task { await changed(); await load() } }
    }

    #if DEBUG
    /// Screenshots: a total typed into Edit's window (`-editReceiptTotal`).
    func debugType(total: String?) {
        guard let total, case .checking(let check)? = editing?.phase else { return }
        check.totalText = total
    }
    #endif

    private func finishEdit() async {
        editing = nil
        await changed()
        await load()
    }

    private func work(_ kind: Work, reload: Bool = true, _ change: @escaping () async throws -> Void) async {
        guard !isWorking else { return }
        working = kind
        problem = nil
        defer { working = nil }
        #if DEBUG
        await DebugLaunch.holdWork()
        #endif
        do {
            try await change()
            await changed()
            if reload { await load() }
        } catch {
            problem = error.localizedDescription
        }
    }
}

private extension Optional {
    func asyncMap<T>(_ transform: (Wrapped) async throws -> T) async rethrows -> T? {
        guard let self else { return nil }
        return try await transform(self)
    }
}
