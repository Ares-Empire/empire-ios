import Foundation

// The shared engine's values as they cross the bridge (JSON), mirroring aresium/src/engine (index.ts and the files it
// exports). Field names are the engine's; optional fields the engine leaves out stay out when encoded, so a value passed
// back (a saved layout, say) reaches the engine exactly as it came.

// MARK: - categories (aresium/src/engine/categories.ts)

nonisolated struct EngineCategory: Codable, Equatable, Sendable {
    struct Names: Codable, Equatable, Sendable {
        let en: String
        let de: String
    }
    let id: String
    let name: Names
    /// The group in the picker ("Everyday", "Home", …): the engine's English word, worded by the app (`CategoryGroup`).
    let group: String
    /// "spend", "income" or "transfer": how it counts.
    let kind: String

    func name(in language: AppLanguage) -> String { language == .german ? name.de : name.en }
}

/// A category's icon (a Lucide name, mapped by `CategorySymbol`) and colour (`#RRGGBB`).
nonisolated struct CategoryLook: Codable, Equatable, Sendable {
    let icon: String
    let color: String
}

/// Everything the engine says about categories, read once per engine: the default list, the two built-ins, their looks
/// and the look of a person's own category.
nonisolated struct CategoryCatalog: Codable, Equatable, Sendable {
    let defaults: [EngineCategory]
    let builtIns: [EngineCategory]
    let looks: [String: CategoryLook]
    let custom: CategoryLook

    /// The built-in category for money between one's own accounts (`OWN_TRANSFERS`).
    static let ownTransfers = "own-transfers"
    /// The built-in "Not sorted"; the app keeps such payments without a category (see `PhoneCategoryList`).
    static let notSorted = "not-sorted"

    func category(_ id: String) -> EngineCategory? {
        defaults.first { $0.id == id } ?? builtIns.first { $0.id == id }
    }

    func look(_ id: String) -> CategoryLook { looks[id] ?? custom }
}

// MARK: - bank files (aresium/src/engine/readers/types.ts)

/// One payment as a reader read it. Dates are ISO strings (midnight UTC for a plain date), amounts decimal strings
/// ("-12.30"), exactly as the engine wrote them.
nonisolated struct BankTxn: Codable, Equatable, Sendable {
    let externalId: String
    let bookingDate: String
    var valueDate: String?
    let amount: String
    var balance: String?
    let currency: String
    let description: String
    var counterparty: String?
    /// The other party's IBAN (checked, no spaces, upper case), where the file has one: the own-transfer proof.
    var counterpartyIban: String?
    var raw: JSONValue?

    /// The booking day, `YYYY-MM-DD`.
    var day: String { String(bookingDate.prefix(10)) }
}

nonisolated struct BankAccount: Codable, Equatable, Sendable {
    var iban: String?
    var name: String?
    var currency: String?
}

nonisolated struct BankName: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

/// What `readBankFile` returns. An unknown CSV comes back without payments and with `needsLayout`: the person confirms
/// a layout, which is saved, and the file is read again with it.
nonisolated struct BankFile: Codable, Equatable, Sendable {
    /// "camt", "mt940", "paypal" or "csv".
    let format: String
    var bank: BankName?
    var account: BankAccount?
    let transactions: [BankTxn]
    var skipped: Int?
    var layout: CsvLayout?
    var encoding: String?
    var needsLayout: LayoutGuess?

    /// The export a payment came from, as the sorting rules name it: PayPal's own export, or a bank's.
    var source: String { format == "paypal" ? "paypal" : "bank" }
}

/// A CSV table's layout (`CsvLayout` in types.ts): which column holds what. Columns count from 0 in the header row.
nonisolated struct CsvLayout: Codable, Equatable, Sendable {
    struct Columns: Codable, Equatable, Sendable {
        var date: Int
        var valueDate: Int?
        var amount: Int?
        var debit: Int?
        var credit: Int?
        var sign: Int?
        var counterparty: [Int]?
        var payer: Int?
        var payee: Int?
        var text: [Int]?
        var kind: Int?
        var iban: Int?
        var accountIban: Int?
        var balance: Int?
        var currency: Int?
        var reference: Int?
        var status: Int?
        var fees: [Int]?
        var addAmounts: [Int]?
    }

    struct LabelledText: Codable, Equatable, Sendable {
        let labels: [String]
        let counterparty: [String]
        let text: [String]
    }

    var version = 1
    var name: String?
    var profile: String?
    var separator: String
    var header: [String]
    var columnCount: Int?
    var dateFormat: String
    var numberFormat: String
    var columns: Columns
    var skipStatus: [String]?
    var keepStatus: [String]?
    var invertSign: Bool?
    var labelledText: LabelledText?
    var currency: String?
}

