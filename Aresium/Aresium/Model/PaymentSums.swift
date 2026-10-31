import Foundation
import Observation

// Adding up the payments of one name inside a category's list (brief 53, Patrik's D after build 4, 2026-10-30): ten
// Vinted purchases in Clothes in October show as one row with their sum and a mark that they are several; a tap opens
// them in place, and the swipe or the long press makes them single rows again. Only how a list shows: totals, the
// category's numbers, the export and the engine never change.

/// Who adds up what: four levels, the more specific wins. Everywhere (Settings → Dashboard), a category (the icon at the
/// top of its payments), a name (the switch on the name's page), a name in a category (the swipe and the long press).
/// Every level but everywhere is on, off or not set; a choice equal to what the levels above give is not set, so making
/// a name "normal again" (Separate after Add up, a switch back) leaves nothing behind that would outvote a later choice
/// (fix 58, Patrik 2026-10-31: the icon did nothing after Vinted was added up and separated by hand). Categories are keyed
/// by `DashboardStore.sumCategoryKey` (their stable id), names by the rows' opaque `nameKey`, never parsed.
nonisolated struct SumChoices: Codable, Equatable, Sendable {
    var everywhere = false
    var categories: [String: Bool] = [:]
    var names: [String: Bool] = [:]
    /// A name in a category: by category key, then by name key.
    var pairs: [String: [String: Bool]] = [:]

    /// Whether this name's payments in this category's list show as one row (when it has two or more there).
    func sums(name: String, category: String) -> Bool {
        pairs[category]?[name] ?? names[name] ?? categories[category] ?? everywhere
    }

    /// What the category's icon shows for a list: on when every name with two or more payments there adds up, which is
    /// what the list shows (not the category's own choice, which a name's choice can outvote).
    func sumsAll(_ names: [String], in category: String) -> Bool {
        !names.isEmpty && names.allSatisfy { sums(name: $0, category: category) }
    }

    /// What the name's page's switch shows: the name's own choice, else everywhere's.
    func sumsName(_ name: String) -> Bool { names[name] ?? everywhere }

    /// The category's icon over a list whose names with two or more payments are `names`: the opposite of what it shows,
    /// for every name there and the names to come. The category takes it, the choices of single names in it are cleared,
    /// and a name whose own choice (its page's switch) says otherwise gets the tap's choice in this category, so the tap
    /// always means all or none here.
    mutating func toggleCategory(_ category: String, names: [String]) {
        let target = !sumsAll(names, in: category)
        categories[category] = target == everywhere ? nil : target
        pairs[category] = nil
        for name in names where (self.names[name] ?? target) != target {
            pairs[category, default: [:]][name] = target
        }
    }

    /// The name's page's switch: the name in every category, its choices in single categories cleared.
    mutating func setName(_ name: String, sums: Bool) {
        names[name] = sums == everywhere ? nil : sums
        for category in pairs.keys { pairs[category]?[name] = nil }
        pairs = pairs.filter { !$0.value.isEmpty }
    }

    /// The swipe's and the long press's Add up and Separate: this name in this category, every month. Separate after
    /// Add up (or the other way round) leaves the name as the levels above have it.
    mutating func setName(_ name: String, in category: String, sums: Bool) {
        if sums == (names[name] ?? categories[category] ?? everywhere) {
            pairs[category]?[name] = nil
            if pairs[category]?.isEmpty == true { pairs[category] = nil }
        } else {
            pairs[category, default: [:]][name] = sums
        }
    }
}

/// The choices as the app keeps them: the person's in the app's defaults (`aresium.sums`; a view choice like the graph,
/// so not in the export; deleted with Aresium's data), or an empty set in memory for the tour, tests and the samples, which
/// never read or change the person's.
@MainActor @Observable
final class PaymentSums {
    static let key = "aresium.sums"

    private(set) var choices: SumChoices
    /// Counts every change, so a list built from the choices is built again only after one.
    private(set) var revision = 0
    @ObservationIgnored private let defaults: UserDefaults?

