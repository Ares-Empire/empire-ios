import Foundation
import SwiftData
import Testing
@testable import Aresium

struct FixedCostsTests {
    private func row(_ id: String, _ day: String, _ amount: Double = -800, name: String = "Fictional Rent",
                     key: String? = "merchant:fictional rent", counted: Double? = nil) -> Transaction {
        Transaction(id: id, date: day, day: Int(day.suffix(2))!, month: String(day.prefix(7)), amount: amount,
                    categoryName: amount < 0 ? "Housing" : "Salary", tags: [], place: name, city: "",
                    categoriesIn: amount < 0 ? ["Housing"] : [], incomeBuckets: amount > 0 ? ["Salary"] : [],
                    counted: counted, nameKey: key)
    }
    private func rows(_ days: [String], amount: Double = -800, name: String = "Fictional Rent",
                      key: String = "merchant:fictional rent", prefix: String = "rent") -> [Transaction] {
        days.enumerated().map { row(prefix + String($0.offset), $0.element, amount, name: name, key: key) }
    }
    private func dashboard(_ rows: [Transaction], months: [Month] = [], totals: [String: MonthData] = [:]) -> Dashboard {
        let categories = [Category(name: "Housing", icon: "house", color: "#123456", kind: .spend),
                          Category(name: "Salary", icon: "banknote", color: "#123456", kind: .income),
                          Category(name: "Transfer", icon: "arrow", color: "#123456", kind: .transfer)]
        return Dashboard(version: 2, months: months, categories: categories, incomeBuckets: [categories[1]],
                         transactions: rows, overview: Overview(expense: [], income: [], balance: []),
                         total: Totals(expense: 0, income: 0, categories: [], incomeBuckets: []), byMonth: totals,
                         spend: [:], income: [:], pick: CategoryChoices(spend: [], income: []))
    }
    private let monthly = ["2026-07-03", "2026-08-03", "2026-09-03", "2026-10-03"]

    @Test func rentRaiseAndSteppedRaisesKeepOneSeries() throws {
        var payments = rows(monthly)
        payments[3] = row("rent3", monthly[3], -850)
        let entries = FixedCosts.entries(in: dashboard(payments))
        let entry = try #require(entries.first)
        #expect(entries.count == 1 && entry.count == 4 && entry.amount == 850 && entry.monthlyEquivalent == 850)
        #expect(entry.ids == ["rent3", "rent2", "rent1", "rent0"] && entry.newest.id == "rent3")
        #expect(entry.first == monthly[0] && entry.last == monthly[3] && entry.nextDue == "2026-11-03")
        #expect(entry.running && entry.category.name == "Housing")
        payments.append(row("rent4", "2026-11-03", -900))
        #expect(FixedCosts.entries(in: dashboard(payments)).first?.id == entry.id)
    }

    @Test func twoSubscriptionsSameShopSameCadenceHaveIndependentIDsAndMarks() throws {
        let payments = rows(monthly, amount: -10, name: "Fictional Media")
            + rows(monthly, amount: -30, name: "Fictional Media", prefix: "video")
        let d = dashboard(payments)
        let entries = FixedCosts.entries(in: d)
        #expect(entries.count == 2 && Set(entries.map(\.id)).count == 2)
        let mark = try #require(entries.first).mark
        let list = FixedCosts.list(FixedCosts.entries(in: d, marks: [mark]), side: .expenses)
        #expect(list.running.count == 1 && list.takenOut.count == 1)
        #expect(list.monthlyTotal == list.running[0].amount)
    }

    @Test func weeklySupermarketAndTwoInOneMonthAreNotRegular() {
        let weekly = ["2026-08-01", "2026-08-08", "2026-08-15", "2026-08-22", "2026-08-29"]
        let payments = weekly.enumerated().map { row("shop\($0.offset)", $0.element, -Double(20 + $0.offset), name: "Fictional Grocer") }
        #expect(FixedCosts.entries(in: dashboard(payments)).isEmpty)
        let double = rows(monthly) + [row("extra", "2026-08-10")]
        #expect(FixedCosts.entries(in: dashboard(double)).isEmpty)
    }

    @Test func yearlySupermarketPairAmongOtherPurchasesIsNotFixed() {
        let pair = rows(["2025-10-15", "2026-10-15"], amount: -25, name: "Fictional Supermarket")
        let visits = (0..<40).map { index in
            let date = FixedCosts.calendar.date(byAdding: .day, value: index * 7,
                                                to: FixedCosts.date("2025-11-01")!)!
            return row("visit\(index)", LedgerExport.day(date, calendar: FixedCosts.calendar),
                       -Double(60 + index % 4), name: "Fictional Supermarket")
        }
        #expect(FixedCosts.entries(in: dashboard(pair + visits)).isEmpty)
    }

