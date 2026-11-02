import Foundation
import Observation
import os

// Money paid back on screen (brief 203; the engine is brief 201, the data and the API brief 202, `Paybacks.swift`): a
// payment that came in pays back a payment that went out, all of it or a part, because the person linked them by hand
// from either payment's page. Those euros come off the expense and are not income. Wholly optional (Patrik,
// 2026-11-02): one quiet action on a payment's page and one tour step; no prompts, badges or offers anywhere else.
// This file decides what the screens say and does what their buttons ask; the look is `Screens/PaybackScreens.swift`.

/// The words of paying back, in the app's language (pure, so tests pin them in both).
nonisolated enum PaybackWording {
    /// The page's quiet action: the first link, or another one while the payment still has euros free.
    static func action(direction: PaybackDirection, linked: Bool, language: AppLanguage = .current) -> String {
        switch (direction, linked) {
        case (.moneyIn, false): language.string("Pays back an expense…")
        case (.moneyOut, false): language.string("Paid back to you…")
        case (.moneyIn, true): language.string("Also pays back…")
        case (.moneyOut, true): language.string("Also paid back by…")
        }
    }

    /// The section's heading over a payment's links: what came back to an expense, what a payment in pays back.
    static func heading(direction: PaybackDirection, language: AppLanguage = .current) -> String {
        direction == .moneyOut ? language.string("Paid back") : language.string("Pays back")
    }

    /// Under the links: what still counts. An expense counts its share, a payment in its rest as income.
    static func summary(direction: PaybackDirection, counted: Double, language: AppLanguage = .current) -> String {
        let left = abs(counted)
        let euros = Money.precise(left, language: language)
        switch direction {
        case .moneyOut:
            return left > 0 ? language.string("Your share, \(euros), counts as spent.")
                            : language.string("Paid back in full: none of it counts as spent.")
        case .moneyIn:
            return left > 0 ? language.string("The rest, \(euros), counts as income.")
                            : language.string("None of it counts as income.")
        }
    }

    /// What fits between a suggestion and the payment: "half" / "die Hälfte", "in full" / "ganz", …
    static func fit(_ fit: PaybackFit, language: AppLanguage = .current) -> String {
        switch fit {
        case .whole: language.string("in full")
        case .half: language.string("half")
        case .third: language.string("a third")
        case .quarter: language.string("a quarter")
        case .rest: language.string("the rest")
        }
    }

    /// A day as the link cards and the window's rows write it: "29 Oct" / "29. Okt.", with the year when it is not
    /// `now`'s.
    static func day(_ value: String, now: Date = .now, language: AppLanguage = .current) -> String {
        guard let date = WidgetFormatting.date(String(value.prefix(10))) else { return value }
        let calendar = WidgetFormatting.calendar
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                     timeZone: calendar.timeZone).day().month(.abbreviated)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        return date.formatted(style)
    }

    /// A link card's quiet line: the other payment's day and its own amount, "29 Oct · +80.00".
    static func linkLine(_ link: PaybackDetailLink, now: Date = .now, language: AppLanguage = .current) -> String {
        day(link.date, now: now, language: language) + " · " + Money.transaction(link.amount, language: language)
    }

    /// VoiceOver's reading of a link card: "Max Mustermann, 29 Oct, €64.00 paid back".
    static func spokenLink(_ link: PaybackDetailLink, direction: PaybackDirection, now: Date = .now,
                           language: AppLanguage = .current) -> String {
        let euros = Money.precise(link.linkedAmount, language: language)
        let what = direction == .moneyOut ? language.string("\(euros) paid back") : language.string("pays back \(euros)")
        return [link.place, day(link.date, now: now, language: language), what].joined(separator: ", ")
    }

    // MARK: the window

    /// The window's bar title: an expense chooses who paid it back, a payment in what it pays back.
    static func windowTitle(direction: PaybackDirection, language: AppLanguage = .current) -> String {
        direction == .moneyOut ? language.string("Paid back by") : language.string("Pays back")
    }

    /// The window's question under the payment (or the payments): in the plural, since several can be ticked on the other
    /// side (brief 206), which reads naturally for one too.
    static func question(direction: PaybackDirection, several: Bool = false, language: AppLanguage = .current) -> String {
        switch (direction, several) {
        case (.moneyOut, false): language.string("Which payments paid this back?")
        case (.moneyOut, true): language.string("Which payments paid these back?")
        case (.moneyIn, false): language.string("Which expenses does this pay back?")
        case (.moneyIn, true): language.string("Which expenses do these pay back?")
        }
    }

    /// A group's title in the window: "3 expenses" / "3 Ausgaben", "2 payments in" / "2 Einnahmen".
    static func groupTitle(count: Int, direction: PaybackDirection, language: AppLanguage = .current) -> String {
        direction == .moneyOut ? language.string("\(count) expenses") : language.string("\(count) payments in")
    }

    /// The one quiet line under a group's heading: what of the selection cannot take part, and why. Nil when nothing was
    /// left out. "Left out: 1 receipt, 2 transfers." / "Nicht dabei: 1 Beleg, 2 Umbuchungen."
    static func leftOut(_ skipped: PaybackSkipped, direction: PaybackDirection,
                        language: AppLanguage = .current) -> String? {
        var parts: [String] = []
        if skipped.receipts > 0 { parts.append(language.string("\(skipped.receipts) receipts")) }
        if skipped.cashEntries > 0 { parts.append(language.string("\(skipped.cashEntries) cash entries")) }
        if skipped.transfers > 0 { parts.append(language.string("\(skipped.transfers) transfers")) }
        if skipped.withdrawals > 0 { parts.append(language.string("\(skipped.withdrawals) withdrawals")) }
        if skipped.otherCurrencies > 0 {
            parts.append(language.string("\(skipped.otherCurrencies) in another currency"))
        }
        if skipped.nothingLeft > 0 {
            parts.append(direction == .moneyOut ? language.string("\(skipped.nothingLeft) paid back in full")
                                                : language.string("\(skipped.nothingLeft) used in full"))
        }
        guard !parts.isEmpty else { return nil }
        return language.string("Left out: \(parts.joined(separator: ", ")).")
    }

    /// A choice's quiet line when part of it is linked already: what it has free ("€30.00 left").
    static func free(_ amount: Double, language: AppLanguage = .current) -> String {
        language.string("\(Money.precise(amount, language: language)) left")
    }

    /// How the money goes, an expense's quiet line: its day, then "in full" or what stays open ("15 Oct · €36.00 still
    /// open").
    static func planLine(_ allocation: PaybackAllocation, date: String, now: Date = .now,
                         language: AppLanguage = .current) -> String {
        let day = day(date, now: now, language: language)
        guard Paybacks.cents(allocation.rest) ?? 0 > 0 else { return day + " · " + fit(.whole, language: language) }
        return day + " · " + language.string("\(Money.precise(allocation.rest, language: language)) still open")
    }

    /// The amount step's line under the most it can take: what the typed euros leave open on the expense and as income on
    /// the payment in (brief 205's words), nil when they leave nothing. "€64.00 still open. €36.00 stays income."
    static func afterAmount(open: Double, income: Double, language: AppLanguage = .current) -> String? {
        var parts: [String] = []
        if Paybacks.cents(open) ?? 0 > 0 { parts.append(PaybackGroupWording.open(open, language: language)) }
        if Paybacks.cents(income) ?? 0 > 0 { parts.append(PaybackGroupWording.income(income, language: language)) }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func suggestedHeading(language: AppLanguage = .current) -> String { language.string("Suggested") }

    /// No suggestion: close by in time nothing fits; the search finds the rest.
    static func noSuggestion(language: AppLanguage = .current) -> String {
        language.string("Nothing close by fits. Search by name.")
    }

    static func noMatch(_ query: String, language: AppLanguage = .current) -> String {
        language.string("No payment found for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”.")
    }

    /// A suggestion's or result's quiet line: its day, and what fits when something does ("29 Oct · half").
    static func choiceLine(_ suggestion: PaybackSuggestion, now: Date = .now, language: AppLanguage = .current) -> String {
        let day = day(suggestion.transaction.date, now: now, language: language)
        return suggestion.fit.map { day + " · " + fit($0, language: language) } ?? day
    }

    /// The amount step: always about the expense's euros.
    static func amountQuestion(language: AppLanguage = .current) -> String {
        language.string("How much of it was paid back?")
    }

    static func maximum(_ maximum: Double, language: AppLanguage = .current) -> String {
        language.string("At most \(Money.precise(maximum, language: language)).")
    }

    // MARK: the undo bar

    static func linked(_ amount: Double, language: AppLanguage = .current) -> String {
        language.string("Linked: \(Money.precise(amount, language: language)) paid back.")
    }

    static func changed(_ amount: Double, language: AppLanguage = .current) -> String {
        language.string("Changed to \(Money.precise(amount, language: language)).")
    }

    static func removed(language: AppLanguage = .current) -> String { language.string("Link removed.") }

    // MARK: the lists

    /// A list row's number: what counts there (`countedAmount`), so a list's rows add up to its total. A payment that
    /// counts nothing any more (wholly paid back, or wholly used to pay back) reads "0.00", without a sign.
    static func rowAmount(_ transaction: Transaction, language: AppLanguage = .current) -> String {
        let counted = transaction.countedAmount
        guard Paybacks.cents(abs(counted)) != 0 else { return String(Money.transaction(0, language: language).dropFirst()) }
        return Money.transaction(counted, language: language)
    }

    /// Whether the row's number is a counted 0 (drawn quiet).
    static func countsNothing(_ transaction: Transaction) -> Bool {
        transaction.counted != nil && Paybacks.cents(abs(transaction.countedAmount)) == 0
    }

    /// A list row's quiet line when a link changes what it counts: why the number differs from the bank's.
    /// An expense: "€128.00 · €64.00 back"; a payment in: "€64.00 · pays back Fiktiv Ferienhaus" (or "… 2 expenses").
    /// nil without a link. `name` gives the shown name of a payment by its id.
    static func rowLine(_ transaction: Transaction, name: (String) -> String?, language: AppLanguage = .current) -> String? {
        let original = Money.precise(abs(transaction.amount), language: language)
        if transaction.amount < 0, let back = transaction.paidBack, back > 0 {
            return original + " · " + language.string("\(Money.precise(back, language: language)) back")
        }
        if transaction.amount > 0, let links = transaction.paysBack, !links.isEmpty {
            if links.count == 1, let other = name(links[0].payment) {
                return original + " · " + language.string("pays back \(other)")
            }
            return original + " · " + language.string("pays back \(links.count) expenses")
        }
        return nil
    }

    /// A summed row's addition to its days (brief 53's row), when links change what its payments count: "€64.00 back"
    /// on money out, "€64.00 not income" on money in. nil when they count as the bank booked them.
    static func summedLine(original: Double, counted: Double, language: AppLanguage = .current) -> String? {
        let difference = (Paybacks.cents(abs(original)) ?? 0) - (Paybacks.cents(abs(counted)) ?? 0)
        guard difference > 0 else { return nil }
        let euros = Money.precise(Double(difference) / 100, language: language)
        return original < 0 ? language.string("\(euros) back") : language.string("\(euros) not income")
    }

    /// The pen beside a link card, and the long press's entries.
    static func changeLink(language: AppLanguage = .current) -> String { language.string("Change link") }
}

