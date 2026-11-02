import Foundation

/// A hand-made link lives on the payment in. Money has the ledger's decimal-string representation.
nonisolated struct LedgerPayback: Codable, Equatable, Sendable {
    let payment: String
    let amount: String
}

nonisolated enum PaybackDirection: Equatable, Sendable { case moneyIn, moneyOut }

nonisolated struct PaybackState: Equatable, Sendable {
    let direction: PaybackDirection
    /// Positive euros still available, also zero when all of the payment is linked.
    let rest: Double
    var canPayBack: Bool { direction == .moneyIn }
    var canBePaidBack: Bool { direction == .moneyOut }
}

nonisolated enum PaybackFit: String, Codable, Sendable { case whole, half, third, quarter, rest }

nonisolated struct PaybackSuggestion: Identifiable, Sendable {
    let transaction: Transaction
    let state: PaybackState
    let fit: PaybackFit?
    /// Positive euros the proposed link would take, never more than either end's rest.
    let amount: Double
    var id: String { transaction.id }
}

nonisolated struct PaybackCandidate: Sendable {
    let transaction: Transaction
    let state: PaybackState
    /// The same searchable spellings as the name search, including hidden own names.
    let names: [String]
}

nonisolated enum PaybackError: LocalizedError, Equatable {
    case invalidPayment, invalidAmount, payerLimit, expenseLimit, missingLink

    var errorDescription: String? {
        switch self {
        case .invalidAmount: String(localized: "Type the amount.")
        default: String(localized: "This change is no longer available.")
        }
    }
}

/// Pure eligibility, ranking and limit checks; the engine alone supplies applied links and counted amounts.
nonisolated enum Paybacks {
    /// Only whole cents, finite and inside JavaScript's exact integer range. The tolerance accepts binary doubles
    /// such as 0.29, without rounding a typed fraction of a cent into a valid amount.
    static func cents(_ amount: Double) -> Int? {
        let scaled = amount * 100
        guard scaled.isFinite, abs(scaled) <= 9_007_199_254_740_991,
              abs(scaled - scaled.rounded()) <= 0.0000001 else { return nil }
        return Int(scaled.rounded())
    }

    static func stored(_ cents: Int) -> String {
        String(cents / 100) + String(format: ".%02d", abs(cents % 100))
    }

    static func candidates(dashboard: Dashboard, payments: [LedgerPayment], transferIDs: Set<String>,
                           shopNames: [String: String] = [:]) -> [PaybackCandidate] {
        let stored = Dictionary(uniqueKeysWithValues: payments.map { ($0.id, $0) })
        let bankNamesByGroup: [String: [String]] = dashboard.nameGroups?.mapValues { group in
            var seen = Set<String>()
            return group.rows.compactMap { stored[$0.id]?.place }.filter { seen.insert($0).inserted }
        } ?? [:]
        // TODO(api): the engine's transaction output has no currency after PayPal conversion folding. Until it
        // exposes that, only stored EUR payments can safely be offered; do not guess euro eligibility from an amount.
        return dashboard.transactions.compactMap { row -> PaybackCandidate? in
            guard let payment = stored[row.id], payment.currency == "EUR",
                  payment.category.map({ !transferIDs.contains($0) }) ?? true,
                  row.receiptId == nil, row.coveredBy == nil, row.cashWithdrawal != true, row.amount != 0,
                  let original = cents(abs(row.amount)), let counted = cents(abs(row.countedAmount)) else { return nil }
            // Bank spellings belong to the shop; a payment-only own name belongs only to that payment.
            let bankNames = row.nameKey.flatMap { bankNamesByGroup[$0] } ?? []
            let names = [row.place, row.bankName, payment.place, payment.ownName, shopNames[row.id]].compactMap { $0 } + bankNames
            return PaybackCandidate(transaction: row,
                                    state: PaybackState(direction: row.amount > 0 ? .moneyIn : .moneyOut,
                                                        rest: Double(min(original, counted)) / 100), names: names)
        }
    }

    static func suggestion(_ candidate: PaybackCandidate, for payment: PaybackCandidate) -> PaybackSuggestion? {
        guard candidate.transaction.id != payment.transaction.id, candidate.state.direction != payment.state.direction,
              candidate.state.rest > 0, payment.state.rest > 0 else { return nil }
        let incoming = payment.state.direction == .moneyIn ? payment : candidate
        let expense = payment.state.direction == .moneyOut ? payment : candidate
        let available = cents(incoming.state.rest)!, rest = cents(expense.state.rest)!
        let original = cents(abs(expense.transaction.amount))!
        let fits: [(PaybackFit, Int)] = [(.whole, original), (.half, Int((Double(original) / 2).rounded())),
                                       (.third, Int((Double(original) / 3).rounded())),
                                       (.quarter, Int((Double(original) / 4).rounded())), (.rest, rest)]
        let fit = fits.first { $0.1 > 0 && $0.1 <= rest && abs(available - $0.1) <= 1 }
        return PaybackSuggestion(transaction: candidate.transaction, state: candidate.state, fit: fit?.0,
                                 amount: Double(min(available, rest, fit?.1 ?? min(available, rest))) / 100)
    }

    static func suggestions(for payment: PaybackCandidate, in candidates: [PaybackCandidate], limit: Int = 8) -> [PaybackSuggestion] {
        guard let day = ReceiptDay.date(payment.transaction.date) else { return [] }
        let calendar = ReceiptDay.calendar
        return candidates.compactMap { candidate -> (PaybackSuggestion, Int)? in
            guard let otherDay = ReceiptDay.date(candidate.transaction.date),
                  let result = suggestion(candidate, for: payment) else { return nil }
            let days = calendar.dateComponents([.day], from: day, to: otherDay).day ?? 0
            let incomingAfterExpense = payment.state.direction == .moneyOut ? days : -days
            guard (-30...120).contains(incomingAfterExpense) else { return nil }
            return (result, abs(days))
        }.sorted {
            if ($0.0.fit != nil) != ($1.0.fit != nil) { return $0.0.fit != nil }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if $0.0.transaction.date != $1.0.transaction.date { return $0.0.transaction.date > $1.0.transaction.date }
            return $0.0.id < $1.0.id
        }.prefix(max(0, limit)).map(\.0)
    }

    /// No date window or result cap: a name can find every eligible instalment, also years later.
    static func search(_ query: String, for payment: PaybackCandidate, in candidates: [PaybackCandidate]) -> [PaybackSuggestion] {
        candidates.filter { NameSearch.matches(query, names: $0.names) }
            .compactMap { suggestion($0, for: payment) }
            .sorted { $0.transaction.date == $1.transaction.date ? $0.id < $1.id : $0.transaction.date > $1.transaction.date }
    }

    /// Export integrity before restore: no dangling, repeated, non-cent, wrong-direction or over-limit links.
    static func validateStored(payments: [LedgerPayment], transferIDs: Set<String>) throws {
        let byID = Dictionary(uniqueKeysWithValues: payments.map { ($0.id, $0) })
        var received: [String: Int] = [:]
        for payer in payments where !(payer.paysBack ?? []).isEmpty {
            guard payer.currency == "EUR", payer.amountValue > 0,
                  payer.category.map({ !transferIDs.contains($0) }) ?? true,
                  let available = cents(payer.amountValue) else { throw LedgerError.invalidExport("payback payer") }
            var paid = 0, targets = Set<String>()
            for link in payer.paysBack ?? [] {
                guard let expense = byID[link.payment], expense.currency == "EUR", expense.amountValue < 0,
                      expense.category.map({ !transferIDs.contains($0) }) ?? true,
                      targets.insert(link.payment).inserted,
                      LedgerExport.isAmount(link.amount), let euros = Double(link.amount),
                      let amount = cents(euros), amount > 0, let maximum = cents(-expense.amountValue),
                      amount <= available - paid, amount <= maximum - received[expense.id, default: 0]
                else { throw LedgerError.invalidExport("payback link") }
                paid += amount
                received[expense.id, default: 0] += amount
            }
        }
    }
}

