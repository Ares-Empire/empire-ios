import Foundation

// Monthly average and fixed costs on screen (brief 209, Patrik 2026-11-02 after build 18: "lets do monthly and fixcost
// screen feature first"). Brief 208 counts (`MonthlyAverage`, `FixedCosts`); this file decides what the Overview's
// line under a side's total and the fixed costs page say, in both languages (pure, so tests pin them). The look is
// `Screens/FixedCostScreens.swift`.

extension DashboardRoute {
    /// The fixed costs page (brief 209; the income side's is Regular income), pushed from the Overview's line.
    static func fixedCosts(_ side: DashboardSide) -> DashboardRoute {
        DashboardRoute(category: "", side: side, fixedCosts: true)
    }
}

/// The Overview's quiet line under a side's total: "Avg. €1,940 a month · €860 fixed" / "Ø 1.940 € im Monat · davon
/// 860 € fix" (income "… · €1,300 regular" / "… · davon 1.300 € regelmäßig"). The fixed part opens the fixed costs.
struct AverageLine: Equatable {
    let average: String
    /// The fixed (or regular) part; nil without one running (server mode, none found, every one ended).
    let fixed: String?
    /// VoiceOver: the average says it counts the finished months only (said once, here, not on the screen).
    let averageSpoken: String
    let fixedSpoken: String?

    /// Only on Overview (Current and a month's page are one month), only with an average (two finished months).
    init?(average: MonthlyAverage?, fixedCosts: FixedCostList?, side: DashboardSide, scope: DashboardScope,
          language: AppLanguage = .current) {
        guard scope == .overview, let average else { return nil }
        self.average = FixedCostWords.average(average.cents, language: language)
        averageSpoken = FixedCostWords.averageSpoken(average.cents, language: language)
        let cents = AverageLine.fixedCents(fixedCosts)
        fixed = cents.map { FixedCostWords.fixedPart($0, side: side, language: language) }
        fixedSpoken = cents.map { FixedCostWords.fixedSpoken($0, side: side, language: language) }
    }

    /// The monthly total while any entry is running, a taken-out one too: the person who took every one out still finds
    /// the page (at €0) to count one again.
    static func fixedCents(_ list: FixedCostList?) -> Int? {
        guard let list, (list.running + list.takenOut).contains(where: \.running) else { return nil }
        return list.monthlyCents
    }
}

/// The fixed costs page of one side: the monthly total with its year, the running entries, then Ended and Not counted.
nonisolated struct FixedCostPage {
    /// What a row's long press does.
    enum Change: Equatable {
        /// Running or ended: Not fixed / Not regular.
        case takeOut
        /// Taken out: Count again.
        case countAgain
    }

    struct Row: Identifiable {
        let entry: FixedCostEntry
        let name: String
        /// As a payment shows it: "−780.00", "+2,450.00".
        let amount: String
        /// "monthly · next 2 Dec", "monthly · last 10 Jul".
        let line: String
        /// Not monthly: what it makes a month, "€41.58 a month".
        let share: String?
        /// Ended or taken out: drawn quieter, its amount in the muted ink.
        let quiet: Bool
        let change: Change
        /// VoiceOver reads the row as one: name, amount, how often, next due (and the share).
        let spoken: String
        /// The row's place on the page: an entry taken out (or counted again) is a new row in its new section, never
        /// the old one moved (one list holds the three sections, and a lazy list kept the old row's look).
        var id: String { "\(section)\u{1F}\(entry.id)" }
        private var section: String { change == .countAgain ? "takenOut" : quiet ? "ended" : "running" }
        /// The quiet line in one piece, where it fits: "yearly · next 15 Oct 2027 · €41.58 a month".
        var oneLine: String { ([line] + (share.map { [$0] } ?? [])).joined(separator: " · ") }
    }

    let side: DashboardSide
    let running: [Row]
    let ended: [Row]
    let takenOut: [Row]
    /// "€1,084" and "€13,008 a year"; the monthly total over the running entries not taken out.
    let total: String
    let year: String
    var isEmpty: Bool { running.isEmpty && ended.isEmpty && takenOut.isEmpty }

    init(list: FixedCostList, side: DashboardSide, today: String = ReceiptDay.day(.now),
         language: AppLanguage = .current) {
        self.side = side
        func row(_ entry: FixedCostEntry, change: Change) -> Row {
            FixedCostPage.row(entry, side: side, change: change, today: today, language: language)
        }
        running = list.running.map { row($0, change: .takeOut) }
        ended = list.ended.map { row($0, change: .takeOut) }
        takenOut = list.takenOut.map { row($0, change: .countAgain) }
        total = Money.total(Double(list.monthlyCents) / 100, language: language)
        year = FixedCostWords.perYear(list.monthlyCents * 12, language: language)
    }

    private static func row(_ entry: FixedCostEntry, side: DashboardSide, change: Change, today: String,
                            language: AppLanguage) -> Row {
        let signed = side == .expenses ? -entry.amount : entry.amount
        let amount = Money.transaction(signed, language: language)
        let parts = FixedCostWords.lineParts(entry, today: today, language: language)
        let line = parts.joined(separator: " · ")
        let share = entry.cadence == .monthly ? nil : FixedCostWords.share(entry.monthlyCents, language: language)
        // Commas for VoiceOver, where the screen's middle dots would be read out or run together.
        let spoken = ([entry.name, amount] + parts + [share].compactMap { $0 }).joined(separator: ", ")
        return Row(entry: entry, name: entry.name, amount: amount, line: line, share: share,
                   quiet: !entry.running || entry.notFixed, change: change, spoken: spoken)
    }
}