/// What the payment's page shows of paying back (pure): the links with their heading and what still counts, and the
/// quiet action while the payment has euros free. Nothing at all where it cannot take part (`state` nil, no links).
struct PaybackSectionContent: Equatable {
    let direction: PaybackDirection
    let heading: String?
    let links: [PaybackDetailLink]
    let summary: String?
    let action: String?

    init(detail: TransactionDetail, state: PaybackState?, language: AppLanguage = .current) {
        let direction: PaybackDirection = detail.amount < 0 ? .moneyOut : .moneyIn
        self.direction = direction
        links = (direction == .moneyOut ? detail.paidBackBy : detail.paysBack) ?? []
        heading = links.isEmpty ? nil : PaybackWording.heading(direction: direction, language: language)
        summary = links.isEmpty ? nil
            : PaybackWording.summary(direction: direction, counted: detail.countedAmount, language: language)
        if let state, state.direction == direction, Paybacks.cents(state.rest) ?? 0 > 0 {
            action = PaybackWording.action(direction: direction, linked: !links.isEmpty, language: language)
        } else {
            action = nil
        }
    }

    var isEmpty: Bool { links.isEmpty && action == nil }
}

/// The two ends of a link: `from` the payment that came in, `to` the expense, whichever page the person starts on.
nonisolated struct PaybackEnds: Equatable, Sendable {
    let from: String
    let to: String

    init(payment: String, direction: PaybackDirection, other: String) {
        from = direction == .moneyIn ? payment : other
        to = direction == .moneyIn ? other : payment
    }
}