extension PhoneBackend {
    /// `names: false` leaves out the search's spellings (the state and the suggestions need none, brief 203).
    func paybackCandidates(names: Bool = true) async throws -> [PaybackCandidate] {
        try await ledger.paybackCandidates(engine: engine, catalog: engine.catalog(), today: today(), ownNames: ownNames,
                                           names: names)
    }

    func paybackState(for id: String) async throws -> PaybackState? {
        try await paybackCandidates(names: false).first { $0.transaction.id == id }?.state
    }

    func paybackSuggestions(for id: String) async throws -> [PaybackSuggestion] {
        guard let group = try await paybackGroup(ids: [id]) else { return [] }
        return try await paybackSuggestions(forGroup: group)
    }

    func paybackSearch(_ query: String, for id: String) async throws -> [PaybackSuggestion] {
        guard let group = try await paybackGroup(ids: [id]) else { return [] }
        return try await paybackSearch(query, forGroup: group)
    }

    /// Saves once; the dashboard store publishes the rebuilt dashboard and widget once.
    func setPayback(from: String, to: String, amount: Double) async throws -> BatchUndo {
        let token = try await ledger.changePayback(from: from, to: to, amount: amount, engine: engine,
                                                   catalog: engine.catalog(), today: today(), ownNames: ownNames)
        return BatchUndo(token: token, phone: self)
    }

    func removePayback(from: String, to: String) async throws -> BatchUndo {
        let token = try await ledger.changePayback(from: from, to: to, amount: nil, engine: engine,
                                                   catalog: engine.catalog(), today: today(), ownNames: ownNames)
        return BatchUndo(token: token, phone: self)
    }
}

extension DashboardStore {
    /// Nil/empty in server mode, and for rows outside the bank ledger (receipts, cash entries and covered rows).
    func paybackState(for id: String) async throws -> PaybackState? { try await phone?.paybackState(for: id) }
    func paybackSuggestions(for id: String) async throws -> [PaybackSuggestion] { try await phone?.paybackSuggestions(for: id) ?? [] }
    func paybackSearch(_ query: String, for id: String) async throws -> [PaybackSuggestion] { try await phone?.paybackSearch(query, for: id) ?? [] }

    func setPayback(from: String, to: String, amount: Double) async throws -> BatchUndo {
        guard let phone else { throw BatchChangeError.unavailable }
        let undo = try await phone.setPayback(from: from, to: to, amount: amount)
        undo.afterChange = { [weak self] in await self?.reloadAfterTransactionChange() }
        await reloadAfterTransactionChange()
        return undo
    }

    func removePayback(from: String, to: String) async throws -> BatchUndo {
        guard let phone else { throw BatchChangeError.unavailable }
        let undo = try await phone.removePayback(from: from, to: to)
        undo.afterChange = { [weak self] in await self?.reloadAfterTransactionChange() }
        await reloadAfterTransactionChange()
        return undo
    }
}
