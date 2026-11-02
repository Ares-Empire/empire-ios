import Foundation
import Testing
@testable import Aresium

/// Brief 209: the Overview's line under a side's total and the fixed costs page, on brief 208's numbers. Made-up data.
@MainActor
struct FixedCostScreensTests {
    private let today = "2026-11-02"

    private func row(_ id: String, _ day: String, _ amount: Double, name: String, category: String = "Housing") -> Transaction {
        let key = "merchant:" + name.lowercased()
        return Transaction(id: id, date: day, day: Int(day.suffix(2))!, month: String(day.prefix(7)), amount: amount,
                           categoryName: category, tags: [], place: name, city: "",
                           categoriesIn: amount < 0 ? [category] : [], incomeBuckets: amount > 0 ? [category] : [],
                           nameKey: key)
    }

    private func dashboard(_ rows: [Transaction]) -> Dashboard {
        let categories = [Category(name: "Housing", icon: "House", color: "#5B8CFF", kind: .spend),
                          Category(name: "Insurance", icon: "Shield", color: "#5B8CFF", kind: .spend),
                          Category(name: "Sports", icon: "Dumbbell", color: "#34E27A", kind: .spend),
                          Category(name: "Salary", icon: "Banknote", color: "#34E27A", kind: .income)]
        return Dashboard(version: 2, months: [], categories: Array(categories.prefix(3)), incomeBuckets: [categories[3]],
                         transactions: rows, overview: Overview(expense: [], income: [], balance: []),
                         total: Totals(expense: 0, income: 0, categories: [], incomeBuckets: []), byMonth: [:],
                         spend: [:], income: [:], pick: CategoryChoices(spend: [], income: []))
    }

    /// A rent (running, €800), a yearly insurance (€498.96), a gym that ended in June and a salary.
    private var sample: Dashboard {
        let rent = ["2026-07-03", "2026-08-03", "2026-09-03", "2026-10-03"].enumerated().map {
            row("rent\($0.offset)", $0.element, -800, name: "Hausverwaltung Fiktiv")
        }
        let insurance = [row("ins0", "2025-10-15", -498.96, name: "Fiktiv Versicherung", category: "Insurance"),
                         row("ins1", "2026-10-15", -498.96, name: "Fiktiv Versicherung", category: "Insurance")]
        let gym = ["2026-03-10", "2026-04-10", "2026-05-10", "2026-06-10"].enumerated().map {
            row("gym\($0.offset)", $0.element, -29.90, name: "Fiktiv Fitness", category: "Sports")
        }
        let salary = ["2026-08-01", "2026-09-01", "2026-10-01"].enumerated().map {
            row("pay\($0.offset)", $0.element, 2450, name: "Fiktiv Werke", category: "Salary")
        }
        return dashboard(rent + insurance + gym + salary)
    }

    private func list(_ side: DashboardSide, takingOut name: String? = nil) -> FixedCostList {
        let entries = FixedCosts.entries(in: sample)
        let marks = entries.filter { $0.name == name }.map(\.mark)
        return FixedCosts.list(FixedCosts.entries(in: sample, marks: marks), side: side)
    }

    // MARK: the Overview's line

