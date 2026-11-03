import Foundation
import SwiftData
import Testing
@testable import Aresium

@MainActor
struct FixedCostsTests {
    private let engine: AresiumEngine
    init() throws { engine = try PhoneTest.engine() }
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

    @Test func rentRaiseAndSteppedRaisesKeepOneSeries() async throws {
        var payments = rows(monthly)
        payments[3] = row("rent3", monthly[3], -850)
        let entries = try await engine.fixedCostEntries(in: dashboard(payments))
        let entry = try #require(entries.first)
        #expect(entries.count == 1 && entry.count == 4 && entry.amount == 850 && entry.monthlyEquivalent == 850)
        #expect(entry.ids == ["rent3", "rent2", "rent1", "rent0"] && entry.newest.id == "rent3")
        #expect(entry.first == monthly[0] && entry.last == monthly[3] && entry.nextDue == "2026-11-03")
        #expect(entry.running && entry.category.name == "Housing")
        payments.append(row("rent4", "2026-11-03", -900))
        #expect(try await engine.fixedCostEntries(in: dashboard(payments)).first?.id == entry.id)
    }

    @Test func twoSubscriptionsSameShopSameCadenceHaveIndependentIDsAndMarks() async throws {
        let payments = rows(monthly, amount: -10, name: "Fictional Media")
            + rows(monthly, amount: -30, name: "Fictional Media", prefix: "video")
        let d = dashboard(payments)
        let entries = try await engine.fixedCostEntries(in: d)
        #expect(entries.count == 2 && Set(entries.map(\.id)).count == 2)
        let mark = try #require(entries.first).mark
        let list = try await engine.fixedCostList(try await engine.fixedCostEntries(in: d, marks: [mark]), side: .expenses)
        #expect(list.running.count == 1 && list.takenOut.count == 1)
        #expect(list.monthlyTotal == list.running[0].amount)
    }

    @Test(arguments: [56.5, 65.0]) func transitPriceStepKeepsAllTwelveRowsAndCountsNewestPriceOnce(newPrice: Double) async throws {
        for sign in [-1.0, 1.0] {
            let payments = (1...12).map { month in
                row("transit\(month)", String(format: "2026-%02d-01", month), sign * (month <= 2 ? 50 : newPrice),
                    name: "Fictional Transit", key: "merchant:fictional transit")
            }
            let entries = try await engine.fixedCostEntries(in: dashboard(payments))
            let entry = try #require(entries.first)
            #expect(entries.count == 1 && entry.cadence == .monthly && entry.count == 12)
            #expect(entry.cents == Int((newPrice * 100).rounded()) && entry.running)
            #expect(entry.first == "2026-01-01" && entry.last == "2026-12-01" && entry.nextDue == "2027-01-01")
            #expect(entry.ids == payments.reversed().map(\.id))
            #expect(Set(entries.flatMap(\.ids)).count == entries.reduce(0) { $0 + $1.count })
            #expect(try await engine.fixedCostList(entries, side: sign < 0 ? .expenses : .income).monthlyCents == entry.cents)
        }
    }