/// What was typed as the link's euros, checked against the most it can take.
nonisolated enum PaybackAmountCheck: Equatable {
    case empty
    case ok(Double)
    /// More than either payment has free.
    case tooMuch

    init(_ text: String, maximum: Double) {
        guard let typed = ReceiptAmount.typed(text), let cents = Paybacks.cents(typed), cents > 0 else {
            self = .empty
            return
        }
        self = cents <= (Paybacks.cents(maximum) ?? 0) ? .ok(Double(cents) / 100) : .tooMuch
    }

    var amount: Double? { if case let .ok(value) = self { value } else { nil } }
}

/// The other payment of a link being made or changed, and the euros: the suggestion's (else the smaller rest), never
/// more than `maximum`. Each end's euros free are kept apart, so the amount step can say what the typed euros leave open
/// on the expense and as income on the payment in (brief 206).
nonisolated struct PaybackPick: Equatable {
    let other: Transaction
    /// What the expense can still get back, and what the payment in can still give (each with the link's own euros while
    /// it is changed).
    let expenseFree: Double
    let incomeFree: Double
    let suggested: Double
    /// The most this link can take: the smaller of both.
    var maximum: Double { min(expenseFree, incomeFree) }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.other.id == rhs.other.id && lhs.expenseFree == rhs.expenseFree && lhs.incomeFree == rhs.incomeFree
            && lhs.suggested == rhs.suggested
    }

    /// From a suggestion (`rest`: this payment's euros free).
    init(_ suggestion: PaybackSuggestion, rest: Double) {
        other = suggestion.transaction
        let otherIsExpense = suggestion.state.direction == .moneyOut
        expenseFree = otherIsExpense ? suggestion.state.rest : rest
        incomeFree = otherIsExpense ? rest : suggestion.state.rest
        suggested = min(suggestion.amount, expenseFree, incomeFree)
    }

    /// A link being changed: each end has its own rest plus the link's euros free. `direction`: this payment's side.
    init(other: Transaction, direction: PaybackDirection, linked: Double, rest: Double, otherRest: Double) {
        self.other = other
        let own = Paybacks.cents(linked) ?? 0
        let mine = Double((Paybacks.cents(rest) ?? 0) + own) / 100
        let theirs = Double((Paybacks.cents(otherRest) ?? 0) + own) / 100
        expenseFree = direction == .moneyOut ? mine : theirs
        incomeFree = direction == .moneyOut ? theirs : mine
        suggested = linked
    }

    /// What stays open on the expense and stays income on the payment in once `amount` is linked (whole cents).
    func left(after amount: Double) -> (open: Double, income: Double) {
        let linked = Paybacks.cents(amount) ?? 0
        return (Double(max(0, (Paybacks.cents(expenseFree) ?? 0) - linked)) / 100,
                Double(max(0, (Paybacks.cents(incomeFree) ?? 0) - linked)) / 100)
    }
}