    @Test func overviewLineWordsInBothLanguages() {
        #expect(FixedCostWords.average(194_000, language: .english) == "Avg. €1,940 a month")
        #expect(FixedCostWords.average(194_000, language: .german) == "Ø 1.940\u{a0}€ im Monat")
        #expect(FixedCostWords.fixedPart(86_000, side: .expenses, language: .english) == "€860 fixed")
        #expect(FixedCostWords.fixedPart(86_000, side: .expenses, language: .german) == "davon 860\u{a0}€ fix")
        #expect(FixedCostWords.fixedPart(130_000, side: .income, language: .english) == "€1,300 regular")
        #expect(FixedCostWords.fixedPart(130_000, side: .income, language: .german) == "davon 1.300\u{a0}€ regelmäßig")
        #expect(FixedCostWords.averageSpoken(194_000, language: .english)
                == "Average of the finished months: €1,940 a month")
        #expect(FixedCostWords.averageSpoken(194_000, language: .german)
                == "Durchschnitt der abgeschlossenen Monate: 1.940\u{a0}€ im Monat")
        #expect(FixedCostWords.fixedSpoken(86_000, side: .expenses, language: .english) == "Fixed costs: €860 a month")
        #expect(FixedCostWords.fixedSpoken(86_000, side: .expenses, language: .german) == "Fixkosten: 860\u{a0}€ im Monat")
        #expect(FixedCostWords.fixedSpoken(130_000, side: .income, language: .german)
                == "Regelmäßige Einnahmen: 1.300\u{a0}€ im Monat")
    }

    @Test func overviewLineOnlyOnOverviewWithAnAverageAndAFixedPartOnlyWhileOneRuns() throws {
        let average = MonthlyAverage(cents: 152_900, count: 12, first: "2025-10", last: "2026-10")
        let expenses = list(.expenses)
        let line = try #require(AverageLine(average: average, fixedCosts: expenses, side: .expenses, scope: .overview,
                                            language: .english))
        #expect(line.average == "Avg. €1,529 a month")
        #expect(line.fixed == "€842 fixed")                        // €800 rent and €41.58 of the yearly insurance
        #expect(line.fixedSpoken == "Fixed costs: €842 a month")
        #expect(line.averageSpoken == "Average of the finished months: €1,529 a month")
        // Current and a month's page are one month: no line; no average (fewer than two finished months): no line.
        #expect(AverageLine(average: average, fixedCosts: expenses, side: .expenses, scope: .current) == nil)
        #expect(AverageLine(average: average, fixedCosts: expenses, side: .expenses, scope: .month("2026-10")) == nil)
        #expect(AverageLine(average: nil, fixedCosts: expenses, side: .expenses, scope: .overview) == nil)
        // Server mode (no fixed costs) and a side where none was found: the average alone.
        #expect(AverageLine(average: average, fixedCosts: nil, side: .expenses, scope: .overview)?.fixed == nil)
        let none = FixedCostList(running: [], ended: expenses.ended, takenOut: [])
        #expect(AverageLine(average: average, fixedCosts: none, side: .expenses, scope: .overview)?.fixed == nil)
        // Every running one taken out: the part stays (at €0), the way back to the page.
        let rentOut = list(.expenses, takingOut: "Hausverwaltung Fiktiv")
        let allOut = FixedCostList(running: [], ended: rentOut.ended, takenOut: rentOut.takenOut)
        #expect(AverageLine(average: average, fixedCosts: allOut, side: .expenses, scope: .overview,
                            language: .english)?.fixed == "€0 fixed")
        let income = try #require(AverageLine(average: average, fixedCosts: list(.income), side: .income,
                                              scope: .overview, language: .german))
        #expect(income.fixed == "davon 2.450\u{a0}€ regelmäßig")
    }

    // MARK: the page

    @Test func pageRowsSectionsTotalAndWordsInEnglish() throws {
        let page = FixedCostPage(list: list(.expenses), side: .expenses, today: today, language: .english)
        #expect(!page.isEmpty)
        #expect(page.total == "€842" && page.year == "€10,099 a year")
        #expect(page.running.map(\.name) == ["Hausverwaltung Fiktiv", "Fiktiv Versicherung"])
        let rent = page.running[0], insurance = page.running[1]
        #expect(rent.amount == "−800.00" && rent.line == "monthly · next 3 Nov" && rent.share == nil)
        #expect(rent.oneLine == "monthly · next 3 Nov" && !rent.quiet && rent.change == .takeOut)
        #expect(rent.spoken == "Hausverwaltung Fiktiv, −800.00, monthly, next 3 Nov")
        #expect(insurance.line == "yearly · next 15 Oct 2027" && insurance.share == "€41.58 a month")
        #expect(insurance.oneLine == "yearly · next 15 Oct 2027 · €41.58 a month")
        #expect(insurance.spoken == "Fiktiv Versicherung, −498.96, yearly, next 15 Oct 2027, €41.58 a month")
        let gym = try #require(page.ended.first)
        #expect(page.ended.count == 1 && gym.name == "Fiktiv Fitness" && gym.quiet && gym.change == .takeOut)
        #expect(gym.line == "monthly · last 10 Jun")
        #expect(page.takenOut.isEmpty)
        #expect(FixedCostWords.title(.expenses, language: .english) == "Fixed costs")
        #expect(FixedCostWords.endedHeading(language: .english) == "Ended")
        #expect(FixedCostWords.takenOutHeading(language: .english) == "Not counted")
        #expect(FixedCostWords.change(.takeOut, side: .expenses, language: .english) == "Not fixed")
        #expect(FixedCostWords.change(.takeOut, side: .income, language: .english) == "Not regular")
        #expect(FixedCostWords.change(.countAgain, side: .expenses, language: .english) == "Count again")
        #expect(FixedCostWords.done(.takeOut, name: "StreamFiktiv", side: .expenses, language: .english)
                == "StreamFiktiv taken out of fixed costs.")
        #expect(FixedCostWords.done(.countAgain, name: "StreamFiktiv", side: .income, language: .english)
                == "StreamFiktiv counted again.")
    }

    @Test func pageWordsInGerman() throws {
        let page = FixedCostPage(list: list(.expenses), side: .expenses, today: today, language: .german)
        #expect(page.total == "842\u{a0}€" && page.year == "10.099\u{a0}€ im Jahr")
        let insurance = page.running[1]
        #expect(insurance.amount == "−498,96" && insurance.line == "jährlich · nächste am 15. Okt. 2027")
        #expect(insurance.share == "41,58\u{a0}€ im Monat")
        #expect(page.ended.first?.line == "monatlich · zuletzt am 10. Juni")
        #expect(FixedCostWords.title(.expenses, language: .german) == "Fixkosten")
        #expect(FixedCostWords.title(.income, language: .german) == "Regelmäßige Einnahmen")
        #expect(FixedCostWords.perMonth(language: .german) == "im Monat")
        #expect(FixedCostWords.endedHeading(language: .german) == "Beendet")
        #expect(FixedCostWords.takenOutHeading(language: .german) == "Nicht gezählt")
        #expect(FixedCostWords.change(.takeOut, side: .expenses, language: .german) == "Nicht fix")
        #expect(FixedCostWords.change(.takeOut, side: .income, language: .german) == "Nicht regelmäßig")
        #expect(FixedCostWords.change(.countAgain, side: .income, language: .german) == "Wieder zählen")
        #expect(FixedCostWords.done(.takeOut, name: "StreamFiktiv", side: .expenses, language: .german)
                == "StreamFiktiv aus den Fixkosten genommen.")
        #expect(FixedCostWords.done(.takeOut, name: "Fiktiv Werke", side: .income, language: .german)
                == "Fiktiv Werke aus den regelmäßigen Einnahmen genommen.")
        #expect(FixedCostWords.done(.countAgain, name: "StreamFiktiv", side: .expenses, language: .german)
                == "StreamFiktiv wird wieder gezählt.")
        #expect(FixedCostWords.howFound(language: .german).hasPrefix("Gefunden in Buchungen desselben Namens"))
        #expect(FixedCostWords.empty(.expenses, language: .german).hasPrefix("Noch keine Fixkosten gefunden."))
        #expect(FixedCostWords.empty(.income, language: .german).hasPrefix("Noch keine regelmäßigen Einnahmen gefunden."))
        #expect(FixedCostWords.empty(.income, language: .english).hasPrefix("No regular income found yet."))
        #expect(FixedCostWording.last("2026-08-03", referenceDay: today, language: .english) == "last 3 Aug")
        #expect(FixedCostWording.last("2026-08-03", referenceDay: today, language: .german) == "zuletzt am 3. Aug.")
        #expect(FixedCostWording.last("2025-08-03", referenceDay: today, language: .english) == "last 3 Aug 2025")
    }

    @Test func takenOutRowsCountAgainIncomeSideAndEmptyPage() throws {
        let page = FixedCostPage(list: list(.expenses, takingOut: "Fiktiv Versicherung"), side: .expenses, today: today,
                                 language: .english)
        #expect(page.running.map(\.name) == ["Hausverwaltung Fiktiv"] && page.total == "€800")
        let out = try #require(page.takenOut.first)
        #expect(out.name == "Fiktiv Versicherung" && out.quiet && out.change == .countAgain)
        #expect(out.line == "yearly · next 15 Oct 2027")              // still running: its next day due
        // A row moved to another section is another row (its identity names the section).
        let before = FixedCostPage(list: list(.expenses), side: .expenses, today: today, language: .english)
        #expect(before.running[1].entry.id == out.entry.id && before.running[1].id != out.id)
        let income = FixedCostPage(list: list(.income), side: .income, today: today, language: .english)
        // Brief 216: the salary is still running by the ledger reference, but 1 November is before today's 2nd.
        #expect(income.running.first?.amount == "+2,450.00" && income.running.first?.line == "monthly · last 1 Oct")
        let empty = FixedCostPage(list: FixedCostList(running: [], ended: [], takenOut: []), side: .income)
        #expect(empty.isEmpty)
    }

    // MARK: the route and the real store

    @Test func routeOpensOnItsSideAndTheHeaderNamesIt() {
        let route = DashboardRoute.fixedCosts(.income)
        #expect(route.fixedCosts && route.side == .income && !route.search && route.month == nil && route.name == nil)
        #expect(route != .fixedCosts(.expenses))
        var place = DashboardPlace(current: false)
        place.open(.fixedCosts(.expenses))
        #expect(place.path == [.fixedCosts(.expenses)])
        #expect(FixedCostWords.title(route.side, language: .english) == "Regular income")
    }

    @Test func overdueRunningAndTakenOutRowsSayLastInBothLanguages() throws {
        // The ledger reference keeps the rent running. The wall clock changes only the next/last wording.
        for language in [AppLanguage.english, .german] {
            let expectedLast = language == .english ? "monthly · last 3 Oct" : "monatlich · zuletzt am 3. Okt."
            let running = FixedCostPage(list: list(.expenses), side: .expenses, today: "2026-11-04", language: language)
            let rent = try #require(running.running.first)
            #expect(rent.line == expectedLast && rent.entry.running && !rent.quiet)
            #expect(rent.spoken.contains(language == .english ? "last 3 Oct" : "zuletzt am 3. Okt."))
            let out = FixedCostPage(list: list(.expenses, takingOut: "Hausverwaltung Fiktiv"), side: .expenses,
                                    today: "2026-11-04", language: language)
            #expect(out.takenOut.first?.line == expectedLast)
            let dueToday = FixedCostPage(list: list(.expenses), side: .expenses, today: "2026-11-03", language: language)
            #expect(dueToday.running.first?.line == (language == .english
                ? "monthly · next 3 Nov" : "monatlich · nächste am 3. Nov."))
            let oldImport = FixedCostPage(list: list(.income), side: .income, today: "2027-01-01", language: language)
            #expect(oldImport.running.first?.line == (language == .english
                ? "monthly · last 1 Oct 2026" : "monatlich · zuletzt am 1. Okt. 2026"))
        }
    }

    @Test func theLineAndThePageFollowTheStoreThroughNotFixedAndUndo() async throws {
        let phone = try await PhoneCountingTests.backend()
        let account = "fictional-fixed"
        let payments = ["2026-06-03", "2026-07-03", "2026-08-03", "2026-09-03", "2026-10-03"].enumerated().map {
            LedgerPayment(id: "rent\($0.offset)", account: account, source: "bank", externalId: "fictional-rent\($0.offset)",
                          bookingDate: $0.element, amount: "-800.00", currency: "EUR", text: "Fictional monthly rent",
                          counterparty: "Hausverwaltung Fiktiv", category: "household", categorySource: .manual,
                          extraCategories: [], sequence: $0.offset)
        }
        try await phone.ledger.restore(LedgerExport(exported: "2026-11-02",
            accounts: [LedgerAccount(id: account, name: "Fictional Bank")], payments: payments,
            categories: [ChosenCategory(id: "household", order: 0)], learned: [], layouts: []),
            catalog: #require(phone.catalog))
        try await phone.refresh()
        phone.today = { "2026-11-03" }
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.fixedCostPage(side: .expenses, language: .english)?.running.first?.line == "monthly · next 3 Nov")
        phone.today = { "2026-11-04" }
        // No import or reference-day change: the page reads the dashboard clock when it builds its rows.
        #expect(store.fixedCostPage(side: .expenses, language: .english)?.running.first?.line == "monthly · last 3 Oct")
        func line() -> AverageLine? {
            AverageLine(average: store.monthlyAverage(side: .expenses), fixedCosts: store.fixedCosts(side: .expenses),
                        side: .expenses, scope: .overview, language: .english)
        }
        #expect(line()?.fixed == "€800 fixed")
        let page = FixedCostPage(list: try #require(store.fixedCosts(side: .expenses)), side: .expenses)
        let rent = try #require(page.running.first)
        // A row's tap: the name's page of its newest payment, as "All with this name".
        let route = try #require(store.nameRoute(for: rent.entry.newest))
        #expect(route.name?.key == rent.entry.newest.nameKey && route.name?.title == "Hausverwaltung Fiktiv")

        let undo = try await store.setNotFixed(rent.entry, rent.change == .takeOut)
        let after = FixedCostPage(list: try #require(store.fixedCosts(side: .expenses)), side: .expenses)
        #expect(after.running.isEmpty && after.takenOut.map(\.name) == ["Hausverwaltung Fiktiv"])
        #expect(after.takenOut.first?.change == .countAgain)
        #expect(line()?.fixed == "€0 fixed")                          // the page stays in reach
        #expect(try await undo.perform() == .undone)
        #expect(line()?.fixed == "€800 fixed")
        #expect(FixedCostPage(list: try #require(store.fixedCosts(side: .expenses)), side: .expenses).running.count == 1)
    }
}