    @Test func halfYearlyRestaurantPairAmongOtherVisitsIsNotFixed() {
        let pair = rows(["2026-04-15", "2026-10-15"], amount: -30, name: "Fictional Restaurant")
        let visits = rows(["2026-05-02", "2026-05-19", "2026-08-10"], amount: -80,
                          name: "Fictional Restaurant", prefix: "visit")
        #expect(FixedCosts.entries(in: dashboard(pair + visits)).isEmpty)
    }

    @Test func gymMonthlyAndHalfYearlyFeesBothCountButUnrelatedVisitsBlockOnlyLongCadence() throws {
        let fee = rows(monthly, amount: -40, name: "Fictional Gym")
        let halfYear = rows(["2026-04-03", "2026-10-03"], amount: -120, name: "Fictional Gym", prefix: "half")
        // A same-name payment in the other direction does not dirty the expense name.
        let refund = row("refund", "2026-10-05", 200, name: "Fictional Gym")
        let d = dashboard(fee + halfYear + [refund])
        let entries = FixedCosts.entries(in: d)
        #expect(Set(entries.map(\.cadence)) == [.monthly, .halfYearly])
        #expect(entries.count == 2)
        let monthlyMark = try #require(entries.first { $0.cadence == .monthly }).mark
        #expect(FixedCosts.entries(in: d, marks: [monthlyMark]).count == 2,
                "A person's Not fixed mark does not make an otherwise regular companion series irregular")
        let extra = row("visit", "2026-08-19", -200, name: "Fictional Gym")
        #expect(FixedCosts.entries(in: dashboard(fee + halfYear + [extra])).map(\.cadence) == [.monthly])
    }

    @Test func insuranceWithOnlyTwoYearlyPaymentsCounts() throws {
        let insurance = rows(["2025-10-15", "2026-10-15"], amount: -498.96, name: "Fictional Insurance")
        let entries = FixedCosts.entries(in: dashboard(insurance))
        let entry = try #require(entries.first)
        #expect(entries.count == 1 && entry.cadence == .yearly && entry.count == 2)
    }

    @Test func monthlyShopAmountsOnScatteredDaysAreNotFixedEvenAmongOtherAmounts() {
        // Every gap is monthly, but the day drifts across the month. Gap regularity alone accepted this series.
        let visits = rows(["2026-01-01", "2026-02-04", "2026-03-08", "2026-04-12", "2026-05-16",
                           "2026-06-20", "2026-07-24", "2026-08-28", "2026-10-01", "2026-11-05", "2026-12-09"],
                          amount: -25, name: "Fictional Shop")
        #expect(FixedCosts.entries(in: dashboard(visits)).isEmpty)
        let others = rows(["2026-02-10", "2026-02-15", "2026-03-20", "2026-05-01"], amount: -90,
                          name: "Fictional Shop", prefix: "other")
        #expect(FixedCosts.entries(in: dashboard(visits + others)).isEmpty)
    }

    @Test func quarterlyAlsoNeedsASteadyDay() {
        let visits = rows(["2025-01-01", "2025-04-04", "2025-07-08", "2025-10-12", "2026-01-16",
                           "2026-04-20", "2026-07-24", "2026-10-28"], amount: -50, name: "Fictional Shop")
        #expect(FixedCosts.entries(in: dashboard(visits)).isEmpty)
    }

    @Test func rentAllowsDayShiftsAndNextWorkingDay() throws {
        // 1 February 2026 is Sunday: paid on Monday the 2nd. Other months move by at most three days.
        let payments = rows(["2026-01-01", "2026-02-02", "2026-03-04", "2026-04-02", "2026-05-01", "2026-06-03"])
        let entries = FixedCosts.entries(in: dashboard(payments))
        #expect(entries.count == 1)
        #expect(try #require(entries.first).cadence == .monthly)
    }

    @Test func steadyDayWrapsAcrossMonthEndsIncludingFebruary() {
        for days in [
            ["2026-05-30", "2026-06-30", "2026-07-31", "2026-09-01", "2026-10-02"],
            ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-06-01"],
            ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30"],
        ] {
            let entries = FixedCosts.entries(in: dashboard(rows(days)))
            #expect(entries.count == 1 && entries.first?.cadence == .monthly)
        }
    }

    @Test func steadyDayAllowsExactlyThreeQuartersAndFiveDays() {
        // Five payments pin the usual day to the 3rd. One is exactly five days away, two are outliers.
        // Six of eight payments pass the day rule; six of seven gaps pass the existing interval rule.
        let allowed = ["2026-01-03", "2026-02-03", "2026-03-03", "2026-04-03",
                       "2026-05-03", "2026-06-08", "2026-07-13", "2026-08-13"]
        #expect(FixedCosts.entries(in: dashboard(rows(allowed))).count == 1)
        // With a third outlier fewer than three quarters fall within five days of the usual day.
        let rejected = ["2026-01-03", "2026-02-03", "2026-03-03", "2026-04-03",
                        "2026-05-03", "2026-06-09", "2026-07-13", "2026-08-13"]
        #expect(FixedCosts.entries(in: dashboard(rows(rejected))).isEmpty)
    }

    @Test func endedUsesNewestLedgerPaymentAndGraceIsInclusive() throws {
        let gym = rows(["2026-03-01", "2026-04-01", "2026-05-01"], amount: -20, name: "Fictional Gym")
        let latest = row("reference", "2026-09-01", 1, key: nil)
        let entries = FixedCosts.entries(in: dashboard(gym + [latest]))
        #expect(entries.count == 1 && entries[0].running == false)
        #expect(FixedCosts.list(entries, side: .expenses).ended.count == 1)
        let last = rows(monthly)
        let entry = try #require(FixedCosts.entries(in: dashboard(last + [row("ref", "2026-11-17", 1, key: nil)])).first)
        #expect(entry.running, "45 days is still running")
        #expect(FixedCosts.entries(in: dashboard(last + [row("ref", "2026-11-18", 1, key: nil)])).first?.running == false)
    }

    @Test func yearlyHalfYearlyQuarterlyAndMissingMonth() throws {
        for (days, cadence, amount, equivalent) in [
            (["2025-10-31", "2026-10-31"], FixedCostCadence.yearly, -120.01, 10.0),
            (["2026-04-30", "2026-10-31"], .halfYearly, -60.04, 10.01),
            (["2026-04-03", "2026-07-03", "2026-10-03"], .quarterly, -90.01, 30.0),
            (["2026-07-03", "2026-08-03", "2026-10-03"], .monthly, -42, 42),
        ] {
            let entries = FixedCosts.entries(in: dashboard(rows(days, amount: amount)))
            let entry = try #require(entries.first)
            #expect(entries.count == 1 && entry.cadence == cadence && entry.monthlyEquivalent == equivalent)
        }
        #expect(FixedCostCadence.monthly.nextDay(after: "2026-01-31") == "2026-02-28")
        #expect(FixedCostCadence.yearly.nextDay(after: "2024-02-29") == "2025-02-28")
        #expect(FixedCostCadence.quarterly.nextDay(after: "2026-11-30") == "2027-02-28")
    }

    @Test func minimumCountsAndThreeQuartersOfGaps() {
        #expect(FixedCosts.entries(in: dashboard(rows(Array(monthly.prefix(2))))).isEmpty)
        #expect(FixedCosts.entries(in: dashboard(rows(["2026-04-03", "2026-07-03"])) ).isEmpty)
        let allowed = rows(["2026-06-03", "2026-07-03", "2026-08-03", "2026-09-03", "2026-10-16"])
        #expect(FixedCosts.entries(in: dashboard(allowed)).count == 1)
        let rejected = rows(["2026-06-03", "2026-07-03", "2026-08-03", "2026-09-16", "2026-10-29"])
        #expect(FixedCosts.entries(in: dashboard(rejected)).isEmpty)
    }

    @Test func countedHalfRegularIncomeTotalsAndOrdering() throws {
        let rent = monthly.enumerated().map { row("rent\($0.offset)", $0.element, -800, counted: -400) }
        let salary = rows(monthly, amount: 2400, name: "Fictional Works", key: "merchant:fictional works", prefix: "salary")
        let parents = rows(monthly, amount: 150, name: "Fictional Parent", key: "own:parent", prefix: "parent")
        let a = rows(monthly, amount: -10, name: "A Fictional Club", key: "merchant:a", prefix: "a")
        let b = rows(monthly, amount: -10, name: "B Fictional Club", key: "bank:B", prefix: "b")
        let entries = FixedCosts.entries(in: dashboard(rent + salary + parents + b + a))
        let out = FixedCosts.list(entries, side: .expenses), incoming = FixedCosts.list(entries, side: .income)
        #expect(out.monthlyTotal == 420 && out.running.map(\.name) == ["Fictional Rent", "A Fictional Club", "B Fictional Club"])
        #expect(incoming.monthlyTotal == 2550 && incoming.running.map(\.amount) == [2400, 150])
        #expect(out.running[0].amount == 400 && out.running[0].newest.amount == -800)
    }

    @Test func receiptsCashWithdrawalsCoveredTransfersAndZeroNeverCount() {
        for kind in 0..<8 {
            var payments = rows(monthly)
            for index in payments.indices {
                switch kind {
                case 0: payments[index].receiptId = "receipt\(index)"
                case 1: payments[index].cashWithdrawal = true
                case 2: payments[index].coveredBy = ["cash"]
                case 3: payments[index] = Transaction(id: payments[index].id, date: monthly[index], day: 3,
                    month: String(monthly[index].prefix(7)), amount: -800, categoryName: "Transfer", tags: [],
                    place: "Fictional Transfer", city: "", categoriesIn: ["Transfer"], incomeBuckets: [], nameKey: "merchant:transfer")
                case 4: payments[index].counted = 0
                case 5: payments[index].nameKey = nil
                case 6: payments[index].receiptId = "entry\(index)"
                default: payments[index] = Transaction(id: payments[index].id, date: monthly[index], day: 3,
                    month: String(monthly[index].prefix(7)), amount: -800, categoryName: "Own transfer", tags: [],
                    place: "Fictional Transfer", city: "", categoriesIn: [], incomeBuckets: [], nameKey: "merchant:transfer")
                }
            }
            #expect(FixedCosts.entries(in: dashboard(payments)).isEmpty)
        }
    }

    @Test func takenOutKeepsAnchorAfterOlderImportAndEndedOrder() throws {
        var base = rows(monthly)
        for index in base.indices { base[index].ledgerSequence = index }
        let entry = try #require(FixedCosts.entries(in: dashboard(base)).first)
        var earlier = row("older", "2026-06-03")
        earlier.ledgerSequence = 4
        #expect(FixedCosts.entries(in: dashboard(base + [earlier])).first?.id == entry.id)
        let marked = try #require(FixedCosts.entries(in: dashboard(base + [earlier]), marks: [entry.mark]).first)
        #expect(marked.id == entry.id && marked.notFixed && marked.count == 5)
        let old = rows(["2026-01-03", "2026-02-03", "2026-03-03"], key: "merchant:old", prefix: "old")
        let later = rows(["2026-02-03", "2026-03-03", "2026-04-03"], key: "merchant:later", prefix: "later")
        let entries = FixedCosts.entries(in: dashboard(old + later + [row("ref", "2026-10-03", 1, key: nil)]))
        #expect(FixedCosts.list(entries, side: .expenses).ended.map(\.last) == ["2026-04-03", "2026-03-03"])
    }

    @Test func averagesExcludePartialAndLateFirstMonthBothSidesAndRoundCents() throws {
        let months = (6...10).map { month in Month(key: "2026-\(String(format: "%02d", month))", label: "", short: "",
            year: 2026, month: month, days: 30, partial: month == 10) }
        let totals = Dictionary(uniqueKeysWithValues: months.map { month in (month.key,
            MonthData(expense: month.month == 10 ? 9999 : Double(month.month) * 10.01,
                      income: Double(month.month) * 100, categories: [], incomeBuckets: [], endBalance: 0,
                      dayExpense: [], dayExpenseRunning: [], dayIncome: [], dayBalance: [])) })
        let d = dashboard([row("first", "2026-06-08")], months: months, totals: totals)
        let out = try #require(MonthlyAverage.calculate(in: d, side: .expenses))
        #expect(out.count == 3 && out.first == "2026-07" && out.last == "2026-09" && out.cents == 8008)
        #expect(MonthlyAverage.calculate(in: d, side: .income)?.amount == 800)
        let completeFirst = dashboard([row("first", "2026-06-07")], months: months, totals: totals)
        #expect(MonthlyAverage.calculate(in: completeFirst, side: .expenses)?.count == 4)
        #expect(MonthlyAverage.calculate(in: completeFirst, side: .expenses)?.cents == 7508)
        let few = dashboard([row("first", "2026-08-08")], months: Array(months.suffix(3)), totals: totals)
        #expect(MonthlyAverage.calculate(in: few, side: .expenses) == nil)
        #expect(MonthlyAverage.calculate(in: dashboard([]), side: .income) == nil)
    }

    @Test func wordsBothLanguagesAndYearOnlyWhenDifferent() {
        #expect(FixedCostCadence.allCases.map { FixedCostWording.cadence($0, language: .english) }
                == ["monthly", "quarterly", "every 6 months", "yearly"])
        #expect(FixedCostCadence.allCases.map { FixedCostWording.cadence($0, language: .german) }
                == ["monatlich", "vierteljährlich", "halbjährlich", "jährlich"])
        #expect(FixedCostWording.nextDue("2026-12-03", referenceDay: "2026-11-02", language: .english) == "next 3 Dec")
        #expect(FixedCostWording.nextDue("2026-12-03", referenceDay: "2026-11-02", language: .german) == "nächste am 3. Dez.")
        #expect(FixedCostWording.nextDue("2027-01-03", referenceDay: "2026-11-02", language: .english) == "next 3 Jan 2027")
        #expect(FixedCostWording.nextDue("2027-01-03", referenceDay: "2026-11-02", language: .german) == "nächste am 3. Jan. 2027")
    }
}
