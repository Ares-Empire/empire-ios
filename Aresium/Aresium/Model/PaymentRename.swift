import Foundation
import Observation

// Brief 44: renaming a payment and the page of all payments of one name, on brief 43's data (`PaymentNames.swift`).
// What a rename saves, when it asks first, what the name's page shows and how its words read are decided here, so the
// screens (`TransactionDetailSheet`'s name field, brief 47; `NameScreen`) only draw them. Phone mode only.

/// One save of brief 43's API: a name (empty removes it) for this payment alone or for its shop.
nonisolated struct PaymentNameStep: Equatable, Sendable {
    let name: String
    let scope: PaymentNameScope

    static func payment(_ name: String) -> PaymentNameStep { PaymentNameStep(name: name, scope: .payment) }
    static func shop(_ name: String) -> PaymentNameStep { PaymentNameStep(name: name, scope: .shop) }
}

/// What Save in the rename window does with what was typed.
nonisolated enum RenameIntent: Equatable {
    /// Nothing changed (or nothing typed while the bank's name shows): Save is off.
    case nothing
    /// A new own name.
    case name(String)
    /// Back to the bank's name: the field emptied, the bank's name typed, or "Use the bank's name".
    case bankName
}

/// The rules for renaming one payment (Claude's choices, briefs 44 and 47):
/// - The field starts with the name the page shows (the payment's own, else its shop's, else the bank's), all selected,
///   so typing replaces it.
/// - A new name asks "Also the other payments from <bank name>?" (with "All N+1" and "Only this one", as the category
///   change asks) whenever the shop can be named (a merchant key) and has other payments, also when the name shown came
///   from the payment alone or from the shop: the answer picks the scope each time. All N+1 saves the shop's name and
///   drops this payment's own one (so it follows the shop too); Only this one saves it for this payment, and a shop's
///   name stays for the others. Without other payments or a merchant key: this payment only, no question.
/// - Back to the bank's name removes every name this payment shows (its own, and its shop's under it). When other
///   payments show the shop's name it asks first, "Use the bank's name for all N+1 payments?": All N+1 removes the
///   shop's name, Only this one (brief 47) keeps the bank's name on this payment alone (`PaymentNames.keptBankName`),
///   Cancel leaves everything.
nonisolated struct RenamePlan: Equatable {
    /// "Also the other payments from <bank name>?" (N on the first answer's button), with what each answer saves.
    struct Question: Equatable, Identifiable {
        let name: String
        let bankName: String
        /// N: the shop's other payments.
        let others: Int
        let all: [PaymentNameStep]
        let onlyThis: [PaymentNameStep]
        var id: String { name }
        /// The first answer's number: the shop's payments with this one.
        var allCount: Int { others + 1 }
    }

    /// "Use the bank's name for all N+1 payments?": a shop's name that other payments show goes (All), or stays for
    /// them while this payment shows the bank's name (Only this one; nil where the bank's name cannot be kept).
    struct BankNameQuestion: Equatable, Identifiable {
        let shopName: String
        let bankName: String
        let count: Int
        let steps: [PaymentNameStep]
        let onlyThis: [PaymentNameStep]?
        var id: String { shopName }
    }

    enum Outcome: Equatable {
        case save([PaymentNameStep])
        case ask(Question)
        case confirmBankName(BankNameQuestion)
    }

    let info: PaymentRenameInfo

    /// What the field shows when it opens: the name the page shows.
    var start: String { info.ownName ?? info.bankName }

    /// Whether a new name asks about the shop's other payments (a merchant key and N > 0).
    var asksAboutOthers: Bool { info.canRenameShop && info.otherPaymentCount > 0 }

    func intent(_ typed: String) -> RenameIntent {
        let name = PaymentNames.normalized(typed)
        if name.isEmpty || name == PaymentNames.keptBankName(info.bankName) {
            return info.ownName == nil ? .nothing : .bankName
        }
        return name == info.ownName ? .nothing : .name(name)
    }

    /// What Save (or "Use the bank's name") does: save at once, or ask first. Nil when there is nothing to save.
    func outcome(_ intent: RenameIntent) -> Outcome? {
        switch intent {
        case .nothing:
            return nil
        case let .name(name):
            let onlyThis = [PaymentNameStep.payment(name)]
            guard asksAboutOthers else { return .save(onlyThis) }
            let all = [PaymentNameStep.shop(name)] + (info.paymentOwnName == nil ? [] : [.payment("")])
            return .ask(Question(name: name, bankName: info.bankName, others: info.otherPaymentCount, all: all,
                                 onlyThis: onlyThis))
        case .bankName:
            guard info.ownName != nil else { return nil }
            let shopName = info.canRenameShop ? info.shopOwnName : nil
            let steps = (info.paymentOwnName == nil ? [] : [PaymentNameStep.payment("")])
                + (shopName == nil ? [] : [.shop("")])
            if let shopName, info.otherPaymentCount > 0 {
                let kept = PaymentNames.keptBankName(info.bankName)
                return .confirmBankName(BankNameQuestion(shopName: shopName, bankName: info.bankName,
                                                         count: info.otherPaymentCount + 1, steps: steps,
                                                         onlyThis: kept.isEmpty ? nil : [.payment(kept)]))
            }
            return .save(steps)
        }
    }
}

