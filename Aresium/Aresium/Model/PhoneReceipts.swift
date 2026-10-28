import Foundation

// Receipts in phone mode (brief 31 part B): reading, keeping, joining to the bank payment, and what the dashboard gets.
// The rules are D8's (ares-empire/docs/ARESIUM-FOR-OTHERS.md → part 6) and the engine's (`readReceipt`, `matchReceipt`,
// `buildDashboardSource`): only an exact single match joins by itself; every other candidate is asked.

/// What the check window saves.
nonisolated struct ReceiptDraft: Equatable, Sendable {
    var date: String
    var time: String?
    var shop: String?
    var total: Double
    var currency: String
    /// A cash receipt in another currency: what it cost in euros.
    var euroAmount: Double?
    var method: ReceiptMethod
    var category: String?
    var categorySource: CategorySource
    var rows: [String]
    var from: String
    /// The shop's name as the engine read it (nil: none read): a name the person typed instead is remembered for it.
    var shopAsRead: String? = nil

    func receipt(id: String = UUID().uuidString, created: Date = .now) -> LedgerReceipt {
        let foreignCash = currency.uppercased() != ReceiptAmount.euro && method == .cash
        return LedgerReceipt(id: id, date: date, time: time, shop: shop.flatMap { $0.isEmpty ? nil : $0 },
                             total: ReceiptAmount.stored(total), currency: currency.uppercased(),
                             euroAmount: foreignCash ? euroAmount.map(ReceiptAmount.stored) : nil, method: method,
                             category: category, categorySource: category == nil ? .none : categorySource, rows: rows,
                             from: from, paymentID: nil, created: created,
                             shopAsRead: shopAsRead.flatMap { $0.isEmpty ? nil : $0 })
    }
}

/// What correcting a saved receipt changes (brief 33): a new total, date, currency or card or cash makes it another
/// payment as far as the bank statement goes, so it leaves its bank payment and is matched again by the D8 rules; a
/// new shop or category (or euro amount) only updates it.
nonisolated enum ReceiptEdit {
    static func matchesAgain(_ before: LedgerReceipt, _ after: LedgerReceipt) -> Bool {
        before.total != after.total || before.date != after.date || before.currency != after.currency
            || before.method != after.method
    }
}

/// A bank payment offered for a receipt, and why it is asked about (nil: offered by hand, "Join with a payment…").
nonisolated struct ReceiptOption: Identifiable, Equatable, Sendable {
    let payment: LedgerPayment
    let candidate: ReceiptCandidate?
    var id: String { payment.id }
}

/// "Is this the same payment?": a card receipt and the bank payments it may belong to.
nonisolated struct ReceiptQuestion: Identifiable, Equatable, Sendable {
    let receipt: LedgerReceipt
    let options: [ReceiptOption]
    var id: String { receipt.id }
}

/// What saving a receipt led to.
nonisolated enum ReceiptSaved: Equatable, Sendable {
    /// A card receipt joined to its bank payment at once (the one exact match); `gaveCategory`: the payment was not
    /// sorted and took the receipt's category.
    case joined(LedgerPayment, gaveCategory: Bool)
    /// A card receipt with bank payments to ask about.
    case question(ReceiptQuestion)
    /// A card receipt whose payment is not in the store yet.
    case waiting
    /// A cash receipt.
    case cash
    /// A saved receipt corrected without matching it again (its shop, category or euro amount changed).
    case updated
}

/// What matching the waiting card receipts after a bank import did.
nonisolated struct ReceiptMatchRound: Equatable, Sendable {
    /// Receipt id → the payment it joined.
    var joined: [String: String] = [:]
    var questions: [ReceiptQuestion] = []
}

extension PhoneBackend {
    // MARK: reading

    /// The engine's reading of what Vision saw.
    func readReceipt(_ capture: ReceiptCapture) async throws -> ReceiptReading {
        try await engine.readReceipt(capture)
    }

    // MARK: keeping

    func receipts() async throws -> [LedgerReceipt] { try await ledger.receipts() }

    func receipt(_ id: String) async throws -> LedgerReceipt? { try await ledger.receipt(id) }

    /// The receipt joined to a payment (its page's Receipt section).
    func receipt(joinedTo paymentID: String) async throws -> LedgerReceipt? { try await ledger.receipt(joinedTo: paymentID) }