/// The window's heading (brief 206): one payment's name and its own amount, as brief 203's window showed it, or a group's
/// count and the euros it can still be paid back or pay back, signed as a payment ("3 expenses", "−240.00", which are
/// the euros its rows count in the list), with what of a selection was left out in one quiet line.
struct PaybackHeading: Equatable {
    let title: String
    let amount: String
    let isExpense: Bool
    let leftOut: String?

    init(detail: TransactionDetail) {
        title = detail.place
        amount = detail.signedAmount
        isExpense = detail.amount < 0
        leftOut = nil
    }

    init(group: PaybackGroup, language: AppLanguage = .current) {
        isExpense = group.direction == .moneyOut
        if group.payments.count == 1, let only = group.payments.first?.transaction {
            title = only.place
            amount = Money.transaction(only.amount, language: language)
        } else {
            title = PaybackWording.groupTitle(count: group.payments.count, direction: group.direction, language: language)
            amount = Money.transaction(isExpense ? -group.totalRest : group.totalRest, language: language)
        }
        leftOut = PaybackWording.leftOut(group.skipped, direction: group.direction, language: language)
    }
}

/// How the money goes, before Link (brief 206; pure): brief 205's plan read as the window shows it. Each expense in the
/// order the euros reach it (oldest first) with what it gets back and its day and what stays open ("in full" when
/// nothing does), then brief 205's sentence ("3 expenses, €100.00 paid back.") and what stays open or stays income.
struct PaybackPlanSummary: Equatable {
    struct Row: Equatable, Identifiable {
        let id: String
        let name: String
        /// The euros this expense gets back in this linking (0 when the money ran out before it).
        let amount: Double
        let line: String
        /// VoiceOver's reading: "Pizzeria Fiktivo, 3 Oct · in full, €48.00 back".
        let spoken: String
    }