    /// The person's choices, read from and written to `defaults`.
    init(defaults: UserDefaults) {
        self.defaults = defaults
        isOffered = true
        choices = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode(SumChoices.self, from: $0) }
            ?? SumChoices()
    }

    /// Choices in memory only (empty unless given: the samples' launch arguments, the tour's own). `offered: false`: the
    /// lists offer no adding up at all.
    init(choices: SumChoices = SumChoices(), offered: Bool = true) {
        defaults = nil
        self.choices = choices
        isOffered = offered
    }

    /// Told after every change (the tour moves on when a name is added up, brief 59). Nil outside the tour.
    @ObservationIgnored var onChange: (() -> Void)?

    /// Whether the choices are kept beyond this launch.
    var isKept: Bool { defaults != nil }
    /// Whether the lists offer adding up.
    let isOffered: Bool

    func setEverywhere(_ on: Bool) { change { $0.everywhere = on } }
    func toggleCategory(_ category: String, names: [String]) { change { $0.toggleCategory(category, names: names) } }
    func setName(_ name: String, sums: Bool) { change { $0.setName(name, sums: sums) } }
    func setName(_ name: String, in category: String, sums: Bool) { change { $0.setName(name, in: category, sums: sums) } }

    /// Delete Aresium's data on this iPhone (Settings, the lock's "Forgot the code?"): the choices go with it.
    func deleteAll() {
        choices = SumChoices()
        revision &+= 1
        defaults?.removeObject(forKey: Self.key)
    }

    private func change(_ body: (inout SumChoices) -> Void) {
        var next = choices
        body(&next)
        guard next != choices else { return }
        choices = next
        revision &+= 1
        if let defaults, let data = try? JSONEncoder().encode(next) { defaults.set(data, forKey: Self.key) }
        onChange?()
    }
}

// MARK: - the list

/// One name's payments in a category's list, shown as one row: the name as its newest payment shows it, the count, the
/// net sum (a refund among purchases lowers it) and the days.
struct SummedPayments: Identifiable {
    /// The name's `nameKey`.
    let key: String
    /// Its payments in the list's order (oldest first, as the list), shown below the row when it is open.
    let rows: [TransactionRow]
    /// The net sum in cents (integer cents, as the name's page counts, so no floating point errors add up).
    let cents: Int

    init(key: String, rows: [TransactionRow]) {
        self.key = key
        self.rows = rows
        cents = rows.reduce(0) { $0 + Int(($1.transaction.amount * 100).rounded()) }
    }

    var id: String { "sum:" + key }
    var count: Int { rows.count }
    var total: Double { Double(cents) / 100 }
    /// The newest payment: the summed row stands where it would, and shows its name.
    var newest: Transaction { rows[rows.count - 1].transaction }
    var title: String { newest.place }
    var firstDay: String { rows[0].transaction.date }
    var lastDay: String { newest.date }
}

/// A row of a category's list: a payment (with whether its name has more payments here, so Add up is offered), or a
/// name's payments added up.
enum PaymentListEntry: Identifiable {
    case payment(TransactionRow, addsUp: Bool)
    case summed(SummedPayments)

    var id: String {
        switch self {
        case let .payment(row, _): row.id
        case let .summed(sum): sum.id
        }
    }

    /// The name the row shows (screenshots pick rows by it).
    var title: String {
        switch self {
        case let .payment(row, _): row.transaction.place
        case let .summed(sum): sum.title
        }
    }
}

/// A category's payments in one month as the list shows them: every name with two or more payments here that adds up
/// (`sums`, the choices) is one row where its newest payment would be; a name with one payment, a payment without a name
/// and a withdrawal's covered row stay single. Built once per change of the dashboard or the choices
/// (`DashboardStore.paymentList`), never per row or per `body`.
struct PaymentList {
    let rows: [TransactionRow]
    let entries: [PaymentListEntry]
    /// The names with two or more payments here, in the list's order: what the category's icon adds up or separates.
    let sumKeys: [String]
    /// Some name has two or more payments here: the category's icon shows.
    var canSum: Bool { !sumKeys.isEmpty }
    /// Every such name shows as one row: the category's icon shows on.
    let allSummed: Bool

    /// `offered: false` (server mode, the tour): every row single, no Add up.
    init(rows: [TransactionRow], offered: Bool = true, sums: (String) -> Bool) {
        self.rows = rows
        var positions: [String: [Int]] = [:]
        for (index, row) in rows.enumerated() where offered {
            if let key = Self.nameKey(row.transaction) { positions[key, default: []].append(index) }
        }
        let several = positions.filter { $0.value.count > 1 }
        let summed = Set(several.keys.filter(sums))
        var entries: [PaymentListEntry] = []
        for (index, row) in rows.enumerated() {
            guard let key = Self.nameKey(row.transaction), let members = several[key] else {
                entries.append(.payment(row, addsUp: false))
                continue
            }
            guard summed.contains(key) else {
                entries.append(.payment(row, addsUp: true))
                continue
            }
            if index == members.last { entries.append(.summed(SummedPayments(key: key, rows: members.map { rows[$0] }))) }
        }
        self.entries = entries
        var seen = Set<String>()
        sumKeys = rows.compactMap { row in
            guard let key = Self.nameKey(row.transaction), several[key] != nil, seen.insert(key).inserted else { return nil }
            return key
        }
        allSummed = !several.isEmpty && summed.count == several.count
    }

    static let empty = PaymentList(rows: [], sums: { _ in false })

