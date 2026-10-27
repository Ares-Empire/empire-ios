import Foundation
import Observation

/// How a receipt reads on its page and in lists (pure, so tests pin both languages).
nonisolated enum ReceiptPageWording {
    /// The shop, or "Receipt" when none was read or typed.
    static func title(_ receipt: LedgerReceipt, language: AppLanguage = .current) -> String {
        receipt.shop ?? language.string("Receipt")
    }

    static func method(_ method: ReceiptMethod, language: AppLanguage = .current) -> String {
        method == .card ? language.string("Card") : language.string("Cash")
    }

    /// The day of the month for the row's tile.
    static func dayNumber(_ day: String) -> String {
        ReceiptDay.date(day).map { String(ReceiptDay.calendar.component(.day, from: $0)) } ?? "–"
    }

    /// "26 Oct 2026" / "26. Okt. 2026".
    static func shortDate(_ day: String, language: AppLanguage = .current) -> String {
        guard let date = ReceiptDay.date(day) else { return day }
        let calendar = ReceiptDay.calendar
        return date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                               timeZone: calendar.timeZone).day().month(.abbreviated).year())
    }

    /// The row's line: "26 Oct 2026 · Card", with where it stands for lists that mix them (Settings → Receipts).
    static func line(_ receipt: LedgerReceipt, withState: Bool, language: AppLanguage = .current) -> String {
        var parts = [shortDate(receipt.date, language: language)]
        if withState { parts.append(ReceiptWording.state(receipt.state, language: language)) }
        else { parts.append(method(receipt.method, language: language)) }
        return parts.joined(separator: " · ")
    }

    /// The amount as money going out, in the receipt's currency ("−€27.65", "−£12.40").
    static func amount(_ receipt: LedgerReceipt, language: AppLanguage = .current) -> String {
        if receipt.isEuro { return Money.transaction(-receipt.totalValue, language: language) }
        return "−" + ReceiptAmount.shown(receipt.totalValue, currency: receipt.currency, language: language)
    }

    /// A cash receipt in another currency: what it cost in euros ("€14.56 in euros").
    static func euros(_ receipt: LedgerReceipt, language: AppLanguage = .current) -> String? {
        guard !receipt.isEuro, receipt.method == .cash, let euros = receipt.euros else { return nil }
        return language.string("\(ReceiptAmount.shown(euros, currency: ReceiptAmount.euro, language: language)) in euros")
    }
}

/// How the dashboard's payment list names receipt rows: a receipt (its shop) with where it stands, and a withdrawal's
/// "Covered by receipts" row in the app's language (the engine names it in English).
nonisolated enum ReceiptRowWording {
    static func title(_ transaction: Transaction, language: AppLanguage = .current) -> String {
        if transaction.coveredBy != nil { return language.string("Covered by receipts") }
        if transaction.receiptId != nil, transaction.place.isEmpty { return language.string("Receipt") }
        return transaction.place
    }

    static func line(_ transaction: Transaction, language: AppLanguage = .current) -> String {
        if transaction.coveredBy != nil { return language.string("Cash spent with receipts") }
        if transaction.receiptId != nil {
            return ReceiptWording.state(transaction.isWaitingReceipt ? .waiting : .cash, language: language)
        }
        return transaction.city
    }
}

/// A receipt's page (from its dashboard row, a withdrawal's covered row, Settings → Receipts): its category with
/// Change, joining and unjoining by hand, and Delete. Every change is saved at once and the dashboard built again.
@MainActor @Observable
final class ReceiptPageModel {
    let id: String
    @ObservationIgnored let phone: PhoneBackend
    private(set) var receipt: LedgerReceipt?
    /// The bank payment it is joined to.
    private(set) var payment: LedgerPayment?
    private(set) var choices: [ReceiptCheckModel.Choice] = []
    /// "Join with a payment…": the payments offered (nil until asked for).
    private(set) var joinOptions: [ReceiptOption]?
    private(set) var isWorking = false
    private(set) var problem: String?
    /// Deleted: the page closes.
    private(set) var isDeleted = false
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
            choices = list.chosen.compactMap { chosen in
                list.name(of: chosen.id).map { ReceiptCheckModel.Choice(id: chosen.id, name: $0, look: list.look(of: chosen.id)) }
            } + [ReceiptCheckModel.Choice(id: nil, name: list.notSortedName, look: nil)]
            if receipt == nil { problem = LedgerError.receiptNotFound.localizedDescription }
        } catch {
            problem = error.localizedDescription
        }
    }

    func setCategory(_ category: String?) async {
        guard category != receipt?.category else { return }
        await work { try await self.phone.setReceiptCategory(self.id, to: category) }
    }

    func loadJoinOptions() async {
        do { joinOptions = try await phone.joinOptions(for: id) }
        catch { problem = error.localizedDescription }
    }

    func join(_ paymentID: String) async {
        await work { try await self.phone.join(receipt: self.id, to: paymentID) }
        joinOptions = nil
    }

    func unjoin() async {
        await work { try await self.phone.unjoin(receipt: self.id) }
    }

    func delete() async {
        await work(reload: false) { try await self.phone.deleteReceipt(self.id) }
        if problem == nil { isDeleted = true }
    }

    private func work(reload: Bool = true, _ change: @escaping () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
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
