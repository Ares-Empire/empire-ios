import Foundation

/// Mutually exclusive reasons why selected rows cannot take part. Missing and covered rows are not live selections.
nonisolated struct PaybackSkipped: Equatable, Sendable {
    var receipts = 0
    var cashEntries = 0
    var transfers = 0
    var withdrawals = 0
    var otherCurrencies = 0
    var nothingLeft = 0
    var total: Int { receipts + cashEntries + transfers + withdrawals + otherCurrencies + nothingLeft }
}

/// A preview belongs to one ledger and one save revision, even if a later save changes a value and changes it back.
nonisolated struct PaybackRevision: Sendable {
    let ledger: UUID
    let value: UInt64
}

nonisolated struct PaybackGroup: Sendable {
    let direction: PaybackDirection
    let payments: [PaybackCandidate]
    let skipped: PaybackSkipped
    let totalRest: Double
    /// Pure groups have no revision and cannot be saved. Get a saveable group from the store.
    let revision: PaybackRevision?
    var ids: Set<String> { Set(payments.map { $0.transaction.id }) }
}

/// `amount` is added by this plan; `totalAmount` includes this pair's existing link.
nonisolated struct PaybackPlanLink: Equatable, Sendable {
    let from: String
    let to: String
    let amount: Double
    let totalAmount: Double
}

nonisolated struct PaybackAllocation: Equatable, Sendable, Identifiable {
    let id: String
    /// Euros given or received in this plan alone.
    let amount: Double
    let rest: Double
}

/// Whole-cent pouring, independent of the store and engine. Each side is ordered by date, list order, then id.
nonisolated struct PaybackPlan: Sendable {
    let links: [PaybackPlanLink]
    let expenses: [PaybackAllocation]
    let paymentsIn: [PaybackAllocation]
    var hasLinks: Bool { !links.isEmpty }
    var expenseCount: Int { expenses.filter { $0.amount > 0 }.count }
    var moneyInCount: Int { paymentsIn.filter { $0.amount > 0 }.count }
    var linked: Double { Self.sum(expenses.map(\.amount)) }
    var stillOpen: Double { Self.sum(expenses.map(\.rest)) }
    var staysIncome: Double { Self.sum(paymentsIn.map(\.rest)) }

    init(group: PaybackGroup, others: [PaybackCandidate]) throws {
        guard others.allSatisfy({ $0.state.direction != group.direction }),
              Set(others.map { $0.transaction.id }).count == others.count,
              group.ids.isDisjoint(with: others.map { $0.transaction.id }) else { throw PaybackError.invalidPayment }
        let out = (group.direction == .moneyOut ? group.payments : others).sorted(by: Paybacks.pourOrder)
        let incoming = (group.direction == .moneyIn ? group.payments : others).sorted(by: Paybacks.pourOrder)
        func rests(_ payments: [PaybackCandidate]) throws -> [Int] {
            try payments.map {
                guard let cents = Paybacks.cents($0.state.rest), cents >= 0 else { throw PaybackError.invalidAmount }
                return cents
            }
        }
        var open = try rests(out), available = try rests(incoming)
        let originalOpen = open, originalAvailable = available
        var links: [PaybackPlanLink] = []
        var expense = 0, payer = 0
        while expense < out.count && payer < incoming.count {
            if open[expense] == 0 { expense += 1; continue }
            if available[payer] == 0 { payer += 1; continue }
            let amount = min(open[expense], available[payer])
            let from = incoming[payer].transaction, to = out[expense].transaction
            let previous = from.paysBack?.first { $0.payment == to.id }?.amount ?? 0
            guard let old = Paybacks.cents(previous), old >= 0 else { throw PaybackError.invalidAmount }
            links.append(PaybackPlanLink(from: from.id, to: to.id, amount: Double(amount) / 100,
                                         totalAmount: Double(old + amount) / 100))
            open[expense] -= amount
            available[payer] -= amount
        }
        self.links = links
        expenses = out.indices.map { PaybackAllocation(id: out[$0].transaction.id,
            amount: Double(originalOpen[$0] - open[$0]) / 100, rest: Double(open[$0]) / 100) }
        paymentsIn = incoming.indices.map { PaybackAllocation(id: incoming[$0].transaction.id,
            amount: Double(originalAvailable[$0] - available[$0]) / 100, rest: Double(available[$0]) / 100) }
    }

    private static func sum(_ amounts: [Double]) -> Double {
        Double(amounts.reduce(0) { $0 + (Paybacks.cents($1) ?? 0) }) / 100
    }
}

