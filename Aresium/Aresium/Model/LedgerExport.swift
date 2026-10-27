import Foundation

/// Settings → Export: everything Aresium keeps on this iPhone for one account, as one JSON file the person keeps
/// themselves (`Aresium-<date>.json`, through the share sheet). Restoring reads it back into an empty store, checked
/// first, all or nothing. Schema version 1; a change to these fields (or to `LedgerPayment`, `LedgerAccount`,
/// `ChosenCategory`, `LearnedRule`, `CsvLayout`) is a new version, and `restore` keeps reading version 1.
nonisolated struct LedgerExport: Codable, Equatable, Sendable {
    static let currentSchema = 1
    static let appName = "Aresium"

    var app = Self.appName
    var schema = Self.currentSchema
    /// The day it was made, `YYYY-MM-DD`.
    var exported: String
    var accounts: [LedgerAccount]
    var payments: [LedgerPayment]
    var categories: [ChosenCategory]
    var learned: [LearnedRule]
    var layouts: [CsvLayout]

    /// The file's name: `Aresium-2026-10-27.json`.
    var fileName: String { "Aresium-\(exported).json" }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    /// Reads an export; anything that is not one (another JSON, another schema) is `invalidExport`.
    static func decode(_ data: Data) throws -> LedgerExport {
        let export: LedgerExport
        do { export = try JSONDecoder().decode(LedgerExport.self, from: data) }
        catch { throw LedgerError.invalidExport("not an export: \(error)") }
        guard export.app == appName else { throw LedgerError.invalidExport("app \(export.app)") }
        guard export.schema == currentSchema else { throw LedgerError.invalidExport("schema \(export.schema)") }
        return export
    }

    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// Checks that the export holds together before anything is written: ids and payment keys unique, every payment on
    /// one of its accounts, dates and amounts readable, categories known (a default or built-in one, or one's own on
    /// its list), sources known.
    func validate(catalog: CategoryCatalog) throws {
        func fail(_ reason: String) -> LedgerError { .invalidExport(reason) }
        let accountIDs = Set(accounts.map(\.id))
        guard accountIDs.count == accounts.count else { throw fail("duplicate account") }
        let chosenIDs = Set(categories.map(\.id))
        guard chosenIDs.count == categories.count else { throw fail("duplicate category") }
        let known = Set(catalog.defaults.map(\.id))
        for category in categories {
            if ChosenCategory.isCustom(category.id) {
                guard let name = category.name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
                    throw fail("custom category without a name")
                }
            } else if !known.contains(category.id) {
                throw fail("unknown category \(category.id)")
            }
        }
        // Payments may be in a chosen category or a built-in one (own transfers); learned rules may also point at a
        // default category that is not ticked now (they wait for it).
        let paymentCategories = chosenIDs.union([CategoryCatalog.ownTransfers])
        let ruleCategories = paymentCategories.union(known)
        var ids = Set<String>(), keys = Set<String>()
        for payment in payments {
            guard ids.insert(payment.id).inserted, keys.insert(payment.key).inserted else { throw fail("duplicate payment") }
            guard accountIDs.contains(payment.account) else { throw fail("payment without its account") }
            guard ["bank", "paypal"].contains(payment.source), !payment.externalId.isEmpty else { throw fail("payment source") }
            guard Self.isDay(payment.bookingDate), payment.valueDate.map(Self.isDay) ?? true else { throw fail("payment date") }
            guard Self.isAmount(payment.amount), payment.balance.map(Self.isAmount) ?? true else { throw fail("payment amount") }
            if let category = payment.category {
                guard paymentCategories.contains(category) else { throw fail("payment category \(category)") }
            }
            guard payment.extraCategories.allSatisfy(chosenIDs.contains) else { throw fail("payment extra category") }
            guard (payment.category == nil) == (payment.categorySource == .none) else { throw fail("category source") }
        }
        var merchants = Set<String>()
        for rule in learned {
            guard !rule.merchant.isEmpty, merchants.insert(rule.merchant).inserted, ruleCategories.contains(rule.category)
            else { throw fail("learned rule") }
        }
    }

    /// `YYYY-MM-DD`, a real calendar day.
    static func isDay(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard value.count == 10, parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]),
              (1...12).contains(month), day >= 1 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        guard let date = calendar.date(from: DateComponents(year: year, month: month)),
              let days = calendar.range(of: .day, in: .month, for: date)?.count else { return false }
        return day <= days
    }

    /// A plain decimal string as the engine writes them: "-12.30", "1080.00".
    static func isAmount(_ value: String) -> Bool {
        value.wholeMatch(of: /-?\d+(\.\d+)?/) != nil
    }
}