    func payment(_ id: String) async throws -> LedgerPayment? { try await ledger.payment(id) }

    /// Keeps a checked receipt. A category the person picked themselves teaches Aresium the shop. A card receipt is
    /// then matched to the stored payments: one exact match joins at once, candidates are asked, none waits.
    func saveReceipt(_ draft: ReceiptDraft) async throws -> ReceiptSaved {
        let receipt = draft.receipt()
        try await ledger.addReceipt(receipt)
        if draft.categorySource == .manual, let category = receipt.category { try await learnShop(of: receipt, category: category) }
        if let change = ShopNames.change(read: receipt.shopAsRead, saved: receipt.shop) { try await ledger.apply(change) }
        let saved = try await matchSaved(receipt)
        try await refresh()
        return saved
    }

    /// Keeps a saved receipt's corrected values (Edit on its page, brief 33). A new total, date, currency or card or cash
    /// unjoins it and matches it again as on Save (`ReceiptEdit.matchesAgain`: one exact match joins, candidates are
    /// asked, none waits; the payments declined before may be offered again); a new shop or category only updates it. A
    /// category picked by hand teaches the shop and a new shop name is remembered for the shop as read, as on Save.
    func updateReceipt(_ id: String, with draft: ReceiptDraft) async throws -> ReceiptSaved {
        guard let before = try await ledger.receipt(id) else { throw LedgerError.receiptNotFound }
        var after = draft.receipt(id: id, created: before.created)
        after.time = draft.date == before.date ? before.time : nil
        after.rows = before.rows
        after.from = before.from
        after.shopAsRead = before.shopAsRead
        after.direction = before.direction
        after.kind = before.kind
        let again = ReceiptEdit.matchesAgain(before, after)
        after.paymentID = again ? nil : before.paymentID
        after.declined = again ? [] : before.declined
        // Card money comes from the bank, so it is paid from nothing in the wallet.
        after.paidFrom = after.method == .cash ? before.paidFrom : nil
        try await ledger.updateReceipt(after)
        if draft.categorySource == .manual, let category = after.category, category != before.category {
            try await learnShop(of: after, category: category)
        }
        if after.shop != before.shop, let change = ShopNames.change(read: after.shopAsRead, saved: after.shop) {
            try await ledger.apply(change)
        }
        // A payment left without the category it had from the receipt is sorted again with the others not sorted.
        if before.paymentID != nil, after.paymentID == nil || after.category == nil { try await sort() }
        let saved = again ? try await matchSaved(after) : ReceiptSaved.updated
        try await refresh()
        return saved
    }

    /// The name the person gave a shop read as `read` before (`ShopNames`), if they corrected it.
    func correctedShopName(read: String?) async throws -> String? {
        guard let read else { return nil }
        let key = ShopNames.key(read)
        guard !key.isEmpty else { return nil }
        return try await ledger.shopName(read: key)
    }

    /// The category Aresium learned for a shop (a receipt's category picked by hand, or a Switch of one of its bank
    /// payments), when that category is on the person's list.
    func learnedCategory(forShop shop: String?) async throws -> String? {
        guard let shop = shop?.trimmingCharacters(in: .whitespacesAndNewlines), !shop.isEmpty else { return nil }
        guard let key = try await engine.merchantKeys([Self.shopPayment(shop, total: 0, currency: ReceiptAmount.euro,
                                                                         date: ReceiptDay.day(.now))]).first,
              !key.isEmpty,
              let category = try await ledger.learned()[key] else { return nil }
        return try await categories().isChosen(category) ? category : nil
    }

    private func matchSaved(_ receipt: LedgerReceipt) async throws -> ReceiptSaved {
        guard receipt.method == .card else { return .cash }
        let match = try await match(receipt, declined: receipt.declined)
        if let exact = match.exact, let payment = try await ledger.payment(exact) {
            let gave = try await ledger.join(receipt.id, to: exact)
            return .joined(payment, gaveCategory: gave)
        }
        let options = try await options(for: match.candidates)
        return options.isEmpty ? .waiting : .question(ReceiptQuestion(receipt: receipt, options: options))
    }

    /// "Is this the same payment?" answered: a payment joins; nil ("None of these") leaves the receipt waiting and never
    /// offers those payments for it again.
    func answer(_ question: ReceiptQuestion, with paymentID: String?) async throws {
        receiptQuestions.removeAll { $0.id == question.id }
        if let paymentID {
            try await ledger.join(question.receipt.id, to: paymentID)
        } else {
            try await ledger.decline(question.options.map(\.payment.id), for: question.receipt.id)
        }
        try await refresh()
    }