extension Paybacks {
    nonisolated static func pourOrder(_ first: PaybackCandidate, _ second: PaybackCandidate) -> Bool {
        let a = first.transaction, b = second.transaction
        if a.date != b.date { return a.date < b.date }
        if Transaction.listOrder(a, b) { return true }
        if Transaction.listOrder(b, a) { return false }
        return a.id < b.id
    }

    nonisolated static func group(ids: Set<String>, dashboard: Dashboard, payments: [LedgerPayment], transferIDs: Set<String>,
                      revision: PaybackRevision? = nil) -> PaybackGroup? {
        let rows = dashboard.transactions.filter { ids.contains($0.id) && $0.coveredBy == nil }
        let directions = Set(rows.filter { $0.amount != 0 }.map { $0.amount > 0 ? 1 : -1 })
        guard directions.count == 1 else { return nil }
        let stored = Dictionary(uniqueKeysWithValues: payments.map { ($0.id, $0) })
        let candidates = Dictionary(uniqueKeysWithValues: candidates(dashboard: dashboard, payments: payments,
            transferIDs: transferIDs).map { ($0.transaction.id, $0) })
        let entryIDs = Set((dashboard.cash?.movements ?? []).filter { $0.kind == .manual || $0.kind == .received }.map(\.id))
        var skipped = PaybackSkipped(), included: [PaybackCandidate] = []
        for row in rows {
            if let receipt = row.receiptId {
                if entryIDs.contains(receipt) { skipped.cashEntries += 1 } else { skipped.receipts += 1 }
            } else if let payment = stored[row.id] {
                if payment.currency != "EUR" { skipped.otherCurrencies += 1 }
                else if payment.category.map(transferIDs.contains) ?? false { skipped.transfers += 1 }
                else if row.cashWithdrawal == true { skipped.withdrawals += 1 }
                else if let candidate = candidates[row.id], candidate.state.rest > 0 { included.append(candidate) }
                else { skipped.nothingLeft += 1 }
            }
        }
        guard let direction = included.first?.state.direction else { return nil }
        return PaybackGroup(direction: direction, payments: included.sorted(by: pourOrder), skipped: skipped,
            totalRest: Double(included.reduce(0) { $0 + (cents($1.state.rest) ?? 0) }) / 100, revision: revision)
    }

    nonisolated static func suggestion(_ candidate: PaybackCandidate, forGroup group: PaybackGroup) -> PaybackSuggestion? {
        // Preserve the established single-payment fits, including original amount and already-linked rest.
        if group.payments.count == 1 { return suggestion(candidate, for: group.payments[0]) }
        guard candidate.state.direction != group.direction, candidate.state.rest > 0,
              !group.ids.contains(candidate.transaction.id), let rest = cents(candidate.state.rest),
              let total = cents(group.totalRest), total > 0 else { return nil }
        let fits: [(PaybackFit, Int)]
        if group.direction == .moneyOut {
            fits = [(.whole, total), (.half, Int((Double(total) / 2).rounded())),
                    (.third, Int((Double(total) / 3).rounded())), (.quarter, Int((Double(total) / 4).rounded()))]
        } else {
            fits = [(.whole, total), (.half, total * 2)]
        }
        let fit = fits.first { $0.1 > 0 && abs(rest - $0.1) <= 1 }?.0
        return PaybackSuggestion(transaction: candidate.transaction, state: candidate.state, fit: fit,
                                 amount: Double(min(rest, total)) / 100)
    }

    nonisolated static func suggestions(forGroup group: PaybackGroup, in candidates: [PaybackCandidate], limit: Int = 8) -> [PaybackSuggestion] {
        if group.payments.count == 1 { return suggestions(for: group.payments[0], in: candidates, limit: limit) }
        let days = group.payments.compactMap { ReceiptDay.date($0.transaction.date) }
        guard let earliest = days.min(), let newest = days.max() else { return [] }
        let calendar = ReceiptDay.calendar
        let start = calendar.date(byAdding: .day, value: group.direction == .moneyOut ? -30 : -120, to: earliest)!
        let end = calendar.date(byAdding: .day, value: group.direction == .moneyOut ? 120 : 30, to: newest)!
        return candidates.compactMap { candidate -> (PaybackSuggestion, Int)? in
            guard let day = ReceiptDay.date(candidate.transaction.date), (start...end).contains(day),
                  let result = suggestion(candidate, forGroup: group) else { return nil }
            return (result, abs(calendar.dateComponents([.day], from: newest, to: day).day ?? 0))
        }.sorted {
            if ($0.0.fit != nil) != ($1.0.fit != nil) { return $0.0.fit != nil }
            if $0.1 != $1.1 { return $0.1 < $1.1 }
            if $0.0.transaction.date != $1.0.transaction.date { return $0.0.transaction.date > $1.0.transaction.date }
            return $0.0.id < $1.0.id
        }.prefix(max(0, limit)).map(\.0)
    }