    let rows: [Row]
    let paidBack: String
    /// "€36.00 still open." or "€20.00 stays income." (never both: the euros are poured until one side runs out).
    let left: String?

    /// `transactions`: the payments of both sides by id (the group's and the ticked ones).
    init(plan: PaybackPlan, transactions: [String: Transaction], now: Date = .now, language: AppLanguage = .current) {
        rows = plan.expenses.map { allocation in
            let transaction = transactions[allocation.id]
            let name = transaction?.place ?? ""
            let line = PaybackWording.planLine(allocation, date: transaction?.date ?? "", now: now, language: language)
            let back = language.string("\(Money.precise(allocation.amount, language: language)) back")
            return Row(id: allocation.id, name: name, amount: allocation.amount, line: line,
                       spoken: [name, line, back].joined(separator: ", "))
        }
        paidBack = PaybackGroupWording.summary(expenses: plan.expenseCount, linked: plan.linked, stillOpen: 0,
                                               staysIncome: 0, language: language)
        if Paybacks.cents(plan.stillOpen) ?? 0 > 0 {
            left = PaybackGroupWording.open(plan.stillOpen, language: language)
        } else if Paybacks.cents(plan.staysIncome) ?? 0 > 0 {
            left = PaybackGroupWording.income(plan.staysIncome, language: language)
        } else {
            left = nil
        }
    }
}

