import Foundation

// Receipts, kept (brief 31 part B, D8 in ares-empire/docs/ARESIUM-FOR-OTHERS.md → part 6): what the person confirmed
// in the check window, stored in the phone's ledger (`StoredReceipt`), never the image. A card receipt joins its bank
// payment so the purchase counts once; until then it counts on its own, waiting for the bank statement. A cash receipt
// counts in its category and takes its amount out of the cash withdrawals before it (the engine counts both,
// `buildDashboardSource`).

/// A stored receipt as a value (also its shape in an export, schema version 2).
nonisolated struct LedgerReceipt: Codable, Equatable, Sendable, Identifiable {
    let id: String
    /// The purchase day, `YYYY-MM-DD`; its time `HH:MM` when the receipt printed one.
    var date: String
    var time: String?
    var shop: String?
    /// The amount paid as a decimal string ("27.65"), in `currency`.
    var total: String
    /// ISO 4217 ("EUR").
    var currency: String
    /// A cash receipt in another currency: what it cost in euros (decimal string).
    var euroAmount: String?
    var method: ReceiptMethod
    var category: String?
    var categorySource: CategorySource
    /// The receipt's lines as read, top to bottom.
    var rows: [String]
    /// "code" when the register's QR code was read, else "text".
    var from: String
    /// The bank payment it is joined to.
    var paymentID: String?
    /// Payments the person said are not this receipt's (never offered for it again).
    var declined: [String] = []
    var created: Date

    var totalValue: Double { Double(total) ?? 0 }
    var isEuro: Bool { currency.uppercased() == ReceiptAmount.euro }

    /// Where it stands: joined to its bank payment, waiting for it (card), or paid in cash.
    var state: ReceiptState {
        if method == .cash { return .cash }
        return paymentID == nil ? .waiting : .joined
    }

    /// The amount the dashboard counts it with, in euros: the total, or for a cash receipt in another currency the euro
    /// amount typed for it; nil for a card receipt in another currency (it counts once joined, as its bank payment).
    var euros: Double? {
        if isEuro { return totalValue }
        return method == .cash ? euroAmount.flatMap(Double.init) : nil
    }
}

/// Where a receipt stands.
nonisolated enum ReceiptState: String, Equatable, Sendable {
    /// Joined to its bank payment: only the payment counts.
    case joined
    /// A card receipt waiting for its bank payment: it counts on its own meanwhile.
    case waiting
    /// Paid in cash: it counts in its category and is taken out of the withdrawals.
    case cash
}

/// Amounts as the ledger keeps them: plain decimal strings ("27.65"), the way the engine writes payments.
nonisolated enum ReceiptAmount {
    static let euro = "EUR"

    /// "27.65" from 27.65 (two decimals, rounded to the cent).
    static func stored(_ value: Double) -> String { String(format: "%.2f", (value * 100).rounded() / 100) }

    /// What a person typed ("27,65", "27.65", "1.027,65", "€ 27,65") as a positive amount; nil when it is not one.
    static func typed(_ text: String) -> Double? {
        let kept = text.filter { $0.isNumber || $0 == "," || $0 == "." }
        guard !kept.isEmpty else { return nil }
        // The last separator with one or two digits after it is the decimal one; the others group thousands.
        let separators = kept.indices.filter { kept[$0] == "," || kept[$0] == "." }
        var normal = kept
        if let last = separators.last, kept.distance(from: last, to: kept.endIndex) - 1 <= 2 {
            let whole = kept[..<last].filter(\.isNumber), cents = kept[kept.index(after: last)...]
            normal = whole + "." + String(cents)
        } else {
            normal = kept.filter(\.isNumber)
        }
        guard let value = Double(normal), value > 0, value.isFinite else { return nil }
        return (value * 100).rounded() / 100
    }

    /// An amount for a field, in the app's language ("27,65" / "27.65"), without the currency.
    static func field(_ value: Double, language: AppLanguage = .current) -> String {
        value.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(language.locale))
    }

    /// An amount with its currency in the app's language ("€27.65", "27,65 €", "£12.40").
    static func shown(_ value: Double, currency: String, language: AppLanguage = .current) -> String {
        value.formatted(.currency(code: currency.isEmpty ? euro : currency).locale(language.locale))
    }
}
