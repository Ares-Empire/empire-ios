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

    /// The window's question under the payment.
    static func question(direction: PaybackDirection, language: AppLanguage = .current) -> String {
        direction == .moneyOut ? language.string("Which payment paid this back?")
                               : language.string("Which expense does this pay back?")
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
/// more than `maximum`.
nonisolated struct PaybackPick: Equatable {
    let other: Transaction
    let maximum: Double
    let suggested: Double

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.other.id == rhs.other.id && lhs.maximum == rhs.maximum && lhs.suggested == rhs.suggested
    }

    /// From a suggestion: the most is the smaller of both rests.
    init(_ suggestion: PaybackSuggestion, rest: Double) {
        other = suggestion.transaction
        maximum = min(rest, suggestion.state.rest)
        suggested = min(suggestion.amount, maximum)
    }

    /// A link being changed: each end has its own rest plus the link's euros free.
    init(other: Transaction, linked: Double, rest: Double, otherRest: Double) {
        self.other = other
        let own = Paybacks.cents(linked) ?? 0
        maximum = Double(min((Paybacks.cents(rest) ?? 0) + own, (Paybacks.cents(otherRest) ?? 0) + own)) / 100
        suggested = linked
    }
}

/// A payment's links on its page (phone mode): whether it can take part and how much is still free (`state`, loaded
/// off the main thread when the page opens), the window that makes or changes a link, and the undo bar's offer after
/// any change. Every change saves once and rebuilds the dashboard once (`DashboardStore.setPayback`/`removePayback`);
/// the page then reads its payment again (`TransactionDetailStore.refresh`).
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

    /// The window that chooses the other payment, then the euros.
    func begin(detail: TransactionDetail) {
        guard let state, Paybacks.cents(state.rest) ?? 0 > 0 else { return }
        window = PaybackWindow(links: self, detail: detail, state: state, editing: nil)
    }

    /// The window at the euros of a link, with Remove.
    func edit(_ link: PaybackDetailLink, detail: TransactionDetail) {
        let direction: PaybackDirection = detail.amount < 0 ? .moneyOut : .moneyIn
        let state = state ?? PaybackState(direction: direction, rest: abs(detail.countedAmount))
        window = PaybackWindow(links: self, detail: detail, state: state, editing: link)
    }

    /// Sets (or changes) a link's euros; the undo bar says so.
    func set(_ ends: PaybackEnds, amount: Double, changing: Bool) async throws {
        let batch = try await dashboardStore.setPayback(from: ends.from, to: ends.to, amount: amount)
        offer(changing ? PaybackWording.changed(amount) : PaybackWording.linked(amount), batch)
    }

    /// Removes a link (the long press's Remove link, the window's); the undo bar brings it back.
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

/// The window from a payment's page (brief 203): the other payment chosen from the suggestions (brief 202's ranking:
/// what fits first, then the nearest days) or found by name, then the euros, then Link. Changing a link opens it at the
/// euros, with Remove link.
@MainActor @Observable
final class PaybackWindow: Identifiable {
    let id = UUID()
    /// This payment's side: money in chooses an expense, money out a payment in.
    let direction: PaybackDirection
    /// This payment as its page shows it (the window's heading).
    let payment: TransactionDetail
    /// Euros still free on this payment.
    let rest: Double
    /// The link being changed; nil while a new one is made.
    let editing: PaybackDetailLink?
    /// The suggestions, once loaded.
    private(set) var suggestions: [PaybackSuggestion]?
    var query = ""
    /// The search's results for `resultsQuery`.
    private(set) var results: [PaybackSuggestion]?
    private(set) var resultsQuery = ""
    /// The other payment and its euros: the amount step.
    private(set) var pick: PaybackPick?
    /// The amount step is pushed over the choice (a new link); a link being changed starts there.
    var showsAmount = false
    var amountText = ""
    private(set) var isWorking = false
    /// Why the save or the removal did not go through.
    private(set) var problem: String?
    @ObservationIgnored private weak var links: PaybackLinks?

    init(links: PaybackLinks, detail: TransactionDetail, state: PaybackState, editing: PaybackDetailLink?) {
        self.links = links
        payment = detail
        direction = state.direction
        rest = state.rest
        self.editing = editing
    }

    var isEditing: Bool { editing != nil }

    /// What was typed, checked against the most this link can take.
    var check: PaybackAmountCheck { PaybackAmountCheck(amountText, maximum: pick?.maximum ?? 0) }
    var canConfirm: Bool {
        guard !isWorking, pick != nil, let amount = check.amount else { return false }
        return editing.map { Paybacks.cents($0.linkedAmount) != Paybacks.cents(amount) } ?? true
    }

    /// The suggestions (a new link), or the link's other payment and how much both ends have free (a change).
    func load() async {
        guard let store = links?.dashboardStore else { return }
        if let editing {
            guard pick == nil, let other = store.bankPayment(editing.payment) else { return }
            let otherRest = (try? await store.paybackState(for: editing.payment))?.rest ?? 0
            let pick = PaybackPick(other: other, linked: editing.linkedAmount, rest: rest, otherRest: otherRest)
            self.pick = pick
            if amountText.isEmpty { amountText = ReceiptAmount.field(pick.suggested) }
            return
        }
        guard suggestions == nil else { return }
        suggestions = (try? await store.paybackSuggestions(for: payment.id)) ?? []
    }

    /// The search for what is typed now (the field waits a moment after the last key).
    func search() async {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else {
            results = nil
            resultsQuery = ""
            return
        }
        let found = (try? await links?.dashboardStore.paybackSearch(typed, for: payment.id)) ?? []
        guard query.trimmingCharacters(in: .whitespacesAndNewlines) == typed else { return }
        results = found
        resultsQuery = typed
    }

    /// A suggestion or result tapped: the amount step, its euros filled in.
    func choose(_ suggestion: PaybackSuggestion) {
        let pick = PaybackPick(suggestion, rest: rest)
        self.pick = pick
        amountText = ReceiptAmount.field(pick.suggested)
        problem = nil
        showsAmount = true
    }

    /// Link (or Save while a link is changed): the window closes, the undo bar on the page says what happened. False
    /// when it did not go through (the window says why).
    @discardableResult
    func confirm() async -> Bool {
        guard canConfirm, let pick, let amount = check.amount, let links else { return false }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            #if DEBUG
            await DebugLaunch.holdWork()
            #endif
            try await links.set(PaybackEnds(payment: payment.id, direction: direction, other: pick.other.id),
                               amount: amount, changing: isEditing)
            links.window = nil
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// Remove link (a link being changed).
    func remove() async {
        guard let editing, let links, !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        await links.remove(editing, direction: direction)
        links.window = nil
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