/// A payment's links on its page (phone mode): whether it can take part and how much is still free (`state`, loaded
/// off the main thread when the page opens), the window that makes or changes a link, and the undo bar's offer after
/// any change. Every change saves once and rebuilds the dashboard once (`DashboardStore.setPayback`/`setPaybacks`/
/// `removePayback`); the page then reads its payment again (`TransactionDetailStore.refresh`).
@MainActor @Observable
final class PaybackLinks {
    /// Nil while it loads, in server mode, and where the payment cannot take part (a transfer, a withdrawal, a receipt,
    /// another currency).
    private(set) var state: PaybackState?
    private(set) var isLoaded = false
    /// The window while it is open.
    var window: PaybackWindow?
    /// What the last change did, with Undo.
    var undo: UndoOffer?
    private(set) var isWorking = false
    @ObservationIgnored let paymentID: String
    @ObservationIgnored let dashboardStore: DashboardStore
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "paybacks")

    init(paymentID: String, dashboardStore: DashboardStore) {
        self.paymentID = paymentID
        self.dashboardStore = dashboardStore
    }

    /// Reads the state (the candidates are built in the ledger, off the main thread). Its time goes to the log.
    func load() async {
        guard dashboardStore.phone != nil else {
            isLoaded = true
            return
        }
        let clock = ContinuousClock(), start = clock.now
        let loaded = try? await dashboardStore.paybackState(for: paymentID)
        if loaded != state { state = loaded }
        isLoaded = true
        let elapsed = clock.now - start
        let milliseconds = Double(elapsed.components.seconds) * 1000 + Double(elapsed.components.attoseconds) / 1e15
        Self.log.debug("payback state in \(milliseconds, format: .fixed(precision: 1), privacy: .public) ms")
    }

    /// The window that chooses the other payment (one or several, brief 206), then the euros.
    func begin(detail: TransactionDetail) {
        guard let state, Paybacks.cents(state.rest) ?? 0 > 0 else { return }
        window = PaybackWindow(store: dashboardStore, detail: detail, state: state, editing: nil, done: finished)
    }

    /// The window at the euros of a link, with Remove.
    func edit(_ link: PaybackDetailLink, detail: TransactionDetail) {
        let direction: PaybackDirection = detail.amount < 0 ? .moneyOut : .moneyIn
        let state = state ?? PaybackState(direction: direction, rest: abs(detail.countedAmount))
        window = PaybackWindow(store: dashboardStore, detail: detail, state: state, editing: link, done: finished)
    }

    /// Removes a link (the long press's Remove link); the undo bar brings it back.
    func remove(_ link: PaybackDetailLink, direction: PaybackDirection) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            let ends = PaybackEnds(payment: paymentID, direction: direction, other: link.payment)
            let batch = try await dashboardStore.removePayback(from: ends.from, to: ends.to)
            offer(PaybackWording.removed(), batch)
        } catch {
            undo = UndoOffer(message: error.localizedDescription)
        }
    }

    /// The window made, changed or removed links: it closes, and the undo bar on the page says what happened.
    private var finished: @MainActor (String, BatchUndo) -> Void {
        { [weak self] message, batch in
            self?.window = nil
            self?.offer(message, batch)
        }
    }

    private func offer(_ message: String, _ batch: BatchUndo) {
        undo = UndoOffer(message: message) { [weak self] in
            do {
                let outcome = try await batch.perform()
                if outcome == .unavailable { self?.undo = UndoOffer(message: outcome.message) }
            } catch {
                self?.undo = UndoOffer(message: error.localizedDescription)
            }
        }
    }
}

/// The one window of money paid back (brief 203, grown in brief 206), from a payment's page or from a selection's bar:
/// this side's payments at the top (one, or a group), the other side chosen from the suggestions (brief 205's ranking:
/// what fits the group first, then the nearest days) or found by name, **several ticked** if need be. While anything is
/// ticked the window shows how the money goes (`plan`, brief 205's pouring, oldest first). One payment on each side
/// keeps brief 203's amount step (Next, the typed euros, Link); with several on either side Link pours them
/// (`setPaybacks`, one undo for all). Changing a link opens it at the euros, with Remove link. When it is done the owner
/// gets the undo bar's line and its undo (`done`) and closes the window.
@MainActor @Observable
final class PaybackWindow: Identifiable {
    let id = UUID()
    /// This side: money out chooses payments in, money in chooses expenses.
    let direction: PaybackDirection
    let heading: PaybackHeading
    /// The payment's page this window was opened from (the amount step's own payment); nil from a selection.
    let payment: TransactionDetail?
    /// The link being changed; nil while new ones are made.
    let editing: PaybackDetailLink?
    /// This side's payments that take part: given by a selection, read for a payment's page as the window loads.
    private(set) var group: PaybackGroup?
    /// The suggestions, once loaded.
    private(set) var suggestions: [PaybackSuggestion]?
    var query = ""
    /// The search's results for `resultsQuery`.
    private(set) var results: [PaybackSuggestion]?
    private(set) var resultsQuery = ""
    /// The other side's payments ticked, in the order they were ticked.
    private(set) var ticked: [PaybackSuggestion] = []
    /// The other payment and its euros: the amount step (one payment on each side, or a link being changed).
    private(set) var pick: PaybackPick?
    /// The amount step is pushed over the choice (Next); a link being changed starts there.
    var showsAmount = false
    var amountText = ""
    private(set) var isWorking = false
    /// Why the link, the save or the removal did not go through.
    private(set) var problem: String?
    @ObservationIgnored let store: DashboardStore
    /// This side's one payment (its page, or a selection of one): the link's own end in the amount step.
    @ObservationIgnored private let ownID: String?
    /// Euros still free on that one payment.
    @ObservationIgnored private let ownRest: Double?
    @ObservationIgnored private let done: @MainActor (String, BatchUndo) -> Void