    /// The question about a receipt was closed without an answer: it is not asked again for this import.
    func dismissQuestion(_ question: ReceiptQuestion) {
        receiptQuestions.removeAll { $0.id == question.id }
    }

    /// Joins by hand (the receipt's page).
    @discardableResult
    func join(receipt receiptID: String, to paymentID: String) async throws -> Bool {
        let gave = try await ledger.join(receiptID, to: paymentID)
        try await refresh()
        return gave
    }

    /// Unjoins by hand: the receipt waits again; a category its payment took from it goes, and the payment is sorted
    /// again with the others not sorted.
    func unjoin(receipt receiptID: String) async throws {
        try await ledger.unjoin(receiptID)
        try await sort()
        try await refresh()
    }

    /// Deletes a receipt: unjoined first (as above), and the cash it covered is uncovered.
    func deleteReceipt(_ receiptID: String) async throws {
        try await ledger.deleteReceipt(receiptID)
        try await sort()
        try await refresh()
    }

    /// The receipt's category, changed by the person: Aresium learns its shop, as a Switch does (not for a hand entry,
    /// `addCashEntry`).
    func setReceiptCategory(_ receiptID: String, to category: String?) async throws {
        try await ledger.setReceiptCategory(receiptID, category: category, source: .manual)
        if let category, let receipt = try await ledger.receipt(receiptID), receipt.kind == .receipt {
            try await learnShop(of: receipt, category: category)
        }
        try await refresh()
    }

