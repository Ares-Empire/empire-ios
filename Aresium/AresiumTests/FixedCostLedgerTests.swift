import Foundation
import SwiftData
import Testing
@testable import Aresium

@MainActor
@Suite(.serialized)
struct FixedCostLedgerTests {
    private let auth = BackendAuth(token: nil)
    private let account = "fictional-fixed"
    private func payment(_ id: String, _ day: String, amount: String = "-800.00", name: String = "Fictional Rent",
                         category: String = "household", own: String? = nil, links: [LedgerPayback]? = nil) -> LedgerPayment {
        LedgerPayment(id: id, account: account, source: "bank", externalId: "fictional-" + id,
                      bookingDate: day, amount: amount, currency: "EUR", text: "Fictional monthly payment",
                      counterparty: name, category: category, categorySource: .manual, extraCategories: [],
                      sequence: Int(id.filter(\.isNumber)) ?? 0, ownName: own, paysBack: links)
    }
    private var rent: [LedgerPayment] {
        ["2026-07-03", "2026-08-03", "2026-09-03", "2026-10-03"].enumerated().map { payment("rent\($0.offset)", $0.element) }
    }
    private func setup(_ payments: [LedgerPayment]? = nil, marks: [FixedCostMark] = []) async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend()
        try await phone.ledger.restore(LedgerExport(exported: "2026-11-02", accounts: [LedgerAccount(id: account, name: "Fictional Bank")],
            payments: payments ?? rent, categories: [ChosenCategory(id: "household", order: 0), ChosenCategory(id: "salary", order: 1)],
            learned: [], layouts: [], fixedCostMarks: marks), catalog: #require(phone.catalog))
        try await phone.refresh()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    @Test func markOneSaveOneRebuildPersistencePutBackAndUndo() async throws {
        let (phone, store) = try await setup()
        let entry = try #require(store.fixedCosts(side: .expenses)?.running.first)
        #expect(store.fixedCost(id: entry.id)?.ids == entry.ids)
        #expect(store.builtFixedCosts.revision == store.revision)
        let observer = await phone.ledger.batchObserver(), save = observer.value, revision = store.revision
        let undo = try await store.setNotFixed(entry, true)
        #expect(observer.value == save + 1 && store.revision == revision + 1)
        #expect(store.fixedCosts(side: .expenses)?.monthlyTotal == 0)
        #expect(store.fixedCosts(side: .expenses)?.takenOut.first?.id == entry.id)
        #expect(try await phone.export().fixedCostMarks == [entry.mark])
        await store.reload()
        #expect(store.fixedCosts(side: .expenses)?.takenOut.count == 1)
        #expect(try await undo.perform() == .undone)
        #expect(store.fixedCosts(side: .expenses)?.monthlyTotal == 800)
        _ = try await store.setNotFixed(try #require(store.fixedCost(id: entry.id)), true)
        let restore = try await store.setNotFixed(try #require(store.fixedCost(id: entry.id)), false)
        #expect(store.fixedCosts(side: .expenses)?.running.count == 1)
        #expect(try await restore.perform() == .undone)
        #expect(store.fixedCosts(side: .expenses)?.takenOut.count == 1)
    }

    @Test func newImportKeepsMarkAndInvalidatesUndoAndOldEntry() async throws {
        let (phone, store) = try await setup()
        let entry = try #require(store.fixedCosts(side: .expenses)?.running.first)
        let undo = try await store.setNotFixed(entry, true)
        _ = try await phone.importFiles([PhoneTest.vrBank([("03.11.2026", "Fictional Rent", "Fictional monthly payment", -80000)])], auth: auth)
        await store.reloadAfterImport()
        let live = try #require(store.fixedCosts(side: .expenses)?.takenOut.first)
        #expect(live.id == entry.id && live.count == 5 && live.last == "2026-11-03")
        #expect(try await undo.perform() == .unavailable)
        await #expect(throws: BatchChangeError.unavailable) { _ = try await store.setNotFixed(entry, false) }
    }

    @Test func countAgainOnMergedPriceStepClearsBothMarksInOneSaveAndUndoRestoresBoth() async throws {
        let older = ["2026-01-03", "2026-02-03", "2026-03-03"].enumerated().map {
            payment("old\($0.offset)", $0.element)
        }
        let newer = ["2026-04-03", "2026-05-03", "2026-06-03"].enumerated().map {
            payment("new\($0.offset)", $0.element, amount: "-1040.00")
        }
        let (_, unmarked) = try await setup(older + newer)
        let entry = try #require(unmarked.fixedCosts(side: .expenses)?.running.first)
        let oldMark = FixedCostMark(key: entry.mark.key, side: .expenses, cadence: .monthly, anchor: "old0")
        let newMark = FixedCostMark(key: entry.mark.key, side: .expenses, cadence: .monthly, anchor: "new0")
        let marks = Set([oldMark, newMark])
        let (phone, store) = try await setup(older + newer, marks: Array(marks))
        let excluded = try #require(store.fixedCosts(side: .expenses)?.takenOut.first)
        #expect(store.fixedCosts(side: .expenses)?.takenOut.count == 1 && excluded.count == 6)
        #expect(marks.contains(excluded.mark))
        let observer = await phone.ledger.batchObserver(), save = observer.value, revision = store.revision
        let undo = try await store.setNotFixed(excluded, false)
        #expect(observer.value == save + 1 && store.revision == revision + 1)
        #expect(try await phone.export().fixedCostMarks.isEmpty == true)
        #expect(store.fixedCosts(side: .expenses)?.monthlyTotal == 1040)
        #expect(store.fixedCosts(side: .expenses)?.running.count == 1)
        #expect(try await undo.perform() == .undone)
        #expect(Set(try await phone.export().fixedCostMarks) == marks)
        #expect(store.fixedCosts(side: .expenses)?.takenOut.count == 1)
        #expect(store.fixedCosts(side: .expenses)?.monthlyTotal == 0)
    }

    @Test func olderImportKeepsAnUnmarkedEntryID() async throws {
        let (phone, store) = try await setup()
        let entry = try #require(store.fixedCosts(side: .expenses)?.running.first)
        _ = try await phone.importFiles([PhoneTest.vrBank([("03.06.2026", "Fictional Rent", "Fictional monthly payment", -80000)])], auth: auth)
        await store.reloadAfterImport()
        let live = try #require(store.fixedCosts(side: .expenses)?.running.first)
        #expect(live.id == entry.id && live.count == 5 && live.first == "2026-06-03")
    }

    @Test func schemaEightRoundTripSchemaSevenRestoreAndRejectInvalidMarks() async throws {
        let (phone, store) = try await setup()
        let entry = try #require(store.fixedCosts(side: .expenses)?.running.first)
        _ = try await store.setNotFixed(entry, true)
        let file = try await phone.export()
        #expect(file.schema == 8)
        let decoded = try LedgerExport.decode(file.encoded())
        #expect(decoded.fixedCostMarks == [entry.mark])
        let target = try await PhoneCountingTests.backend()
        try await target.restore(decoded.encoded())
        #expect(try await target.export().fixedCostMarks == file.fixedCostMarks)
        let restoredStore = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: target)
        await restoredStore.reload()
        #expect(restoredStore.fixedCosts(side: .expenses)?.takenOut.count == 1)
        var older = file
        older.schema = 7
        older.fixedCostMarks = []
        // A real older file has no field for the marks.
        var json = try #require(JSONSerialization.jsonObject(with: older.encoded()) as? [String: Any])
        json.removeValue(forKey: "fixedCostMarks")
        let oldData = try JSONSerialization.data(withJSONObject: json)
        let oldTarget = try await PhoneCountingTests.backend()
        try await oldTarget.restore(oldData)
        #expect(try await oldTarget.export().payments.count == rent.count)
        #expect(try await oldTarget.export().fixedCostMarks.isEmpty == true)
        older.fixedCostMarks = file.fixedCostMarks
        #expect(throws: LedgerError.self) { try LedgerExport.decode(older.encoded()) }
        var invalid = file
        invalid.fixedCostMarks += file.fixedCostMarks
        #expect(throws: LedgerError.self) { try invalid.validate(catalog: #require(phone.catalog)) }
        invalid.fixedCostMarks = [FixedCostMark(key: "merchant:fictional", side: .expenses, cadence: .monthly, anchor: "absent")]
        #expect(throws: LedgerError.self) { try invalid.validate(catalog: #require(phone.catalog)) }
    }

    @Test func engineRevisionMovesLongestWholeWordMerchantKeyAndKeepsOtherNamespaces() async throws {
        let (phone, store) = try await setup()
        let current = try #require(store.fixedCosts(side: .expenses)?.running.first).mark
        let obsolete = FixedCostMark(key: current.key + " old foreign card suffix", side: .expenses, cadence: .monthly, anchor: current.anchor)
        let own = FixedCostMark(key: "own:fictional friend", side: .income, cadence: .monthly, anchor: rent[1].id)
        let bank = FixedCostMark(key: "bank:Fictional exact bank line", side: .expenses, cadence: .yearly, anchor: rent[2].id)
        var file = try await phone.export()
        file.fixedCostMarks = [obsolete, own, bank]
        let target = try await PhoneCountingTests.backend(version: "old")
        try await target.ledger.restore(file, catalog: #require(target.catalog))
        let updated = PhoneBackend(ledger: target.ledger, engine: target.engine, defaults: PhoneTest.defaults(), engineVersion: { "updated" })
        try await updated.load()
        let marks = try await updated.ledger.fixedCostMarks()
        #expect(Set(marks) == Set([current, own, bank]))
        let rebuilt = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: updated)
        await rebuilt.reload()
        #expect(rebuilt.fixedCosts(side: .expenses)?.takenOut.first?.mark == current)
    }

    @Test func ownNameMarkAndSalaryDirectionAndPaidBackAverageUseEngineNumbers() async throws {
        var payments: [LedgerPayment] = []
        for (index, day) in ["2026-07-03", "2026-08-03", "2026-09-03", "2026-10-03"].enumerated() {
            payments.append(payment("rent\(index)", day, own: "Our Fictional Home"))
            payments.append(payment("back\(index)", day, amount: "400.00", name: "Fictional Flatmate", category: "salary",
                                    links: [LedgerPayback(payment: "rent\(index)", amount: "400.00")]))
            payments.append(payment("salary\(index)", day, amount: "2400.00", name: "Fictional Works", category: "salary"))
        }
        let (_, store) = try await setup(payments)
        let entry = try #require(store.fixedCosts(side: .expenses)?.running.first)
        #expect(entry.amount == 400 && entry.mark.key.hasPrefix("merchant:") && entry.name == "Our Fictional Home")
        #expect(store.fixedCosts(side: .income)?.monthlyTotal == 2400, "fully used payback income counts zero")
        let out = try #require(store.monthlyAverage(side: .expenses))
        #expect(out.amount == 400 && out.count >= 3)
        #expect(store.monthlyAverage(side: .income)?.amount == 2400)
        let undo = try await store.setNotFixed(entry, true)
        #expect(store.fixedCosts(side: .expenses)?.monthlyTotal == 0)
        #expect(store.fixedCosts(side: .income)?.monthlyTotal == 2400)
        await store.setOwnNames(false)
        #expect(store.fixedCosts(side: .expenses)?.takenOut.first?.id == entry.id)
        #expect(try await undo.perform() == .undone)
        let salary = try #require(store.fixedCosts(side: .income)?.running.first)
        let salaryUndo = try await store.setNotFixed(salary, true)
        #expect(store.fixedCosts(side: .income)?.monthlyTotal == 0)
        #expect(store.fixedCosts(side: .expenses)?.monthlyTotal == 400)
        #expect(try await salaryUndo.perform() == .undone)
        #expect(store.fixedCosts(side: .income)?.monthlyTotal == 2400)
    }

    @Test func versionSevenStoreMigratesReopensAndDeleteRemovesMarks() async throws {
        let storage = PhoneTest.storage()
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        let payments = rent
        try await Task.detached {
            let schema = Schema(versionedSchema: LedgerSchemaV7.self)
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration("Aresium", schema: schema, url: storage.storeURL, cloudKitDatabase: .none))
            let context = ModelContext(container)
            context.insert(LedgerSchemaV7.Account(id: "fictional-fixed", name: "Fictional Bank", iban: nil, bank: nil, currency: "EUR"))
            for payment in payments { context.insert(LedgerSchemaV7.Payment(payment)) }
            context.insert(LedgerSchemaV7.Chosen(id: "household", customName: nil, order: 0))
            try context.save()
        }.value
        let ledger = try await Task.detached { try storage.open() }.value
        #expect(try await ledger.payments().count == payments.count)
        #expect(try await ledger.fixedCostMarks().isEmpty == true)
        let phone = PhoneBackend(ledger: ledger, engine: try await AresiumEngine.bundledForPhone(), defaults: PhoneTest.defaults())
        try await phone.load()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        let entry = try #require(store.fixedCosts(side: .expenses)?.running.first)
        _ = try await store.setNotFixed(entry, true)
        let reopened = try await Task.detached { try storage.open() }.value
        #expect(try await reopened.fixedCostMarks() == [entry.mark])
        try storage.delete()
        let empty = try await Task.detached { try storage.open() }.value
        #expect(try await empty.fixedCostMarks().isEmpty == true)
        #expect(try await empty.summary().isEmpty == true)
    }

    @Test func serverHasAverageAndNoFixedCostAPI() async throws {
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), sample: true)
        await store.reload()
        #expect(store.monthlyAverage(side: .expenses) != nil)
        #expect(store.fixedCosts(side: .expenses) == nil && store.fixedCosts(side: .income) == nil)
        #expect(store.fixedCost(id: "absent") == nil)
    }
}