    /// From a payment's page (brief 203): its group of one is read as the window loads.
    init(store: DashboardStore, detail: TransactionDetail, state: PaybackState, editing: PaybackDetailLink?,
         done: @escaping @MainActor (String, BatchUndo) -> Void) {
        self.store = store
        payment = detail
        direction = state.direction
        heading = PaybackHeading(detail: detail)
        self.editing = editing
        ownID = detail.id
        ownRest = state.rest
        self.done = done
    }

    /// From a selection (brief 206): its group, read as the bar's item was tapped.
    init(store: DashboardStore, group: PaybackGroup, done: @escaping @MainActor (String, BatchUndo) -> Void) {
        self.store = store
        payment = nil
        direction = group.direction
        heading = PaybackHeading(group: group)
        editing = nil
        self.group = group
        let one = group.payments.count == 1 ? group.payments.first : nil
        ownID = one?.transaction.id
        ownRest = one?.state.rest
        self.done = done
    }

    var isEditing: Bool { editing != nil }

    /// More than one payment on this side (a group from a selection): the question says "these".
    var isSeveral: Bool { ownID == nil }

    /// One payment on this side and at most one ticked: the bar's button is Next, to the typed euros (brief 203's
    /// amount step); otherwise it is Link, which pours.
    var confirmsByAmount: Bool { ownID != nil && ticked.count <= 1 }

    func isTicked(_ id: String) -> Bool { ticked.contains { $0.id == id } }

    /// What shows while nothing is typed: the ticked payments the suggestions do not hold (found by the search), then the
    /// suggestions. Nil while they load.
    var choices: [PaybackSuggestion]? {
        guard let suggestions else { return nil }
        let suggested = Set(suggestions.map(\.id))
        return ticked.filter { !suggested.contains($0.id) } + suggestions
    }

    /// How the money would go with what is ticked (pure: the rests the window read; Link plans again under the save
    /// revision). Nil while nothing is ticked.
    var plan: PaybackPlan? {
        guard let group, !ticked.isEmpty else { return nil }
        return try? PaybackPlan(group: group, others: ticked.map {
            PaybackCandidate(transaction: $0.transaction, state: $0.state, names: [])
        })
    }

    /// The plan as the window shows it.
    var summary: PaybackPlanSummary? {
        guard let plan, let group else { return nil }
        var transactions = Dictionary(uniqueKeysWithValues: group.payments.map { ($0.transaction.id, $0.transaction) })
        for suggestion in ticked { transactions[suggestion.id] = suggestion.transaction }
        return PaybackPlanSummary(plan: plan, transactions: transactions)
    }

    var canNext: Bool { !isWorking && confirmsByAmount && ticked.count == 1 }
    var canLink: Bool { !isWorking && !confirmsByAmount && group?.revision != nil && plan?.hasLinks == true }

    /// What was typed, checked against the most this link can take.
    var check: PaybackAmountCheck { PaybackAmountCheck(amountText, maximum: pick?.maximum ?? 0) }
    var canConfirm: Bool {
        guard !isWorking, pick != nil, let amount = check.amount else { return false }
        return editing.map { Paybacks.cents($0.linkedAmount) != Paybacks.cents(amount) } ?? true
    }

    /// The amount step's line under the most it can take: what the typed euros leave open and as income.
    var afterAmount: String? {
        guard let pick, let amount = check.amount else { return nil }
        let left = pick.left(after: amount)
        return PaybackWording.afterAmount(open: left.open, income: left.income)
    }

    /// The suggestions (new links: this payment's group read first when the window comes from its page), or the link's
    /// other payment and how much both ends have free (a change).
    func load() async {
        if let editing {
            guard pick == nil, let ownRest, let other = store.bankPayment(editing.payment) else { return }
            let otherRest = (try? await store.paybackState(for: editing.payment))?.rest ?? 0
            let pick = PaybackPick(other: other, direction: direction, linked: editing.linkedAmount, rest: ownRest,
                                   otherRest: otherRest)
            self.pick = pick
            if amountText.isEmpty { amountText = ReceiptAmount.field(pick.suggested) }
            return
        }
        guard suggestions == nil else { return }
        if group == nil, let ownID { group = try? await store.paybackGroup(ids: [ownID]) }
        guard let group else {
            suggestions = []
            return
        }
        suggestions = (try? await store.paybackSuggestions(forGroup: group)) ?? []
    }