/// The name being edited on the payment's page (brief 47; brief 44's window before), on the payment's
/// `TransactionDetailStore` (its load, its busy state and errors, its save). `isDone` once a save went through: the page
/// shows the name again.
@MainActor @Observable
final class PaymentRenameModel {
    enum Work: Equatable { case save, bankName }

    /// The answers to "Use the bank's name for all N+1 payments?".
    enum BankNameAnswer: Equatable { case all, onlyThis, cancel }

    let store: TransactionDetailStore
    var text: String
    private(set) var question: RenamePlan.Question?
    private(set) var bankNameQuestion: RenamePlan.BankNameQuestion?
    /// The button whose work runs (it shows the spinner, the others are greyed).
    private(set) var working: Work?
    /// A save went through: the field closes.
    private(set) var isDone = false

    init(store: TransactionDetailStore) {
        self.store = store
        text = store.renameInfo.map { RenamePlan(info: $0).start } ?? ""
    }

    var plan: RenamePlan? { store.renameInfo.map(RenamePlan.init) }
    var intent: RenameIntent { plan?.intent(text) ?? .nothing }
    var canSave: Bool { !store.isSaving && intent != .nothing }
    /// Something typed would be lost (Cancel asks first).
    var hasChanges: Bool { PaymentNames.normalized(text) != PaymentNames.normalized(plan?.start ?? "") }
    var asks: Bool { question != nil || bankNameQuestion != nil }

    /// The field keeps at most what a name can hold (60 characters, `PaymentNames.maximumLength`).
    func limitText() {
        if text.count > PaymentNames.maximumLength { text = String(text.prefix(PaymentNames.maximumLength)) }
    }

    /// Save (Return, Done or the bar's Save). Nothing changed: the field just closes, as Return in a name field does.
    func save() async {
        guard !store.isSaving else { return }
        guard let outcome = plan?.outcome(intent) else {
            if intent == .nothing { isDone = true }
            return
        }
        await carry(outcome, work: intent == .bankName ? .bankName : .save)
    }

    func useBankName() async {
        guard !store.isSaving, let outcome = plan?.outcome(.bankName) else { return }
        await carry(outcome, work: .bankName)
    }

    /// The answer to "Also the other payments from <bank name>?": taken at once, so a dismissal that follows answers
    /// nothing twice.
    func answer(all: Bool) async {
        guard let question else { return }
        self.question = nil
        await run(all ? question.all : question.onlyThis, work: .save)
    }

    func answerBankName(_ answer: BankNameAnswer) async {
        guard let bankNameQuestion else { return }
        self.bankNameQuestion = nil
        switch answer {
        case .all: await run(bankNameQuestion.steps, work: .bankName)
        case .onlyThis: if let steps = bankNameQuestion.onlyThis { await run(steps, work: .bankName) }
        case .cancel: break
        }
    }

    private func carry(_ outcome: RenamePlan.Outcome, work: Work) async {
        switch outcome {
        case let .save(steps): await run(steps, work: work)
        case let .ask(question): self.question = question
        case let .confirmBankName(question): bankNameQuestion = question
        }
    }

    private func run(_ steps: [PaymentNameStep], work: Work) async {
        working = work
        defer { working = nil }
        await store.rename(steps)
        if store.saveError == nil { isDone = true }
    }
}

// MARK: - the name's page

/// A name's page on the dashboard's stack (`DashboardRoute.name`): the group's key and the name as the line or row that
/// opened it showed it (a group without an own name joins bank lines spelt differently).
nonisolated struct PaymentNameRoute: Hashable, Sendable {
    let key: String
    let title: String

    /// After a payment opened from this page was renamed: the page to show instead, or nil to stay. The page follows
    /// the payment when its own name has no payments left (its whole shop renamed), or when the same name is now spelt
    /// differently; a payment renamed alone just leaves the page.
    func following(_ payment: Transaction?, groups: [String: PaymentNameGroup]?) -> PaymentNameRoute? {
        guard let payment, let key = payment.nameKey, let groups else { return nil }
        if groups[self.key] != nil {
            guard key == self.key, payment.isOwnName == true, payment.place != title else { return nil }
            return PaymentNameRoute(key: key, title: payment.place)
        }
        guard groups[key] != nil else { return nil }
        return PaymentNameRoute(key: key, title: payment.place)
    }
}