    @Test func overlappingStreamingSubscriptionsOwnTheirRowsEvenAfterTheCheaperOneStops() async throws {
        let cheap = rows(["2026-01-01", "2026-02-01", "2026-03-01"], amount: -10,
                         name: "Fictional Streaming", prefix: "cheap")
        let dear = rows(["2026-01-01", "2026-02-01", "2026-03-01", "2026-04-01", "2026-05-01", "2026-06-01"],
                        amount: -30, name: "Fictional Streaming", prefix: "dear")
        let entries = try await engine.fixedCostEntries(in: dashboard(cheap + dear))
        let older = try #require(entries.first { $0.cents == 1000 })
        let newer = try #require(entries.first { $0.cents == 3000 })
        #expect(entries.count == 2 && older.count == 3 && newer.count == 6)
        #expect(!older.running && newer.running && Set(older.ids).isDisjoint(with: newer.ids))
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 3000)
    }

    @Test func priceStepsRequireTheNextPeriodAndTheSameSteadyDay() async throws {
        let older = rows(["2026-01-01", "2026-02-01", "2026-03-01"], amount: -50)
        for days in [["2026-05-01", "2026-06-01", "2026-07-01"],
                     ["2026-04-09", "2026-05-09", "2026-06-09"]] {
            let newer = rows(days, amount: -65, prefix: "new")
            let entries = try await engine.fixedCostEntries(in: dashboard(older + newer))
            #expect(entries.count == 2 && entries.allSatisfy { $0.count == 3 })
            #expect(Set(entries.flatMap(\.ids)).count == 6)
        }
    }

    @Test func quarterlySeriesCannotCarryAnEndedMonthlySeriesOrBecomeItsExtra() async throws {
        let monthly = rows(["2026-01-01", "2026-02-01", "2026-03-01", "2026-04-01", "2026-05-01", "2026-06-01"], amount: -10)
        let quarterly = rows(["2026-07-01", "2026-10-01", "2027-01-01"], amount: -30, prefix: "quarter")
        let entries = try await engine.fixedCostEntries(in: dashboard(monthly + quarterly))
        let base = try #require(entries.first { $0.cadence == .monthly })
        let other = try #require(entries.first { $0.cadence == .quarterly })
        #expect(entries.count == 2 && base.count == 6 && other.count == 3)
        #expect(!base.running && other.running && other.cents == 3000)
        #expect(Set(base.ids).isDisjoint(with: other.ids))
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 1000)
    }

    @Test func priceStepAndCombinedHalfYearlyFeeKeepOnlyTheirOwnPortions() async throws {
        let payments = (1...12).map { month in
            let base = month <= 2 ? 50.0 : 65.0
            return row("step\(month)", String(format: "2026-%02d-01", month),
                       -(base + (month == 6 || month == 12 ? 60 : 0)))
        }
        let entries = try await engine.fixedCostEntries(in: dashboard(payments))
        let base = try #require(entries.first { $0.cadence == .monthly })
        let fee = try #require(entries.first { $0.cadence == .halfYearly })
        #expect(entries.count == 2 && base.count == 12 && base.cents == 6500)
        #expect(fee.ids == ["step12", "step6"] && fee.cents == 6000)
        #expect(base.cents + fee.cents == Int(abs(base.newest.countedAmount) * 100))
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 7500)
    }

    @Test func priceStepsMergeForEveryCadenceIncludingACutAtMonthEnd() async throws {
        for (oldDays, newDays, cadence) in [
            (["2026-01-31", "2026-02-28"], ["2026-04-01", "2026-04-30"], FixedCostCadence.monthly),
            (["2025-01-03", "2025-04-03"], ["2025-07-06", "2025-10-03"], .quarterly),
            (["2024-01-03", "2024-07-03"], ["2025-01-03", "2025-07-03"], .halfYearly),
            (["2023-01-03", "2024-01-03"], ["2025-01-03", "2026-01-03"], .yearly),
        ] {
            let payments = rows(oldDays, amount: -50) + rows(newDays, amount: -65, prefix: "new")
            let entries = try await engine.fixedCostEntries(in: dashboard(payments))
            let entry = try #require(entries.first)
            #expect(entries.count == 1 && entry.count == 4 && entry.cadence == cadence && entry.cents == 6500)
            #expect(entry.first == oldDays.first && entry.last == newDays.last)
        }
    }

    @Test func mergedPriceStepKeepsAMarkFromEitherSegmentAndPrefersTheFirstStoredMark() async throws {
        let older = rows(["2026-01-01", "2026-02-01", "2026-03-01"], amount: -50)
        let newer = rows(["2026-04-01", "2026-05-01", "2026-06-01"], amount: -65, prefix: "new")
        let oldEntry = try #require(try await engine.fixedCostEntries(in: dashboard(older)).first)
        let newEntry = try #require(try await engine.fixedCostEntries(in: dashboard(newer)).first)
        let d = dashboard(older + newer)
        #expect(try await engine.fixedCostEntries(in: d).first?.id == oldEntry.id)
        for marks in [[oldEntry.mark], [newEntry.mark], [oldEntry.mark, newEntry.mark], [newEntry.mark, oldEntry.mark]] {
            let entries = try await engine.fixedCostEntries(in: d, marks: marks)
            let entry = try #require(entries.first)
            #expect(entries.count == 1 && entry.count == 6 && entry.notFixed && entry.id == marks[0].id)
            #expect(entry.exclusionIDs == Set(marks.map(\.id)))
            #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 0)
        }
    }

    @Test func weeklySupermarketAndTwoInOneMonthAreNotRegular() async throws {
        let weekly = ["2026-08-01", "2026-08-08", "2026-08-15", "2026-08-22", "2026-08-29"]
        let payments = weekly.enumerated().map { row("shop\($0.offset)", $0.element, -Double(20 + $0.offset), name: "Fictional Grocer") }
        #expect(try await engine.fixedCostEntries(in: dashboard(payments)).isEmpty)
        let double = rows(monthly) + [row("extra", "2026-08-10")]
        #expect(try await engine.fixedCostEntries(in: dashboard(double)).isEmpty)
    }

    @Test func yearlySupermarketPairAmongOtherPurchasesIsNotFixed() async throws {
        let pair = rows(["2025-10-15", "2026-10-15"], amount: -25, name: "Fictional Supermarket")
        let visits = (0..<40).map { index in
            let date = ReceiptDay.calendar.date(byAdding: .day, value: index * 7,
                                                to: ReceiptDay.date("2025-11-01")!)!
            return row("visit\(index)", LedgerExport.day(date, calendar: ReceiptDay.calendar),
                       -Double(60 + index % 4), name: "Fictional Supermarket")
        }
        #expect(try await engine.fixedCostEntries(in: dashboard(pair + visits)).isEmpty)
    }

    @Test func halfYearlyRestaurantPairAmongOtherVisitsIsNotFixed() async throws {
        let pair = rows(["2026-04-15", "2026-10-15"], amount: -30, name: "Fictional Restaurant")
        let visits = rows(["2026-05-02", "2026-05-19", "2026-08-10"], amount: -80,
                          name: "Fictional Restaurant", prefix: "visit")
        #expect(try await engine.fixedCostEntries(in: dashboard(pair + visits)).isEmpty)
    }

    @Test func gymMonthlyAndHalfYearlyFeesBothCountButUnrelatedVisitsBlockOnlyLongCadence() async throws {
        // The separate half-yearly series owns April's booking even though the membership has no April row.
        let fee = rows(monthly, amount: -40, name: "Fictional Gym")
        let halfYear = rows(["2026-04-03", "2026-10-03"], amount: -120, name: "Fictional Gym", prefix: "half")
        // A same-name payment in the other direction does not dirty the expense name.
        let refund = row("refund", "2026-10-05", 200, name: "Fictional Gym")
        let d = dashboard(fee + halfYear + [refund])
        let entries = try await engine.fixedCostEntries(in: d)
        #expect(Set(entries.map(\.cadence)) == [.monthly, .halfYearly])
        #expect(entries.count == 2)
        let monthlyMark = try #require(entries.first { $0.cadence == .monthly }).mark
        #expect(try await engine.fixedCostEntries(in: d, marks: [monthlyMark]).count == 2,
                "A person's Not fixed mark does not make an otherwise regular companion series irregular")
        let extra = row("visit", "2026-08-19", -200, name: "Fictional Gym")
        #expect(try await engine.fixedCostEntries(in: dashboard(fee + halfYear + [extra])).map(\.cadence) == [.monthly])
    }

    @Test func insuranceWithOnlyTwoYearlyPaymentsCounts() async throws {
        let insurance = rows(["2025-10-15", "2026-10-15"], amount: -498.96, name: "Fictional Insurance")
        let entries = try await engine.fixedCostEntries(in: dashboard(insurance))
        let entry = try #require(entries.first)
        #expect(entries.count == 1 && entry.cadence == .yearly && entry.count == 2)
    }

    private func combinedGym(throughDecember: Bool = true) -> [Transaction] {
        // Two paused months (April and August), a sign-up four times the membership, and June/December fees.
        let days = ["2026-02-01", "2026-03-01", "2026-05-01", "2026-06-01", "2026-07-01",
                    "2026-09-01", "2026-10-01", "2026-11-01", "2026-12-01"]
        return [row("signup", "2026-01-01", -160, name: "Fictional Combined Gym")] + days.enumerated().compactMap { index, day in
            if !throughDecember && day > "2026-11-01" { return nil }
            let combined = day == "2026-06-01" || day == "2026-12-01"
            return row("gym\(index)", day, combined ? -100 : -40, name: "Fictional Combined Gym")
        }
    }

    @Test func combinedGymWithPausesSignupAndHalfYearlyExtraHasNoDoubleCounting() async throws {
        let payments = combinedGym() + [row("new-month", "2027-01-01", -40, name: "Fictional Combined Gym")]
        let entries = try await engine.fixedCostEntries(in: dashboard(payments))
        let membership = try #require(entries.first { $0.cadence == .monthly })
        let fee = try #require(entries.first { $0.cadence == .halfYearly })
        #expect(entries.count == 2 && membership.running && fee.running)
        #expect(membership.cents == 4000 && membership.count == 11)
        #expect(membership.ids.contains("gym3") && membership.ids.contains("gym8"))
        #expect(fee.cents == 6000 && fee.ids == ["gym8", "gym3"] && fee.count == 2)
        #expect(fee.first == "2026-06-01" && fee.last == "2026-12-01" && fee.nextDue == "2027-06-01")
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 5000)
    }

    @Test func latestCombinedBookingKeepsMembershipAmountRunningAndNextDue() async throws {
        // 10 January is more than 45 days after the last ordinary membership on 1 November,
        // and still within the grace period of the combined booking on 1 December.
        let payments = combinedGym() + [row("reference", "2027-01-10", 1, key: nil)]
        let entries = try await engine.fixedCostEntries(in: dashboard(payments))
        let membership = try #require(entries.first { $0.cadence == .monthly })
        #expect(membership.running && membership.cents == 4000 && membership.count == 10)
        #expect(membership.last == "2026-12-01" && membership.nextDue == "2027-01-01")
        #expect(membership.newest.id == "gym8" && membership.newest.amount == -100)
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 5000)
    }

    @Test func combinedBookingsRepairGapsBeforeRegularityIsDecided() async throws {
        // Without the combined months, two of seven gaps are three months long: the ordinary amount alone
        // fails brief 208's three-quarters rule. Pauses in April and August remain genuine missed months.
        let ordinary = rows(["2026-01-01", "2026-02-01", "2026-05-01", "2026-06-01", "2026-07-01",
                             "2026-10-01", "2026-11-01", "2026-12-01"], amount: -40)
        #expect(try await engine.fixedCostEntries(in: dashboard(ordinary)).isEmpty)
        let combined = rows(["2026-03-01", "2026-09-01"], amount: -100, prefix: "combined")
        let signup = row("signup", "2025-12-01", -160)
        let entries = try await engine.fixedCostEntries(in: dashboard(ordinary + combined + [signup]))
        let membership = try #require(entries.first { $0.cadence == .monthly })
        #expect(entries.count == 2 && membership.count == 11 && membership.cents == 4000)
        #expect(entries.first { $0.cadence == .halfYearly }?.cents == 6000)
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 5000)
    }

    @Test func extrasUseAmountToleranceAndCanMixSeparateAndCombinedFees() async throws {
        let ordinary = rows(["2025-01-01", "2025-02-01", "2025-04-01", "2025-05-01", "2025-06-01",
                             "2025-07-01", "2025-08-01", "2025-09-01", "2025-10-01", "2025-11-01",
                             "2025-12-01", "2026-01-01", "2026-02-01"], amount: -40)
        let fees = [row("first-combined", "2025-03-01", -100), row("separate", "2025-09-01", -60),
                    row("latest-combined", "2026-03-01", -104)]
        let entries = try await engine.fixedCostEntries(in: dashboard(ordinary + fees))
        let fee = try #require(entries.first { $0.cadence == .halfYearly })
        #expect(entries.count == 2 && fee.count == 3 && fee.cents == 6400 && fee.monthlyCents == 1067)
        #expect(fee.ids == ["latest-combined", "separate", "first-combined"])
        #expect(entries.first { $0.cadence == .monthly }?.cents == 4000)
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 5067)
    }

    @Test func oneOffBeforeAndAfterYearlySeriesDoesNotDirtyItsSpan() async throws {
        let insurance = rows(["2025-10-15", "2026-10-15"], amount: -498.96, name: "Fictional Insurance")
        let outside = [row("before", "2025-01-03", -180, name: "Fictional Insurance"),
                       row("after", "2026-10-30", -230, name: "Fictional Insurance")]
        let entries = try await engine.fixedCostEntries(in: dashboard(insurance + outside))
        #expect(entries.count == 1 && entries.first?.cadence == .yearly && entries.first?.cents == 49896)
        let inside = row("inside", "2026-01-03", -700, name: "Fictional Insurance")
        #expect(try await engine.fixedCostEntries(in: dashboard(insurance + outside + [inside])).isEmpty)
    }

    @Test func combinedBookingOnlyFillsAnEmptyPeriodOnTheUsualDayAndDirection() async throws {
        let membership = rows(["2025-11-01", "2025-12-01", "2026-01-01", "2026-02-01", "2026-03-01"], amount: -40)
        let others = [row("occupied", "2026-03-02", -100), row("wrong-day", "2026-04-15", -100),
                      row("income", "2026-04-01", 100)]
        let entry = try #require(try await engine.fixedCostEntries(in: dashboard(membership + others)).first)
        #expect(entry.count == 5 && entry.last == "2026-03-01" && entry.cents == 4000)
        let combined = row("combined", "2026-04-06", -100)
        let carried = try #require(try await engine.fixedCostEntries(in: dashboard(membership + others + [combined])).first)
        #expect(carried.count == 6 && carried.last == "2026-04-06" && carried.cents == 4000)
    }

    @Test func quarterlyCombinedBookingsUseTheirPhaseAndExtraOnly() async throws {
        let ordinary = rows(["2025-01-03", "2025-04-03", "2025-10-03", "2026-04-03"], amount: -90)
        let combined = rows(["2025-07-03", "2026-01-03", "2026-07-03"], amount: -150, prefix: "combined")
        let offPhase = row("off-phase", "2026-08-03", -210)
        let entries = try await engine.fixedCostEntries(in: dashboard(ordinary + combined + [offPhase]))
        let base = try #require(entries.first { $0.cadence == .quarterly })
        let extra = try #require(entries.first { $0.cadence == .halfYearly })
        #expect(entries.count == 2 && base.count == 7 && base.cents == 9000 && base.nextDue == "2026-10-03")
        #expect(!base.ids.contains("off-phase") && extra.cents == 6000 && extra.count == 3)
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 4000)
    }

    @Test func combinedBookingUsesCountedCentsAndMostRecentPriceOnBothSides() async throws {
        for sign in [-1.0, 1.0] {
            var payments = rows(["2026-01-01", "2026-02-01", "2026-03-01"], amount: sign * 40)
            payments[2] = row("rent2", "2026-03-01", sign * 44)
            payments.append(row("combined", "2026-04-01", sign * 208, counted: sign * 104))
            let entry = try #require(try await engine.fixedCostEntries(in: dashboard(payments)).first)
            #expect(entry.count == 4 && entry.cents == 4400 && entry.newest.countedAmount == sign * 104)
            #expect(entry.side == (sign < 0 ? .expenses : .income))
        }
    }

    @Test func combinedMonthEndWrapsAndTwoOrdinaryPaymentsStillRejectSeries() async throws {
        let base = rows(["2026-05-01", "2026-06-01", "2026-07-01"], amount: -40)
        let combined = row("combined", "2026-07-31", -100)
        let entry = try #require(try await engine.fixedCostEntries(in: dashboard(base + [combined])).first)
        #expect(entry.count == 4 && entry.last == "2026-07-31" && entry.cents == 4000)
        let duplicate = row("duplicate", "2026-06-02", -40)
        #expect(try await engine.fixedCostEntries(in: dashboard(base + [combined, duplicate])).isEmpty)
    }

    @Test func marksSurviveCombinedRowsAndFeeAmountChangesWhileLostAnchorsStayUnmatched() async throws {
        let before = combinedGym(throughDecember: false)
        let oldMembership = try #require(try await engine.fixedCostEntries(in: dashboard(before)).first { $0.cadence == .monthly })
        let membership = try #require(try await engine.fixedCostEntries(in: dashboard(combinedGym()), marks: [oldMembership.mark])
            .first { $0.cadence == .monthly })
        #expect(membership.id == oldMembership.id && membership.notFixed && membership.count == oldMembership.count + 1)
        let feeRows = combinedGym().filter { $0.id == "gym3" || $0.id == "gym8" }
        // The old detector saw the full combined amounts as a half-yearly fee. Its row anchor survives when
        // those same rows now contribute only their extras; the amount is deliberately absent from the mark.
        let oldFee = try #require(try await engine.fixedCostEntries(in: dashboard(feeRows)).first)
        let rebuilt = try await engine.fixedCostEntries(in: dashboard(combinedGym()), marks: [oldMembership.mark, oldFee.mark])
        let fee = try #require(rebuilt.first { $0.cadence == .halfYearly })
        #expect(oldFee.cents == 10000 && fee.cents == 6000 && fee.id == oldFee.id && fee.notFixed)
        #expect(try await engine.fixedCostList(rebuilt, side: .expenses).monthlyCents == 0)
        let absent = FixedCostMark(key: oldFee.mark.key, side: .expenses, cadence: .halfYearly, anchor: "signup")
        #expect(try await engine.fixedCostEntries(in: dashboard(combinedGym()), marks: [absent]).allSatisfy { !$0.notFixed })
    }

    @Test func consecutiveMonthlyHigherBookingsAreAPriceStepRatherThanAMonthlyExtra() async throws {
        // Follow-up 217: this old monthly-extra fixture is a regular new price starting immediately after
        // the old price. Its bookings now belong to that series and cannot carry the old membership.
        let ordinary = rows(["2026-01-01", "2026-02-01", "2026-03-01"], amount: -40)
        let combined = rows(["2026-04-01", "2026-05-01", "2026-06-01"], amount: -100, prefix: "combined")
        let oldEntry = try #require(try await engine.fixedCostEntries(in: dashboard(combined)).first)
        let entries = try await engine.fixedCostEntries(in: dashboard(ordinary + combined), marks: [oldEntry.mark])
        let membership = try #require(entries.first)
        #expect(entries.count == 1 && membership.count == 6 && membership.cents == 10000)
        #expect(membership.notFixed && membership.id == oldEntry.id)
        #expect(try await engine.fixedCostList(entries, side: .expenses).monthlyCents == 0)
    }

    @Test func monthlyShopAmountsOnScatteredDaysAreNotFixedEvenAmongOtherAmounts() async throws {
        // Every gap is monthly, but the day drifts across the month. Gap regularity alone accepted this series.
        let visits = rows(["2026-01-01", "2026-02-04", "2026-03-08", "2026-04-12", "2026-05-16",
                           "2026-06-20", "2026-07-24", "2026-08-28", "2026-10-01", "2026-11-05", "2026-12-09"],
                          amount: -25, name: "Fictional Shop")
        #expect(try await engine.fixedCostEntries(in: dashboard(visits)).isEmpty)
        let others = rows(["2026-02-10", "2026-02-15", "2026-03-20", "2026-05-01"], amount: -90,
                          name: "Fictional Shop", prefix: "other")
        #expect(try await engine.fixedCostEntries(in: dashboard(visits + others)).isEmpty)
    }

    @Test func quarterlyAlsoNeedsASteadyDay() async throws {
        let visits = rows(["2025-01-01", "2025-04-04", "2025-07-08", "2025-10-12", "2026-01-16",
                           "2026-04-20", "2026-07-24", "2026-10-28"], amount: -50, name: "Fictional Shop")
        #expect(try await engine.fixedCostEntries(in: dashboard(visits)).isEmpty)
    }

    @Test func rentAllowsDayShiftsAndNextWorkingDay() async throws {
        // 1 February 2026 is Sunday: paid on Monday the 2nd. Other months move by at most three days.
        let payments = rows(["2026-01-01", "2026-02-02", "2026-03-04", "2026-04-02", "2026-05-01", "2026-06-03"])
        let entries = try await engine.fixedCostEntries(in: dashboard(payments))
        #expect(entries.count == 1)
        #expect(try #require(entries.first).cadence == .monthly)
    }

    @Test func steadyDayWrapsAcrossMonthEndsIncludingFebruary() async throws {
        for days in [
            ["2026-05-30", "2026-06-30", "2026-07-31", "2026-09-01", "2026-10-02"],
            ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30", "2026-06-01"],
            ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30"],
        ] {
            let entries = try await engine.fixedCostEntries(in: dashboard(rows(days)))
            #expect(entries.count == 1 && entries.first?.cadence == .monthly)
        }
    }

    @Test func steadyDayAllowsExactlyThreeQuartersAndFiveDays() async throws {
        // Five payments pin the usual day to the 3rd. One is exactly five days away, two are outliers.
        // Six of eight payments pass the day rule; six of seven gaps pass the existing interval rule.
        let allowed = ["2026-01-03", "2026-02-03", "2026-03-03", "2026-04-03",
                       "2026-05-03", "2026-06-08", "2026-07-13", "2026-08-13"]
        #expect(try await engine.fixedCostEntries(in: dashboard(rows(allowed))).count == 1)
        // With a third outlier fewer than three quarters fall within five days of the usual day.
        let rejected = ["2026-01-03", "2026-02-03", "2026-03-03", "2026-04-03",
                        "2026-05-03", "2026-06-09", "2026-07-13", "2026-08-13"]
        #expect(try await engine.fixedCostEntries(in: dashboard(rows(rejected))).isEmpty)
    }

    @Test func endedUsesNewestLedgerPaymentAndGraceIsInclusive() async throws {
        let gym = rows(["2026-03-01", "2026-04-01", "2026-05-01"], amount: -20, name: "Fictional Gym")
        let latest = row("reference", "2026-09-01", 1, key: nil)
        let entries = try await engine.fixedCostEntries(in: dashboard(gym + [latest]))
        #expect(entries.count == 1 && entries[0].running == false)
        #expect(try await engine.fixedCostList(entries, side: .expenses).ended.count == 1)
        let last = rows(monthly)
        let entry = try #require(try await engine.fixedCostEntries(in: dashboard(last + [row("ref", "2026-11-17", 1, key: nil)])).first)
        #expect(entry.running, "45 days is still running")
        #expect(try await engine.fixedCostEntries(in: dashboard(last + [row("ref", "2026-11-18", 1, key: nil)])).first?.running == false)
    }

    @Test func yearlyHalfYearlyQuarterlyAndMissingMonth() async throws {
        for (days, cadence, amount, equivalent) in [
            (["2025-10-31", "2026-10-31"], FixedCostCadence.yearly, -120.01, 10.0),
            (["2026-04-30", "2026-10-31"], .halfYearly, -60.04, 10.01),
            (["2026-04-03", "2026-07-03", "2026-10-03"], .quarterly, -90.01, 30.0),
            (["2026-07-03", "2026-08-03", "2026-10-03"], .monthly, -42, 42),
        ] {
            let entries = try await engine.fixedCostEntries(in: dashboard(rows(days, amount: amount)))
            let entry = try #require(entries.first)
            #expect(entries.count == 1 && entry.cadence == cadence && entry.monthlyEquivalent == equivalent)
        }
        #expect(try await engine.nextFixedDay(after: "2026-01-31", cadence: .monthly) == "2026-02-28")
        #expect(try await engine.nextFixedDay(after: "2024-02-29", cadence: .yearly) == "2025-02-28")
        #expect(try await engine.nextFixedDay(after: "2026-11-30", cadence: .quarterly) == "2027-02-28")
    }

    @Test func minimumCountsAndThreeQuartersOfGaps() async throws {
        #expect(try await engine.fixedCostEntries(in: dashboard(rows(Array(monthly.prefix(2))))).isEmpty)
        #expect(try await engine.fixedCostEntries(in: dashboard(rows(["2026-04-03", "2026-07-03"])) ).isEmpty)
        let allowed = rows(["2026-06-03", "2026-07-03", "2026-08-03", "2026-09-03", "2026-10-16"])
        #expect(try await engine.fixedCostEntries(in: dashboard(allowed)).count == 1)
        let rejected = rows(["2026-06-03", "2026-07-03", "2026-08-03", "2026-09-16", "2026-10-29"])
        #expect(try await engine.fixedCostEntries(in: dashboard(rejected)).isEmpty)
    }

    @Test func countedHalfRegularIncomeTotalsAndOrdering() async throws {
        let rent = monthly.enumerated().map { row("rent\($0.offset)", $0.element, -800, counted: -400) }
        let salary = rows(monthly, amount: 2400, name: "Fictional Works", key: "merchant:fictional works", prefix: "salary")
        let parents = rows(monthly, amount: 150, name: "Fictional Parent", key: "own:parent", prefix: "parent")
        let a = rows(monthly, amount: -10, name: "A Fictional Club", key: "merchant:a", prefix: "a")
        let b = rows(monthly, amount: -10, name: "B Fictional Club", key: "bank:B", prefix: "b")
        let entries = try await engine.fixedCostEntries(in: dashboard(rent + salary + parents + b + a))
        let out = try await engine.fixedCostList(entries, side: .expenses), incoming = try await engine.fixedCostList(entries, side: .income)
        #expect(out.monthlyTotal == 420 && out.running.map(\.name) == ["Fictional Rent", "A Fictional Club", "B Fictional Club"])
        #expect(incoming.monthlyTotal == 2550 && incoming.running.map(\.amount) == [2400, 150])
        #expect(out.running[0].amount == 400 && out.running[0].newest.amount == -800)
    }

    @Test func receiptsCashWithdrawalsCoveredTransfersAndZeroNeverCount() async throws {
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
            #expect(try await engine.fixedCostEntries(in: dashboard(payments)).isEmpty)
        }
    }

    @Test func takenOutKeepsAnchorAfterOlderImportAndEndedOrder() async throws {
        var base = rows(monthly)
        for index in base.indices { base[index].ledgerSequence = index }
        let entry = try #require(try await engine.fixedCostEntries(in: dashboard(base)).first)
        var earlier = row("older", "2026-06-03")
        earlier.ledgerSequence = 4
        #expect(try await engine.fixedCostEntries(in: dashboard(base + [earlier])).first?.id == entry.id)
        let marked = try #require(try await engine.fixedCostEntries(in: dashboard(base + [earlier]), marks: [entry.mark]).first)
        #expect(marked.id == entry.id && marked.notFixed && marked.count == 5)
        let old = rows(["2026-01-03", "2026-02-03", "2026-03-03"], key: "merchant:old", prefix: "old")
        let later = rows(["2026-02-03", "2026-03-03", "2026-04-03"], key: "merchant:later", prefix: "later")
        let entries = try await engine.fixedCostEntries(in: dashboard(old + later + [row("ref", "2026-10-03", 1, key: nil)]))
        #expect(try await engine.fixedCostList(entries, side: .expenses).ended.map(\.last) == ["2026-04-03", "2026-03-03"])
    }

    @Test func averagesExcludePartialAndLateFirstMonthBothSidesAndRoundCents() async throws {
        let months = (6...10).map { month in Month(key: "2026-\(String(format: "%02d", month))", label: "", short: "",
            year: 2026, month: month, days: 30, partial: month == 10) }
        let totals = Dictionary(uniqueKeysWithValues: months.map { month in (month.key,
            MonthData(expense: month.month == 10 ? 9999 : Double(month.month) * 10.01,
                      income: Double(month.month) * 100, categories: [], incomeBuckets: [], endBalance: 0,
                      dayExpense: [], dayExpenseRunning: [], dayIncome: [], dayBalance: [])) })
        let d = dashboard([row("first", "2026-06-08")], months: months, totals: totals)
        let out = try #require(try await engine.monthlyAverage(in: d, side: .expenses))
        #expect(out.count == 3 && out.first == "2026-07" && out.last == "2026-09" && out.cents == 8008)
        #expect(try await engine.monthlyAverage(in: d, side: .income)?.amount == 800)
        let completeFirst = dashboard([row("first", "2026-06-07")], months: months, totals: totals)
        #expect(try await engine.monthlyAverage(in: completeFirst, side: .expenses)?.count == 4)
        #expect(try await engine.monthlyAverage(in: completeFirst, side: .expenses)?.cents == 7508)
        let few = dashboard([row("first", "2026-08-08")], months: Array(months.suffix(3)), totals: totals)
        #expect(try await engine.monthlyAverage(in: few, side: .expenses) == nil)
        #expect(try await engine.monthlyAverage(in: dashboard([]), side: .income) == nil)
    }

    @Test func wordsBothLanguagesAndYearOnlyWhenDifferent() async throws {
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