@MainActor
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["FIXED_COST_TIMINGS"] == "1"))
struct FixedCostTimingTests {
    @Test func existingFiveThousandPaymentSource() async throws {
        let phone = try await PhoneCountingTests.backend()
        let file = try PhoneTest.fixture("timing-vr-5000.csv")
        let header = String(decoding: file.data, as: UTF8.self).components(separatedBy: "\n")[0]
        try await phone.saveLayout(CsvLayout(separator: ";", header: header.components(separatedBy: ";"),
            dateFormat: "YYYY-MM-DD", numberFormat: "de",
            columns: .init(date: 0, valueDate: 1, amount: 4, counterparty: [2], text: [3], currency: 5)))
        _ = try await phone.importFiles([file], auth: BackendAuth(token: nil))
        #expect(phone.summary.payments == 5000)
        let dashboard = try await phone.dashboard(auth: BackendAuth(token: nil))
        var samples: [Double] = []
        for round in 0..<8 {
            let start = ProcessInfo.processInfo.systemUptime
            let entries = await FixedCostsCache.build(dashboard, marks: [])
            let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
            if round > 0 { samples.append(ms) }
            print("FIXED COST TIMING round=\(round) payments=5000 entries=\(entries.count) ms=\(ms)")
        }
        print("FIXED COST TIMING median-ms=\(samples.sorted()[3]) min-ms=\(samples.min()!) max-ms=\(samples.max()!)")
    }
}