/// What a name's page shows (`NameScreen`): the totals over every month, the months with payments as the category page
/// lists them (oldest first, its `ValueRow` bars), the graph over all the dashboard's months, and the payments newest
/// first under their months. The bars and the graph count the name's main side: money out, or money in for a name that
/// brought more in than it took (a salary).
nonisolated struct NamePage {
    struct MonthAmount: Identifiable {
        let month: Month
        let total: Double
        var id: String { month.key }
    }

    struct Section: Identifiable {
        let month: String
        let title: String
        let rows: [Transaction]
        var id: String { month }
    }

    let count: Int
    let moneyOut: Double
    let moneyIn: Double
    /// The bars and the graph show money out (else money in).
    let spends: Bool
    let months: [MonthAmount]
    let chart: [ChartPoint]
    let sections: [Section]
    /// The category most of the payments are in: the bars' and the graph's colour and icon.
    let category: Category
    /// "Feb 2026 – Oct 2026", or one month.
    let range: String

    init(group: PaymentNameGroup, dashboard: Dashboard, language: AppLanguage = .current) {
        count = group.count
        moneyOut = group.moneyOut
        moneyIn = group.moneyIn
        let spends = group.moneyOut >= group.moneyIn
        self.spends = spends
        let amount = { (amounts: PaymentNameAmounts?) in (spends ? amounts?.moneyOut : amounts?.moneyIn) ?? 0 }
        months = dashboard.months.compactMap { month in
            let total = amount(group.months[month.key])
            return total > 0 ? MonthAmount(month: month, total: total) : nil
        }
        chart = dashboard.months.enumerated().map { index, month in
            ChartPoint(index: index, label: month.shortTitle(language), value: amount(group.months[month.key]),
                       title: month.title(language))
        }
        let titles = Dictionary(dashboard.months.map { ($0.key, $0.title(language)) }, uniquingKeysWith: { first, _ in first })
        var sections: [Section] = []
        for row in group.rows {           // newest first already
            if sections.last?.month == row.month {
                let last = sections.removeLast()
                sections.append(Section(month: last.month, title: last.title, rows: last.rows + [row]))
            } else {
                sections.append(Section(month: row.month, title: titles[row.month] ?? row.month, rows: [row]))
            }
        }
        self.sections = sections
        category = Self.mostCommonCategory(group.rows, spends: spends, dashboard: dashboard)
        let first = group.rows.last.map(\.month), last = group.rows.first.map(\.month)
        range = [first, last].compactMap { $0 }.map { titles[$0] ?? $0 }.reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }.joined(separator: " – ")
    }

    /// The category most of the rows are in (ties: the newest row's), as the dashboard knows it.
    private static func mostCommonCategory(_ rows: [Transaction], spends: Bool, dashboard: Dashboard) -> Category {
        let names = rows.map { spends ? $0.categoryName : $0.incomeBuckets.first ?? $0.categoryName }
        var counts: [String: Int] = [:]
        for name in names { counts[name, default: 0] += 1 }
        let top = counts.values.max() ?? 0
        let chosen = names.first { counts[$0] == top }        // the rows are newest first: a tie goes to the newest
        let known = (dashboard.categories + dashboard.incomeBuckets).first { $0.name == chosen }
        return known ?? Category(name: chosen ?? "", icon: "Tag", color: "#9ca3af", kind: spends ? .spend : .income)
    }
}

/// The words of the name's page and the "All from" line, in the app's language.
nonisolated enum NameWording {
    /// "All from Penny" (the swipe's and the long press's VoiceOver name, the page's line, the menu item).
    static func allFrom(_ name: String, language: AppLanguage = .current) -> String {
        language.string("All from \(name)")
    }

    /// "23 payments · €412.30 spent", with "· €12.00 received" when money came in too.
    static func summary(count: Int, moneyOut: Double, moneyIn: Double, language: AppLanguage = .current) -> String {
        var parts = [language.string("\(count) payments")]
        if moneyOut > 0 || moneyIn == 0 {
            parts.append(language.string("\(Money.precise(moneyOut, language: language)) spent"))
        }
        if moneyIn > 0 { parts.append(language.string("\(Money.precise(moneyIn, language: language)) received")) }
        return parts.joined(separator: " · ")
    }

    static func summary(_ group: PaymentNameGroup, language: AppLanguage = .current) -> String {
        summary(count: group.count, moneyOut: group.moneyOut, moneyIn: group.moneyIn, language: language)
    }

    /// The name's page's heading line: "23 payments · Feb 2026 – Oct 2026".
    static func pageLine(count: Int, range: String, language: AppLanguage = .current) -> String {
        [language.string("\(count) payments"), range].filter { !$0.isEmpty }.joined(separator: " · ")
    }
}

#if DEBUG
extension PhoneSample {
    /// Screenshots (`-sampleNames`): the bakery named for its shop ("Corner bakery", all its payments, future ones too)
    /// and the newest restaurant visit named alone ("Anna's birthday"). Made up, like the sample's payments.
    static func addNames(_ phone: PhoneBackend) async throws {
        let payments = try await phone.ledger.payments().sorted { $0.bookingDate > $1.bookingDate }
        if let bakery = payments.first(where: { $0.place.localizedCaseInsensitiveContains("Baeckerei") }) {
            _ = try await phone.rename(id: bakery.id, name: "Corner bakery", scope: .shop)
        }
        if let dinner = payments.first(where: { $0.place.localizedCaseInsensitiveContains("Restaurant") }) {
            _ = try await phone.rename(id: dinner.id, name: "Anna's birthday", scope: .payment)
        }
    }
}
#endif

extension DashboardRoute {
    /// A name's page (brief 44); `category` and `side` are not used.
    init(name: PaymentNameRoute) {
        self.init(category: "", side: .expenses, name: name)
    }
}