    /// The payments "Join with a payment…" offers: the engine's (exact first, then its candidates); when it has none,
    /// the money going out from the receipt's day to 7 days later that no other receipt has, nearest day first.
    func joinOptions(for receiptID: String) async throws -> [ReceiptOption] {
        guard let receipt = try await ledger.receipt(receiptID) else { throw LedgerError.receiptNotFound }
        let match = try await match(receipt, declined: [])
        var options = try await options(for: match.candidates)
        if let exact = match.exact, let payment = try await ledger.payment(exact) {
            options.insert(ReceiptOption(payment: payment, candidate: nil), at: 0)
        }
        guard options.isEmpty else { return options }
        let taken = try await ledger.takenPayments(besides: receiptID)
        guard let day = ReceiptDay.date(receipt.date) else { return [] }
        return try await ledger.payments().compactMap { payment -> (Int, ReceiptOption)? in
            guard payment.amountValue < 0, !taken.contains(payment.id), let booked = ReceiptDay.date(payment.bookingDate),
                  let days = ReceiptDay.calendar.dateComponents([.day], from: day, to: booked).day, (0...7).contains(days)
            else { return nil }
            return (days, ReceiptOption(payment: payment, candidate: nil))
        }
        .sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// Before saving (the check window): whether the stored payments hold a match for these values, exact or asked
    /// about. Card is then chosen when the receipt did not say card or cash.
    func hasMatch(date: String, total: Double, currency: String, shop: String?) async throws -> Bool {
        let draft = ReceiptDraft(date: date, shop: shop, total: total, currency: currency, method: .card,
                                 categorySource: .none, rows: [], from: "text")
        let match = try await match(draft.receipt(), declined: [])
        return match.exact != nil || !match.candidates.isEmpty
    }

    // MARK: after a bank import

    /// Every card receipt waiting for its bank payment is matched again: one exact match joins by itself; candidates
    /// are asked once after the import (`receiptQuestions`).
    func matchWaitingReceipts() async throws -> ReceiptMatchRound {
        var round = ReceiptMatchRound()
        for receipt in try await ledger.receipts() where receipt.state == .waiting {
            let match = try await match(receipt, declined: receipt.declined)
            if let exact = match.exact {
                try await ledger.join(receipt.id, to: exact)
                round.joined[receipt.id] = exact
            } else {
                let options = try await options(for: match.candidates)
                if !options.isEmpty { round.questions.append(ReceiptQuestion(receipt: receipt, options: options)) }
            }
        }
        for question in round.questions where !receiptQuestions.contains(where: { $0.id == question.id }) {
            receiptQuestions.append(question)
        }
        return round
    }

    // MARK: helpers

    /// `matchReceipt` over every stored payment; `taken` are the payments other receipts have and the declined ones.
    private func match(_ receipt: LedgerReceipt, declined: [String]) async throws -> ReceiptMatch {
        let taken = try await ledger.takenPayments(besides: receipt.id).union(declined)
        let payments = try await ledger.payments().map { payment in
            MatchPayment(id: payment.id, date: payment.bookingDate, amount: payment.amountValue, currency: payment.currency,
                         counterparty: payment.counterparty, description: payment.text)
        }
        return try await engine.matchReceipt(MatchReceipt(date: receipt.date, total: receipt.totalValue,
                                                          currency: receipt.currency, shop: receipt.shop),
                                             payments: payments, taken: taken.sorted())
    }

    private func options(for candidates: [ReceiptCandidate]) async throws -> [ReceiptOption] {
        var options: [ReceiptOption] = []
        for candidate in candidates {
            if let payment = try await ledger.payment(candidate.id) {
                options.append(ReceiptOption(payment: payment, candidate: candidate))
            }
        }
        return options
    }

    /// Teaches Aresium the receipt's shop (`learn`, as a Switch does with a payment's merchant).
    private func learnShop(of receipt: LedgerReceipt, category: String) async throws {
        guard let shop = receipt.shop, !shop.isEmpty else { return }
        let payment = Self.shopPayment(shop, total: receipt.totalValue, currency: receipt.currency, date: receipt.date)
        try await ledger.remember(try await engine.learn(payment, categoryID: category))
    }

    /// A shop as the sorting rules see a payment of it: the merchant a receipt teaches and looks up.
    private static func shopPayment(_ shop: String, total: Double, currency: String, date: String) -> SortingPayment {
        SortingPayment(counterparty: shop, description: shop, source: "bank", account: "receipt", amount: -total,
                       currency: currency, date: date)
    }
}

/// Receipt days (`YYYY-MM-DD`) as dates and back, in the Gregorian calendar of the iPhone's time zone (the day the
/// person paid, as the date picker shows it).
nonisolated enum ReceiptDay {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Noon of that day (so a time zone change never moves it to another day); nil when it is not a day.
    static func date(_ day: String) -> Date? {
        guard LedgerExport.isDay(String(day.prefix(10))) else { return nil }
        let parts = day.prefix(10).split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func day(_ date: Date) -> String { LedgerExport.day(date, calendar: calendar) }
}

/// The words for receipts (English here, German in the catalog): pure, so tests pin both languages.
nonisolated enum ReceiptWording {
    /// Where a receipt stands, in one line.
    static func state(_ state: ReceiptState, language: AppLanguage = .current) -> String {
        switch state {
        case .joined: language.string("Counted as its bank payment")
        case .waiting: language.string("Waiting for the bank statement")
        case .cash: language.string("Paid in cash")
        }
    }

    /// What differs between a receipt and a payment it is asked about. `sameAmount`: how many payments have the
    /// receipt's exact amount.
    static func difference(_ candidate: ReceiptCandidate?, sameAmount: Int, language: AppLanguage = .current) -> String? {
        guard let candidate else { return nil }
        switch candidate.why {
        case .severalSame:
            return language.string("One of \(max(sameAmount, 2)) payments with this amount")
        case .otherCurrency:
            return language.string("Paid in another currency")
        case .amountDiffers:
            guard let difference = candidate.difference, abs(difference) >= 0.005 else { return nil }
            let money = ReceiptAmount.shown(abs(difference), currency: ReceiptAmount.euro, language: language)
            return difference > 0 ? language.string("\(money) more: cash back or a tip?")
                                  : language.string("\(money) less than the receipt")
        }
    }

    /// The line after saving, in the import's result banner.
    static func saved(_ saved: ReceiptSaved, language: AppLanguage = .current) -> String {
        switch saved {
        case .joined: language.string("Receipt saved. It counts as its bank payment.")
        case .waiting, .question: language.string("Receipt saved. It waits for the bank statement.")
        case .cash, .updated: language.string("Receipt saved.")
        }
    }

    /// After "Is this the same payment?".
    static func answered(joined: Bool, language: AppLanguage = .current) -> String {
        joined ? language.string("Receipt saved. It counts as its bank payment.")
               : language.string("Receipt saved. It waits for the bank statement.")
    }
}
