import Foundation

nonisolated struct Dashboard: Codable {
    let version: Int
    let months: [Month]
    let categories: [Category]
    let incomeBuckets: [Category]
    var transactions: [Transaction]
    let overview: Overview
    let total: Totals
    let byMonth: [String: MonthData]
    let spend: [String: Series]
    let income: [String: Series]
    let pick: CategoryChoices
    /// Phone mode (brief 32; absent from the server's JSON): every cash movement, for the Cash page. A view, counted in
    /// no total.
    var cash: CashView? = nil

    var paybacksIgnored: [PaybackIgnored]? = nil

    /// Phone mode: built once with the dashboard, over all its months.
    var nameGroups: [String: PaymentNameGroup]? = nil

    static func decode(_ data: Data) throws -> Dashboard {
        let dashboard = try JSONDecoder().decode(Dashboard.self, from: data)
        guard dashboard.version == 2 else { throw DashboardError.unsupportedVersion }
        return dashboard
    }

    static func sample() throws -> Dashboard {
        guard let url = Bundle.main.url(forResource: "dashboard.sample", withExtension: "json") else {
            throw DashboardError.missingSample
        }
        return try decode(Data(contentsOf: url))
    }
}

nonisolated struct CategoryChoices: Codable {
    let spend: [String]
    let income: [String]
}

extension Dashboard {
    func recategorisationChoices(amount: Double) -> [Category] {
        (Self.picksIncome(amount: amount) ? pick.income : pick.spend).compactMap { name in
            categories.first { $0.name == name }
        }
    }

    /// Money in moves among the income list (`pick.income`), everything else among spending (`pick.spend`).
    static func picksIncome(amount: Double) -> Bool { amount > 0 }


}

nonisolated struct Month: Codable, Identifiable {
    let key: String
    /// The server's English names ("Sep 2025", "Sep"); the app shows `title()` and `shortTitle()`.
    let label: String
    let short: String
    let year: Int
    let month: Int
    let days: Int
    let partial: Bool
    var id: String { key }

    /// The month in the app's language: the server's "Sep 2025", or German "Sept. 2025".
    func title(_ language: AppLanguage = .current) -> String {
        german(language, style: { $0.month(.abbreviated).year() }) ?? label
    }

    /// The chart's axis label: "Sep", or German "Sept".
    func shortTitle(_ language: AppLanguage = .current) -> String {
        german(language, style: { $0.month(.abbreviated) }) ?? short
    }

    private func german(_ language: AppLanguage, style: (Date.FormatStyle) -> Date.FormatStyle) -> String? {
        guard language == .german, let date = WidgetFormatting.monthDate(key) else { return nil }
        let calendar = WidgetFormatting.calendar
        return date.formatted(style(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                                     calendar: calendar, timeZone: calendar.timeZone)))
    }
}

nonisolated struct Category: Codable, Identifiable {
    enum Kind: String, Codable { case spend, income, transfer }
    let name: String
    let icon: String
    let color: String
    let kind: Kind
    var otherSide: Bool? = nil
    var id: String { name }
}

nonisolated struct Transaction: Codable, Identifiable {
    let id: String
    let date: String
    let day: Int
    let month: String
    let amount: Double
    let categoryName: String
    let tags: [String]
    var place: String
    let city: String
    let categoriesIn: [String]
    let incomeBuckets: [String]
    var counted: Double? = nil
    var paidBack: Double? = nil
    var paidBackBy: [PaymentLink]? = nil
    var paysBack: [PaymentLink]? = nil
    var countedAmount: Double { counted ?? amount }

    /// Phone mode's receipts (brief 31; absent from the server's JSON): the receipt this row is (a cash receipt, or a
    /// card receipt not joined yet), a card receipt waiting for its bank payment, and on a withdrawal's "covered by
    /// receipts" row the receipts that took the cash.
    var receiptId: String? = nil
    var provisional: Bool? = nil
    var coveredBy: [String]? = nil
    /// Phone mode (brief 32): a cash withdrawal (the shop list's cash rule), a source of the wallet.
    var cashWithdrawal: Bool? = nil

    /// Phone mode only: this payment's bank line when different from the shown name, and any own name's source.
    var bankName: String? = nil
    var isOwnName: Bool? = nil
    var ownNameSource: PaymentNameSource? = nil
    /// Opaque group identity; use as a dictionary key, never display it.
    var nameKey: String? = nil
    /// Phone mode only (brief 99): a bank payment's text as the bank wrote it (Verwendungszweck), for the quick sort's
    /// example lines. Nil for receipts, cash entries and server rows.
    var purpose: String? = nil

    /// A card receipt counted on its own until its bank payment comes.
    var isWaitingReceipt: Bool { provisional == true }
}

