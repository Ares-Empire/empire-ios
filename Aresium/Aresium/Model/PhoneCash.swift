import Foundation

// Cash in phone mode (brief 33 part B): hand entries, Paid from, and the Cash page's data. Entries are receipts of kind
// manual (`CashEntryDraft`); the engine counts them and builds `Dashboard.cash` (brief 32). See `Model/Cash.swift`.

extension PhoneBackend {
    /// The Cash page's data: the engine's `cash` of a dashboard built now (nil only from an engine without it).
    func cash() async throws -> CashView? {
        try await dashboard(auth: BackendAuth(token: nil)).cash
    }

    /// Paid from's choices for a cash payment on `day`: the withdrawals and cash received on or before it, newest first,
    /// each with what it still holds (`besides`: the entry itself).
    func cashSources(onOrBefore day: String, besides id: String? = nil) async throws -> [CashSource] {
        guard let cash = try await cash() else { return [] }
        return CashPage(cash: cash).sources(onOrBefore: day, besides: id)
    }

    /// Keeps a hand entry (Add cash): a receipt of kind manual, cash, never joined to a bank payment. Its category is not
    /// learned for what was typed: an entry names an occasion ("Flohmarkt", "Geburtstag von Oma") more often than a
    /// shop, and a rule from it could sort bank payments that only share a word.
    @discardableResult
    func addCashEntry(_ draft: CashEntryDraft) async throws -> LedgerReceipt {
        let entry = draft.receipt()
        try await ledger.addReceipt(entry)
        try await refresh()
        return entry
    }

    /// Keeps an entry's corrected values (Edit on its page). One that was cash received and is now spent is no source
    /// any more: what was paid from it goes back to automatic.
    @discardableResult
    func updateCashEntry(_ id: String, with draft: CashEntryDraft) async throws -> LedgerReceipt {
        guard let before = try await ledger.receipt(id), before.kind == .manual else { throw LedgerError.receiptNotFound }
        let after = draft.receipt(id: id, created: before.created)
        try await ledger.updateReceipt(after)
        if before.direction == .in, after.direction == .out { try await ledger.forgetPaidFrom(id) }
        try await refresh()
        return after
    }

    /// Paid from on a cash receipt's or spent entry's page: a withdrawal or received entry, or nil (automatic).
    func setPaidFrom(_ receiptID: String, to source: String?) async throws {
        guard var receipt = try await ledger.receipt(receiptID) else { throw LedgerError.receiptNotFound }
        guard receipt.method == .cash, receipt.direction == .out else { return }
        receipt.paidFrom = source
        try await ledger.updateReceipt(receipt)
        try await refresh()
    }
}