/// The words of the line and the page (English here, German in the catalog).
nonisolated enum FixedCostWords {
    /// The header's title.
    static func title(_ side: DashboardSide, language: AppLanguage = .current) -> String {
        side == .expenses ? language.string("Fixed costs") : language.string("Regular income")
    }

    // MARK: the Overview's line

    /// "Avg. €1,940 a month" / "Ø 1.940 € im Monat" (whole euros, as the total above it).
    static func average(_ cents: Int, language: AppLanguage = .current) -> String {
        let money = euros(cents, language)
        return language.string("Avg. \(money) a month")
    }

    static func averageSpoken(_ cents: Int, language: AppLanguage = .current) -> String {
        let money = euros(cents, language)
        return language.string("Average of the finished months: \(money) a month")
    }

    /// "€860 fixed" / "davon 860 € fix"; income "€1,300 regular" / "davon 1.300 € regelmäßig".
    static func fixedPart(_ cents: Int, side: DashboardSide, language: AppLanguage = .current) -> String {
        let money = euros(cents, language)
        return side == .expenses ? language.string("\(money) fixed") : language.string("\(money) regular")
    }

    /// The fixed part's button for VoiceOver: "Fixed costs: €860 a month".
    static func fixedSpoken(_ cents: Int, side: DashboardSide, language: AppLanguage = .current) -> String {
        let money = euros(cents, language)
        return side == .expenses ? language.string("Fixed costs: \(money) a month")
                                 : language.string("Regular income: \(money) a month")
    }

    // MARK: the page

    /// The caption beside the page's total: "a month" / "im Monat".
    static func perMonth(language: AppLanguage = .current) -> String { language.string("a month") }

    /// Under the total: "€13,008 a year" / "13.008 € im Jahr".
    static func perYear(_ cents: Int, language: AppLanguage = .current) -> String {
        let money = euros(cents, language)
        return language.string("\(money) a year")
    }

    /// A row's quiet line in two parts: how often, then the next day due ("monthly", "next 3 Dec"), or for one that
    /// ended or whose next due day has passed, its last payment ("last 3 Aug"). The screen joins them with a middle
    /// dot, VoiceOver with a comma. Running status still follows the ledger's reference day, independently of today.
    static func lineParts(_ entry: FixedCostEntry, today: String = ReceiptDay.day(.now),
                          language: AppLanguage = .current) -> [String] {
        let when = entry.running && entry.nextDue >= today
            ? FixedCostWording.nextDue(entry.nextDue, referenceDay: today, language: language)
            : FixedCostWording.last(entry.last, referenceDay: today, language: language)
        return [FixedCostWording.cadence(entry.cadence, language: language), when]
    }

    /// What one that is not monthly makes a month, to the cent: "€41.58 a month" / "41,58 € im Monat".
    static func share(_ monthlyCents: Int, language: AppLanguage = .current) -> String {
        let money = Money.precise(Double(monthlyCents) / 100, language: language)
        return language.string("\(money) a month")
    }

    static func endedHeading(language: AppLanguage = .current) -> String { language.string("Ended") }
    static func takenOutHeading(language: AppLanguage = .current) -> String { language.string("Not counted") }

    /// At the page's end, once: how they are found, and the long press.
    static func howFound(language: AppLanguage = .current) -> String {
        language.string("Found in payments of the same name with about the same amount at the same interval, monthly to yearly. Hold a row to take it out.")
    }

    /// Nothing found yet: when one shows up.
    static func empty(_ side: DashboardSide, language: AppLanguage = .current) -> String {
        side == .expenses
            ? language.string("No fixed costs found yet. They show up after three payments of one name at the same interval, a yearly one after two.")
            : language.string("No regular income found yet. It shows up after three payments of one name at the same interval, a yearly one after two.")
    }

    /// The long press's entry.
    static func change(_ change: FixedCostPage.Change, side: DashboardSide, language: AppLanguage = .current) -> String {
        switch change {
        case .takeOut: side == .expenses ? language.string("Not fixed") : language.string("Not regular")
        case .countAgain: language.string("Count again")
        }
    }

    /// The undo bar's line after it.
    static func done(_ change: FixedCostPage.Change, name: String, side: DashboardSide,
                     language: AppLanguage = .current) -> String {
        switch change {
        case .takeOut:
            side == .expenses ? language.string("\(name) taken out of fixed costs.")
                              : language.string("\(name) taken out of regular income.")
        case .countAgain: language.string("\(name) counted again.")
        }
    }

    /// The store changed between the page and the long press (an import meanwhile): nothing was saved.
    static func changedMeanwhile(language: AppLanguage = .current) -> String {
        language.string("The payments changed meanwhile. Try again.")
    }

    private static func euros(_ cents: Int, _ language: AppLanguage) -> String {
        Money.total(Double(cents) / 100, language: language)
    }
}

extension DashboardStore {
    /// Use the phone dashboard's clock for row wording too, independently of the newest imported payment.
    func fixedCostPage(side: DashboardSide, language: AppLanguage = .current) -> FixedCostPage? {
        guard let list = fixedCosts(side: side) else { return nil }
        return FixedCostPage(list: list, side: side, today: phone?.today() ?? ReceiptDay.day(.now), language: language)
    }
}