/// The Cash page's data (the engine's `cash`, brief 32): each month's numbers and every cash movement from the
/// wallet's side. Card receipts, joined receipts and entries in another currency are not movements.
nonisolated struct CashView: Codable, Equatable {
    /// By `YYYY-MM`: only months with a movement.
    let months: [String: CashMonth]
    /// By date, oldest first (on one day, money in first).
    var movements: [CashMovement]
}

/// One month of cash, in positive euros. `unaccounted`: what the month's withdrawals still hold after everything that
/// took from them (the number their category shows): in the wallet still, or spent without a receipt.
nonisolated struct CashMonth: Codable, Equatable {
    let withdrawn: Double
    let received: Double
    let spent: Double
    let unaccounted: Double

    static let none = CashMonth(withdrawn: 0, received: 0, spent: 0, unaccounted: 0)
}

/// One movement of the wallet.
nonisolated struct CashMovement: Codable, Equatable, Identifiable {
    enum Kind: String, Codable, Equatable {
        /// Cash from the bank (a payment).
        case withdrawal
        /// Cash received, entered by hand.
        case received
        /// A cash receipt.
        case receipt
        /// Cash spent, entered by hand.
        case manual
    }
    /// The payment's id (a withdrawal) or the receipt's.
    let id: String
    let date: String
    /// From the wallet's side: + in, − out.
    let amount: Double
    let kind: Kind
    var otherSide: Bool? = nil
    var place: String
    /// The category's name on the dashboard ("Uncategorised" for none).
    let category: String
    /// Money out: the sources it took from ([]: all from elsewhere); nil for money in.
    let paidFrom: [String]?
    /// Money in: the movements out that took from it; nil for money out.
    let coveredBy: [String]?
    /// Money in: what it still holds; nil for money out.
    let left: Double?

    var isSource: Bool { kind == .withdrawal || kind == .received }
    var month: String { String(date.prefix(7)) }
}

nonisolated struct Overview: Codable {
    let expense: [Double]
    let income: [Double]
    let balance: [Double]
}

nonisolated struct CategoryTotal: Codable, Identifiable {
    let name: String
    let total: Double
    var id: String { name }
}

nonisolated struct Totals: Codable {
    let expense: Double
    let income: Double
    let categories: [CategoryTotal]
    let incomeBuckets: [CategoryTotal]
}

nonisolated struct MonthData: Codable {
    let expense: Double
    let income: Double
    let categories: [CategoryTotal]
    let incomeBuckets: [CategoryTotal]
    let endBalance: Double
    let dayExpense: [Double]
    let dayExpenseRunning: [Double]
    let dayIncome: [Double]
    let dayBalance: [Double]

    var totals: Totals {
        Totals(expense: expense, income: income, categories: categories, incomeBuckets: incomeBuckets)
    }
}

nonisolated struct Series: Codable {
    let months: [Double]
    let days: [String: [Double]]
}

nonisolated enum DashboardError: LocalizedError {
    case unsupportedVersion, missingSample
    var errorDescription: String? {
        switch self {
        case .unsupportedVersion: String(localized: LocalizedStringResource("This dashboard version is not supported.",
                                                                            table: "AresiumShared",
                                                                            locale: .appLanguage))
        case .missingSample: String(localized: LocalizedStringResource("The bundled sample dashboard is missing.",
                                                                       table: "AresiumShared",
                                                                       locale: .appLanguage))
        }
    }
}

/// Where a bank payment's own name was saved (phone mode only).
nonisolated enum PaymentNameSource: String, Codable, Sendable { case shop, payment }

/// Separate positive money out and in, in euros.
nonisolated struct PaymentNameAmounts: Codable, Equatable, Sendable {
    var moneyOut: Double = 0
    var moneyIn: Double = 0
}

/// All counted payments of one name, over every dashboard month; rows newest first.
nonisolated struct PaymentNameGroup: Codable {
    let rows: [Transaction]
    let amounts: PaymentNameAmounts
    /// Every dashboard month, including months without a payment of this name.
    let months: [String: PaymentNameAmounts]
    /// Search spellings: shown names, every bank line and own name, including hidden own names. Phone mode only.
    var names: [String]? = nil
    var count: Int { rows.count }
    var moneyOut: Double { amounts.moneyOut }
    var moneyIn: Double { amounts.moneyIn }
}

/// The engine's applied links (euros), distinct from the ledger's decimal-string storage.
nonisolated struct PaymentLink: Codable, Equatable, Sendable {
    let payment: String
    let amount: Double
}

nonisolated struct PaybackIgnored: Codable, Equatable, Sendable {
    let from: String
    let to: String
    let reason: String
    let amount: Double?
}