    /// The name a row adds up under: its `nameKey`; none for a withdrawal's covered row (it is the receipts', not a
    /// payment).
    static func nameKey(_ transaction: Transaction) -> String? {
        transaction.coveredBy == nil ? transaction.nameKey : nil
    }

    /// The summed row of this name, if the name is summed here.
    func summed(_ key: String) -> SummedPayments? {
        for case let .summed(sum) in entries where sum.key == key { return sum }
        return nil
    }
}

/// Which list (`DashboardStore.paymentList`).
struct PaymentListKey: Hashable {
    let category: String
    let month: String
    let side: DashboardSide
}

/// The lists built since the dashboard (`DashboardStore.revision`) or the choices (`PaymentSums.revision`) last changed.
struct PaymentListCache {
    var revision = -1
    var sums = -1
    var lists: [PaymentListKey: PaymentList] = [:]
}

extension DashboardStore {
    /// A category's payments in one month with the names added up as chosen (brief 53). Built the first time it is asked
    /// for after the dashboard or the choices changed, then kept: the header's icon and the list read the same one.
    /// Reading it makes a view follow both changes.
    func paymentList(category: String, month: String, side: DashboardSide) -> PaymentList {
        let revision = revision, sumsRevision = sums.revision
        if builtLists.revision != revision || builtLists.sums != sumsRevision {
            builtLists = PaymentListCache(revision: revision, sums: sumsRevision)
        }
        let key = PaymentListKey(category: category, month: month, side: side)
        if let list = builtLists.lists[key] { return list }
        let categoryKey = sumCategoryKey(category)
        let choices = sums.choices, offered = offersSums
        let list = PaymentList(rows: transactions(category: category, month: month, side: side), offered: offered) {
            choices.sums(name: $0, category: categoryKey)
        }
        builtLists.lists[key] = list
        return list
    }

    /// A category's key for the choices: in phone mode its id (Clothes and Kleidung are one, and one's own category keeps
    /// it), which survives a language switch and its shown name changing; otherwise (the dashboard's own entries such as
    /// Refunds, server mode) its name, which the engine keeps in both languages.
    func sumCategoryKey(_ name: String) -> String {
        if let phone, let catalog = phone.catalog,
           let id = PhoneCategoryList(catalog: catalog, chosen: phone.summary.chosen).id(named: name) {
            return "id:" + id
        }
        return "name:" + name
    }

    /// Names add up only where they exist: phone mode (server rows carry no name key); in the tour on its own choices.
    var offersSums: Bool { phone != nil && sums.isOffered }

    /// The long press of a row in a category's list: what its page offers, with Add up before "All with this name" when
    /// its name has more payments here; a summed row's: Separate, and "All with this name" as its payments' rows have it.
    func rowActions(for entry: PaymentListEntry) -> [PaymentRowAction] {
        switch entry {
        case let .payment(row, addsUp):
            var actions = rowActions(for: row.transaction)
            if addsUp { actions.insert(.addUp, at: actions.firstIndex(of: .allFromName) ?? actions.endIndex) }
            return actions
        case let .summed(sum):
            return [.separate] + (nameRoute(for: sum.newest) == nil ? [] : [.allFromName])
        }
    }
}

// MARK: - words

/// The words of adding up, in the app's language (English here, German in the catalog).
enum SumWording {
    /// The swipe's and the long press's action on a single payment ("Summieren").
    static func addUp(language: AppLanguage = .current) -> String { language.string("Add up") }
    /// On a summed row: back to single payments ("Auflösen", Patrik's word).
    static func separate(language: AppLanguage = .current) -> String { language.string("Separate") }

    /// The summed row's mark: "10×".
    static func count(_ count: Int) -> String { "\(count)×" }

    /// The summed row's second line: the days of its payments, "4–28 Oct" / "4.–28. Okt.", or one day.
    static func days(from first: String, to last: String, language: AppLanguage = .current) -> String {
        guard let start = ReceiptDay.date(first), let end = ReceiptDay.date(last) else { return "" }
        let calendar = ReceiptDay.calendar
        if calendar.isDate(start, inSameDayAs: end) || end < start {
            return end.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                                  calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated))
        }
        return (start..<end).formatted(Date.IntervalFormatStyle(locale: language.locale, calendar: calendar,
                                                                timeZone: calendar.timeZone).day().month(.abbreviated))
    }

    /// VoiceOver's reading of a summed row: "REWE, 5 payments, 4–28 Oct, −212.53".
    static func spoken(_ sum: SummedPayments, language: AppLanguage = .current) -> String {
        [sum.title, language.string("\(sum.count) payments"), days(from: sum.firstDay, to: sum.lastDay, language: language),
         Money.transaction(sum.total, language: language)].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