    /// The search for what is typed now (the field waits a moment after the last key).
    func search() async {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            results = nil
            resultsQuery = ""
            return
        }
        guard let group else { return }
        let found = (try? await store.paybackSearch(typed, forGroup: group)) ?? []
        guard query.trimmingCharacters(in: .whitespacesAndNewlines) == typed else { return }
        results = found
        resultsQuery = typed
    }

    /// A tap on a suggestion or result: ticked, or unticked.
    func toggle(_ suggestion: PaybackSuggestion) {
        if let index = ticked.firstIndex(where: { $0.id == suggestion.id }) { ticked.remove(at: index) }
        else { ticked.append(suggestion) }
        problem = nil
    }

    /// Next (one payment on each side): the amount step, the suggestion's euros filled in.
    func next() {
        guard canNext, let ownRest, let suggestion = ticked.first else { return }
        let pick = PaybackPick(suggestion, rest: ownRest)
        self.pick = pick
        amountText = ReceiptAmount.field(pick.suggested)
        problem = nil
        showsAmount = true
    }

    /// Link with several on either side: the euros poured as the summary showed, planned again under the save revision
    /// (a change meanwhile refuses), one save and one undo. False when it did not go through (the window says why).
    @discardableResult
    func link() async -> Bool {
        guard canLink, let group else { return false }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            #if DEBUG
            await DebugLaunch.holdWork()
            #endif
            let result = try await store.setPaybacks(group: group, others: Set(ticked.map(\.id)))
            done(result.message, result.undo)
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// Link (or Save while a link is changed) in the amount step: the typed euros. False when it did not go through.
    @discardableResult
    func confirm() async -> Bool {
        guard canConfirm, let pick, let amount = check.amount, let ownID else { return false }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            #if DEBUG
            await DebugLaunch.holdWork()
            #endif
            let ends = PaybackEnds(payment: ownID, direction: direction, other: pick.other.id)
            let batch = try await store.setPayback(from: ends.from, to: ends.to, amount: amount)
            done(isEditing ? PaybackWording.changed(amount) : PaybackWording.linked(amount), batch)
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// Remove link (a link being changed).
    func remove() async {
        guard let editing, let ownID, !isWorking else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            let ends = PaybackEnds(payment: ownID, direction: direction, other: editing.payment)
            let batch = try await store.removePayback(from: ends.from, to: ends.to)
            done(PaybackWording.removed(), batch)
        } catch {
            problem = error.localizedDescription
        }
    }

    #if DEBUG
    /// Screenshots: types what a person would.
    func debugType(_ text: String) { amountText = text }
    #endif
}

extension DashboardStore {
    /// A bank payment's row by its id (not a receipt's, a cash entry's or a withdrawal's covered row): a link's other end.
    func bankPayment(_ id: String) -> Transaction? {
        dashboard?.transactions.first { $0.id == id && $0.receiptId == nil && $0.coveredBy == nil }
    }

    /// The shown name of the expense a payment in pays back (a list row's line), looked up once per dashboard.
    func paybackName(_ id: String) -> String? {
        if builtPaybackNames.revision != revision {
            let ids = Set((dashboard?.transactions ?? []).flatMap { ($0.paysBack ?? []).map(\.payment) })
            var names: [String: String] = [:]
            for row in dashboard?.transactions ?? [] where ids.contains(row.id) && row.receiptId == nil
                && row.coveredBy == nil { names[row.id] = row.place }
            builtPaybackNames = PaybackNamesCache(revision: revision, names: names)
        }
        return builtPaybackNames.names[id]
    }
}

/// The names of the expenses payments in pay back, for the dashboard they were read from.
struct PaybackNamesCache {
    var revision = -1
    var names: [String: String] = [:]
}