    nonisolated static func search(_ query: String, forGroup group: PaybackGroup, in candidates: [PaybackCandidate]) -> [PaybackSuggestion] {
        candidates.filter { NameSearch.matches(query, names: $0.names) }
            .compactMap { suggestion($0, forGroup: group) }
            .sorted { $0.transaction.date == $1.transaction.date ? $0.id < $1.id : $0.transaction.date > $1.transaction.date }
    }
}

@MainActor
struct PaybackGroupResult {
    let plan: PaybackPlan
    let undo: BatchUndo
    var expenseCount: Int { plan.expenseCount }
    var moneyInCount: Int { plan.moneyInCount }
    var linked: Double { plan.linked }
    var stillOpen: Double { plan.stillOpen }
    var staysIncome: Double { plan.staysIncome }
    var message: String { PaybackGroupWording.summary(plan) }
}

nonisolated enum PaybackGroupWording {
    static func summary(_ plan: PaybackPlan, language: AppLanguage = .current) -> String {
        summary(expenses: plan.expenseCount, linked: plan.linked, stillOpen: plan.stillOpen,
                staysIncome: plan.staysIncome, language: language)
    }

    static func summary(expenses: Int, linked: Double, stillOpen: Double, staysIncome: Double,
                        language: AppLanguage = .current) -> String {
        var parts = [language.string("\(expenses) expenses, \(Money.precise(linked, language: language)) paid back.")]
        if stillOpen > 0 { parts.append(open(stillOpen, language: language)) }
        if staysIncome > 0 { parts.append(income(staysIncome, language: language)) }
        return parts.joined(separator: " ")
    }

    static func open(_ amount: Double, language: AppLanguage = .current) -> String {
        language.string("\(Money.precise(amount, language: language)) still open.")
    }

    static func income(_ amount: Double, language: AppLanguage = .current) -> String {
        language.string("\(Money.precise(amount, language: language)) stays income.")
    }
}

extension PhoneBackend {
    func paybackGroup(ids: Set<String>) async throws -> PaybackGroup? {
        try await ledger.paybackGroup(ids: ids, engine: engine, catalog: engine.catalog(), today: today(), ownNames: ownNames)
    }

    func paybackSuggestions(forGroup group: PaybackGroup) async throws -> [PaybackSuggestion] {
        Paybacks.suggestions(forGroup: group, in: try await paybackCandidates(names: false))
    }

    func paybackSearch(_ query: String, forGroup group: PaybackGroup) async throws -> [PaybackSuggestion] {
        Paybacks.search(query, forGroup: group, in: try await paybackCandidates())
    }

    func paybackPlan(group: PaybackGroup, others: Set<String>) async throws -> PaybackPlan {
        try await ledger.planPaybacks(group: group, others: others, engine: engine, catalog: engine.catalog(),
                                      today: today(), ownNames: ownNames)
    }

    func setPaybacks(group: PaybackGroup, others: Set<String>) async throws -> PaybackGroupResult {
        let saved = try await ledger.changePaybacks(group: group, others: others, engine: engine,
            catalog: engine.catalog(), today: today(), ownNames: ownNames)
        return PaybackGroupResult(plan: saved.plan, undo: BatchUndo(token: saved.undo, phone: self))
    }
}

extension DashboardStore {
    func paybackGroup(ids: Set<String>) async throws -> PaybackGroup? { try await phone?.paybackGroup(ids: ids) }
    func paybackSuggestions(forGroup group: PaybackGroup) async throws -> [PaybackSuggestion] {
        try await phone?.paybackSuggestions(forGroup: group) ?? []
    }
    func paybackSearch(_ query: String, forGroup group: PaybackGroup) async throws -> [PaybackSuggestion] {
        try await phone?.paybackSearch(query, forGroup: group) ?? []
    }
    func paybackPlan(group: PaybackGroup, others: Set<String>) async throws -> PaybackPlan {
        guard let phone else { throw BatchChangeError.unavailable }
        return try await phone.paybackPlan(group: group, others: others)
    }
    func setPaybacks(group: PaybackGroup, others: Set<String>) async throws -> PaybackGroupResult {
        guard let phone else { throw BatchChangeError.unavailable }
        let result = try await phone.setPaybacks(group: group, others: others)
        result.undo.afterChange = { [weak self] in await self?.reloadAfterTransactionChange() }
        await reloadAfterTransactionChange()
        return result
    }
}
