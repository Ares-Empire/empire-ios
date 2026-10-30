import Foundation
import Observation
import os
import SwiftData
import Testing
@testable import Aresium

@MainActor
struct PickerScrollTests {
    @Test func settledBurstsCountAndSortButDashboardWaitsForClosing() async throws {
        let phone = try await PhoneCountingTests.backend()
        _ = try await phone.importFiles([CategoryCountsTests.bankFile], auth: BackendAuth(token: nil))
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let store = DashboardStore(session: session, backend: phone)
        await store.reload()
        let loaded = store.lastSuccessfulLoad
        let changes = ChangeCounter()
        let picker = CategoryPickerModel(phone: phone, settle: .seconds(3600)) {
            changes.count += 1
            await store.reloadAfterTransactionChange()
        }
        await picker.load()
        for (id, waiting) in [("groceries", 3), ("rent", 2)] {
            await picker.toggle(id)
            #expect(await picker.settleSelection())
            #expect(phone.summary.unsorted == waiting)
            #expect(picker.count(of: id) != nil)
            #expect(changes.count == 0 && store.lastSuccessfulLoad == loaded)
        }
        #expect(await picker.flush())
        #expect(changes.count == 1 && store.lastSuccessfulLoad != loaded)
        #expect(store.dashboard?.transactions.filter { $0.categoryName == CategoryName.uncategorised }.count == 2)
        #expect(await picker.flush())
        #expect(changes.count == 1) // Done followed by onDisappear does not publish a second dashboard.
    }

    @Test func unchangedReloadDoesNotPublishListCountsOrSummary() async throws {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries"])
        _ = try await phone.importFiles([CategoryCountsTests.bankFile], auth: BackendAuth(token: nil))
        let picker = CategoryPickerModel(phone: phone) {}
        await picker.load()
        let listChanged = OSAllocatedUnfairLock(initialState: false)
        let countsChanged = OSAllocatedUnfairLock(initialState: false)
        let summaryChanged = OSAllocatedUnfairLock(initialState: false)
        withObservationTracking { _ = picker.list } onChange: { listChanged.withLock { $0 = true } }
        withObservationTracking { _ = picker.counts } onChange: { countsChanged.withLock { $0 = true } }
        withObservationTracking { _ = phone.summary } onChange: { summaryChanged.withLock { $0 = true } }
        await picker.load()
        try await phone.refresh()
        #expect(!listChanged.withLock { $0 })
        #expect(!countsChanged.withLock { $0 })
        #expect(!summaryChanged.withLock { $0 })
    }

    @Test func optimisticChoiceMatchesStoredOrderAfterUntickingLeavesAGap() async throws {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries", "rent", "household"])
        let picker = CategoryPickerModel(phone: phone, settle: .seconds(3600)) {}
        await picker.load()
        await picker.toggle("rent")
        await picker.toggle("gifts")
        let expected = PhoneCategoryList(catalog: try #require(phone.catalog), chosen: try await phone.ledger.chosen())
        #expect(picker.list == expected)
        #expect(picker.list?.chosen.map(\.order) == [0, 2, 3])
        #expect(await picker.flush())
    }

    @Test func workerDashboardMatchesThePreviousMainActorInputInBothLanguages() async throws {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries", "rent"])
        _ = try await phone.importFiles([CategoryCountsTests.bankFile], auth: BackendAuth(token: nil))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for language in [AppLanguage.english, .german] {
            try await AppLanguage.$scoped.withValue(language) {
                let list = try await phone.categories()
                let payments = try await phone.ledger.payments()
                let receipts = try await phone.ledger.receipts()
                let input = PhoneDashboard.input(payments: payments, list: list, today: phone.today(), receipts: receipts)
                let reference = try await phone.engine.dashboard(input)
                var worker = try await phone.dashboard(auth: BackendAuth(token: nil))
                // Brief 43 adds phone-only presentation metadata after the engine. Compare the original engine
                // payload here; PaymentNamesTests checks the added fields and groups independently.
                worker.nameGroups = nil
                for index in worker.transactions.indices {
                    worker.transactions[index].bankName = nil
                    worker.transactions[index].isOwnName = nil
                    worker.transactions[index].ownNameSource = nil
                    worker.transactions[index].nameKey = nil
                }
                #expect(try encoder.encode(reference) == encoder.encode(worker))
            }
        }
    }

    @Test func phoneEngineInitializesOffMainAndKeepsItsAnswers() async throws {
        let recording = PickerTiming.Recording()
        let worker = try await PickerTiming.$recording.withValue(recording) { try await AresiumEngine.bundledForPhone() }
        let creation = recording.values.filter { $0.name == "engine.initialize" }
        #expect(creation.count == 1 && creation.first?.kind == "worker")
        let original = try PhoneTest.engine()
        #expect(try await worker.catalog() == original.catalog())
        let payments = [SortingPayment(counterparty: "REWE", description: "Fictional groceries", source: "bank",
            account: "fictional", amount: -20, currency: "EUR", date: "2026-10-01")]
        #expect(try await worker.sortPayments(payments, categories: ["groceries"], learned: [:])
            == original.sortPayments(payments, categories: ["groceries"], learned: [:]))
    }

    @Test func ledgerJobsStayOffMainEvenWhenConstructedOnMain() async throws {
        // The context is created by the first worker job, not by init's calling thread.
        let schema = Schema(versionedSchema: LedgerSchemaCurrent.self)
        let container = try ModelContainer(for: schema,
            configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        let ledger = PhoneLedger(modelContainer: container)
        let phone = PhoneBackend(ledger: ledger, engine: try PhoneTest.engine(), defaults: PhoneTest.defaults())
        try await phone.load()
        _ = try await phone.importFiles([CategoryCountsTests.bankFile], auth: BackendAuth(token: nil))
        let recording = PickerTiming.Recording()
        try await PickerTiming.$recording.withValue(recording) {
            try await phone.choose("groceries")
            _ = try await phone.categoryCounts()
            _ = try await phone.dashboard(auth: BackendAuth(token: nil))
        }
        let jobs = recording.values.filter { $0.name.hasPrefix("ledger.") }
        #expect(!jobs.isEmpty)
        #expect(jobs.allSatisfy { $0.kind == "worker" })
        #expect(phone.summary.payments == 5 && phone.summary.unsorted == 3)
    }
}