/// What the layout guesser saw in one column (`ColumnInfo`).
nonisolated struct ColumnInfo: Codable, Equatable, Sendable {
    let index: Int
    let header: String
    /// "date", "amount", "iban", "sign", "currency", "text", "number" or "empty".
    let kind: String
    let samples: [String]
    var dateFormat: String?
}

/// An unknown CSV's guessed layout (`LayoutGuess`), for the person to confirm or change.
nonisolated struct LayoutGuess: Codable, Equatable, Sendable {
    var layout: CsvLayout?
    let confidence: Double
    let unsure: [String]
    let missing: [String]
    let separator: String
    let header: [String]
    let headerRow: Int
    let columns: [ColumnInfo]
    let preview: [BankTxn]
}

// MARK: - readings of an unknown file (aresium/src/engine/readers/readings.ts)

/// What a reading changes in the guessed layout (`ReadingReason`). `other` stands for a reason a newer engine might add,
/// so an unknown word never breaks the whole answer.
nonisolated enum ReadingReason: String, Codable, Equatable, Sendable, CaseIterable {
    /// Day and month the other way round (03/04 is 3 April or 4 March).
    case dateFormat
    /// Money out and money in the other way round (or read from two columns).
    case debitCredit
    /// Another amount column is the payment's amount.
    case amount
    /// A column of S/H, Soll/Haben, Lastschrift/Gutschrift marks says which way the money went.
    case sign
    /// Every amount the other way round (cards that list purchases as positive amounts).
    case invertSign
    /// The other party and the payment text the other way round.
    case counterpartyText
    /// Another text column is the other party.
    case counterparty
    /// The booking date and the value date the other way round.
    case valueDate
    case other

    init(from decoder: Decoder) throws {
        self = ReadingReason(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
    }
}

/// One way of reading an unknown CSV (`FileReading`): a complete layout, ready to save, and the first payments it reads
/// (at most 5). `reason` is nil for the engine's own guess, which comes first whenever it reads the file.
nonisolated struct FileReading: Codable, Equatable, Sendable {
    let reason: ReadingReason?
    let layout: CsvLayout
    let preview: [BankTxn]
}

/// `shareableLayout`'s answer: the layout as it may be sent (without `name` and `profile`), or why it may not
/// (`iban`, `email`, `date`, `amount`, `digits`, `tooLong`, `tooWide`, `tooLarge`, `invalid`).
nonisolated enum ShareCheck: Decodable, Equatable, Sendable {
    case shareable(CsvLayout)
    case notShareable(reason: String)

    private enum CodingKeys: String, CodingKey { case ok, layout, reason }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if try container.decode(Bool.self, forKey: .ok) {
            self = .shareable(try container.decode(CsvLayout.self, forKey: .layout))
        } else {
            self = .notShareable(reason: try container.decodeIfPresent(String.self, forKey: .reason) ?? "invalid")
        }
    }
}

// MARK: - sorting (aresium/src/engine/sorting)

/// A payment as the sorting rules see it (`TransferPayment` in sorting/transfers.ts): the text for the shop rules and
/// learned merchants; the account, its IBAN, the other party's IBAN, the signed amount and the date for the
/// own-transfer rules; the original row for PayPal's funding rows.
nonisolated struct SortingPayment: Codable, Equatable, Sendable {
    var counterparty: String?
    var description: String
    /// "bank" or "paypal".
    var source: String
    var account: String
    /// The account's own IBAN, when the file named it.
    var accountIban: String?
    var counterpartyIban: String?
    /// Negative = money out.
    var amount: Double
    var currency: String
    /// `YYYY-MM-DD`.
    var date: String
    var raw: JSONValue?
}

/// One payment's category from `sortPayments`, and the layer that chose it ("structural", "learned", "starter"), or
/// none.
nonisolated struct SortResult: Codable, Equatable, Sendable {
    let categoryId: String?
    let source: String?
}

// MARK: - the dashboard's input (aresium/src/engine/source.ts)

/// One stored payment for `buildDashboardSource` (`SourcePayment`).
nonisolated struct SourcePayment: Codable, Equatable, Sendable {
    let id: String
    let externalId: String
    /// `YYYY-MM-DD`.
    let date: String
    let amount: Double
    let currency: String
    var balance: Double?
    let description: String
    var counterparty: String?
    var city: String?
    var raw: JSONValue?
    /// The category's name on the person's list, or nil while it has none ("Uncategorised" in the dashboard).
    var category: String?
    var tags: [String]
}

/// A category on the person's list, with its look (`SourceCategory`).
nonisolated struct SourceCategory: Codable, Equatable, Sendable {
    let name: String
    let icon: String
    let color: String
    let excludeFromTotals: Bool
}

nonisolated struct DashboardSourceInput: Codable, Equatable, Sendable {
    let transactions: [SourcePayment]
    let categories: [SourceCategory]
    /// Today, `YYYY-MM-DD`: the current month counts up to this day.
    let today: String
}
