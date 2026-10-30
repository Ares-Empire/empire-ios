import Foundation
import Testing
@testable import Aresium

@MainActor
struct PhonePickerBatchTests {
    private let auth = BackendAuth(token: nil)
    private let choices = ["groceries", "rent", "household", "gifts", "hobbies"]

    /// The engine is unchanged; the test wrapper counts full sorts, excluding the picker's smaller dry run.
    static func countingEngine(paymentCount: Int) throws -> AresiumEngine {
        let url = try #require(AresiumEngine.bundledScriptURL())
        let script = try String(contentsOf: url, encoding: .utf8) + """
        ;(() => {
            const original = globalThis.AresiumEngine;
            let calls = 0;
            globalThis.AresiumEngine = {
                ...original,
                sortPayments: (payments, ...rest) => {
                    if (payments.length === \(paymentCount)) calls++;
                    return original.sortPayments(payments, ...rest);
                },
                get version() { return String(calls); }
            };
        })();
        """
        return try AresiumEngine(script: script)
    }

    private func setup() async throws -> (PhoneBackend, CategoryPickerModel, ChangeCounter) {
        let phone = try await PhoneCountingTests.backend(engine: Self.countingEngine(paymentCount: 2))
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "REWE", "REWE", -2000),
            ("02.10.2026", "Fictional Landlord", "Miete", -80000),
        ])], auth: auth)
        let changes = ChangeCounter()
        let picker = CategoryPickerModel(phone: phone) { changes.count += 1 }
        await picker.load()
        return (phone, picker, changes)
    }

    @Test func fiveQuickTogglesSortOnceAndEqualFiveSlowToggles() async throws {
        let (quick, picker, changes) = try await setup()
        let start = Int(try await quick.engine.version())!
        for id in choices {
            await picker.toggle(id)
            #expect(picker.list?.isChosen(id) == true)
            #expect(try await quick.ledger.chosen().contains { $0.id == id })
        }
        #expect(changes.count == 0) // Saves happened; sorting has not.
        try await Task.sleep(for: .milliseconds(650))
        #expect(await picker.flush())
        #expect(changes.count == 1)
        #expect(Int(try await quick.engine.version()) == start + 1)

        let (slow, slowPicker, slowChanges) = try await setup()
        let slowStart = Int(try await slow.engine.version())!
        for id in choices {
            await slowPicker.toggle(id)
            try await Task.sleep(for: .milliseconds(650))
            #expect(await slowPicker.flush())
        }
        #expect(slowChanges.count == 5)
        #expect(Int(try await slow.engine.version()) == slowStart + 5)
        #expect(try await quick.ledger.payments().map(\.category) == slow.ledger.payments().map(\.category))
        #expect(picker.counts == slowPicker.counts)
        let quickDashboard = try await quick.dashboard(auth: auth)
        let slowDashboard = try await slow.dashboard(auth: auth)
        #expect(quickDashboard.total.expense == slowDashboard.total.expense && quickDashboard.total.expense == 820)
        #expect(quickDashboard.total.income == slowDashboard.total.income && quickDashboard.total.income == 0)
        #expect(quick.summary.unsorted == 0 && slow.summary.unsorted == 0)
    }

    @Test func closingImmediatelyFlushesOnceAndCancelsTheWait() async throws {
        let (phone, picker, changes) = try await setup()
        await picker.toggle("groceries")
        await picker.toggle("rent")
        #expect(await picker.flush()) // Both Done and Back use this.
        #expect(phone.summary.unsorted == 0 && changes.count == 1)
        try await Task.sleep(for: .milliseconds(650))
        #expect(changes.count == 1)
    }

    @Test func untickingFlushesBeforeAskingForItsNewPayments() async throws {
        let (phone, picker, changes) = try await setup()
        await picker.toggle("groceries")
        #expect(phone.summary.unsorted == 2)
        await picker.toggle("groceries")
        #expect(changes.count == 1 && picker.untick?.count == 1)
        await picker.resolveUntick(moveTo: nil)
        #expect(picker.list?.isChosen("groceries") == false)
        #expect(await picker.flush())
        #expect(phone.summary.unsorted == 2)
    }

    @Test func overlappingTapTasksKeepEveryChoiceAndSave() async throws {
        let (phone, picker, _) = try await setup()
        let tasks = choices.map { id in Task { await picker.toggle(id) } }
        for task in tasks { await task.value }
        #expect(await picker.flush())
        #expect(Set(try await phone.ledger.chosen().map(\.id)) == Set(choices))
        #expect(phone.summary.unsorted == 0)
    }

    @Test func oneSortWithThe5000PaymentTimingSource() async throws {
        let file = try PhoneTest.fixture("timing-source-5000.json")
        let root = try #require(try JSONSerialization.jsonObject(with: file.data) as? [String: Any])
        let rows = try #require(root["transactions"] as? [[String: Any]])
        let payments = try rows.map { row in
            SortingPayment(counterparty: try #require(row["place"] as? String), description: "Fictional timing payment",
                source: "bank", account: "timing", amount: try #require(row["amount"] as? Double), currency: "EUR",
                date: try #require(row["date"] as? String))
        }
        #expect(payments.count == 5000)
        let engine = try PhoneTest.engine()
        let categories = try await engine.catalog().defaults.map(\.id) + [CategoryCatalog.ownTransfers]
        let start = ProcessInfo.processInfo.systemUptime
        let results = try await engine.sortPayments(payments, categories: categories, learned: [:])
        let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
        #expect(results.count == 5000 && ms > 0)
        print("COUNTING sort-5000: \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), ms)) ms (one call, Swift encode + engine + decode)")
    }
}
