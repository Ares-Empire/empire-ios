import Foundation
import Testing
@testable import Aresium

/// Phone mode's storage (`PhoneLedger`, `PhoneStorage`): one store per iPhone, an older per-account store moved over,
/// payments unique by (account, source, export id), categories, rules and layouts kept, export and restore.
@MainActor
struct PhoneStoreTests {
    @Test func thePhoneHasOneProtectedStoreThatOpensAgain() async throws {
        let storage = PhoneTest.storage()
        let first = try await PhoneTest.backend(storage: storage, chosen: ["groceries"])
        _ = try await first.importFiles([PhoneTest.fixture("dkb.csv")], auth: BackendAuth(token: nil))
        #expect(first.summary.payments > 0)
        #expect(storage.directory.lastPathComponent == "local" && storage.hasStore)
        // Opened again later (a new launch, whoever is logged in), the data is there.
        let again = try await PhoneTest.backend(storage: storage)
        #expect(again.summary.payments == first.summary.payments)
        #expect(again.summary.chosen.map(\.id) == ["groceries"])
        let attributes = try FileManager.default.attributesOfItem(atPath: storage.directory.path)
        if let protection = attributes[.protectionKey] as? FileProtectionType { #expect(protection == .complete) }
        try storage.delete()
        #expect(!storage.hasStore && !FileManager.default.fileExists(atPath: storage.directory.path))
    }

    // MARK: moving an older per-account store over

    /// An older build's store for an account: `<root>/<account id>/ledger.store`, with these payments, changed `daysAgo`.
    private func oldStore(_ account: String, in storage: PhoneStorage, payments: Int, daysAgo: Double) async throws {
        let folder = storage.root.appending(path: account, directoryHint: .isDirectory)
        let old = PhoneStorage(root: folder.deletingLastPathComponent().appending(path: "build-\(account)",
                                                                                 directoryHint: .isDirectory))
        // Filled in a scope of its own, so its store is closed before it moves.
        func fill() async throws {
            let backend = try await PhoneTest.backend(storage: old, chosen: ["groceries"])
            let rows = (0..<payments).map { ("0\($0 + 1).10.2026", "REWE Markt GmbH", "REWE \(account) \($0)", -1000 - $0) }
            if !rows.isEmpty { _ = try await backend.importFiles([PhoneTest.vrBank(rows)], auth: BackendAuth(token: nil)) }
        }
        try await fill()
        try await Task.sleep(for: .milliseconds(100))
        try FileManager.default.createDirectory(at: storage.root, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: old.directory, to: folder)
        try? FileManager.default.removeItem(at: old.root)
        let date = Date.now.addingTimeInterval(-daysAgo * 86_400)
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        }
    }

    @Test func oneOldStoreBecomesThePhonesStoreByMoving() async throws {
        let storage = PhoneTest.storage()
        try await oldStore("fictionalAccountA", in: storage, payments: 2, daysAgo: 1)
        #expect(!storage.hasStore)
        let phone = try await PhoneTest.backend(storage: storage)        // opening moves it
        #expect(phone.summary.payments == 2 && phone.summary.chosen.map(\.id) == ["groceries"])
        #expect(storage.hasStore)
        #expect(!FileManager.default.fileExists(atPath: storage.root.appending(path: "fictionalAccountA").path))  // moved
        #expect(try storage.moveOldStore() == .nothing)
    }

    @Test func withSeveralTheMostRecentlyChangedMovesAndTheOthersStay() async throws {
        let storage = PhoneTest.storage()
        try await oldStore("fictionalAccountA", in: storage, payments: 1, daysAgo: 9)
        try await oldStore("fictionalAccountB", in: storage, payments: 3, daysAgo: 1)
        try await oldStore("fictionalAccountC", in: storage, payments: 2, daysAgo: 30)
        #expect(try storage.moveOldStore() == .moved(from: "fictionalAccountB", leftBehind: 2))
        let phone = try await PhoneTest.backend(storage: storage)
        #expect(phone.summary.payments == 3)
        for account in ["fictionalAccountA", "fictionalAccountC"] {
            #expect(FileManager.default.fileExists(atPath: storage.root.appending(path: "\(account)/ledger.store").path))
        }
        // The phone has its store now: nothing moves any more.
        #expect(try storage.moveOldStore() == .nothing && storage.oldStores().count == 2)
    }

    @Test func deletingTheDataAlsoRemovesOlderStoresLeftBehind() async throws {
        let storage = PhoneTest.storage()
        try await oldStore("fictionalAccountA", in: storage, payments: 1, daysAgo: 9)
        try await oldStore("fictionalAccountB", in: storage, payments: 3, daysAgo: 1)
        _ = try await PhoneTest.backend(storage: storage)                // opening moves B, A stays behind
        #expect(storage.hasStore && storage.oldStores().count == 1)
        try storage.delete()
        #expect(!storage.hasStore && storage.oldStores().isEmpty)
    }

    @Test func anExistingPhoneStoreIsNeverReplaced() async throws {
        let storage = PhoneTest.storage()
        let phone = try await PhoneTest.backend(storage: storage, chosen: ["rent"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "Fiktiv Laden", "Einkauf", -500)])],
                                        auth: BackendAuth(token: nil))
        try await oldStore("fictionalAccountA", in: storage, payments: 4, daysAgo: 0)
        #expect(try storage.moveOldStore() == .nothing)
        let again = try await PhoneTest.backend(storage: storage)
        #expect(again.summary.payments == 1)
        #expect(FileManager.default.fileExists(atPath: storage.root.appending(path: "fictionalAccountA/ledger.store").path))
    }

    @Test func nothingToMoveOnAFreshInstall() throws {
        let storage = PhoneTest.storage()
        #expect(try storage.moveOldStore() == .nothing && storage.oldStores().isEmpty)
    }

    @Test func aPaymentIsStoredOnceByAccountSourceAndExportID() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let file = try PhoneTest.fixture("dkb.csv")
        let first = PhoneTest.phoneResults(try await phone.importFiles([file], auth: BackendAuth(token: nil)))
        let count = phone.summary.payments
        #expect(first.first?.added == count && first.first?.already == 0 && count > 0)
        // The same export again, and twice in one import: nothing new.
        let second = PhoneTest.phoneResults(try await phone.importFiles([file, file], auth: BackendAuth(token: nil)))
        #expect(second.map(\.added) == [0, 0] && second.map(\.already) == [count, count])
        #expect(phone.summary.payments == count)
        // The same booking id on another account is another payment.
        let ledger = phone.ledger
        let payments = try await ledger.payments()
        let read = try await phone.engine.readBankFile(file.data, layouts: [])
        let added = try await ledger.add(read, account: LedgerAccount(id: "iban:DE00OTHER", name: "Other"))
        #expect(added.newIDs.count == count && payments.count == count)
        #expect(try await ledger.payments().count == count * 2)
    }

    @Test func storesWhatTheDetailAndSortingNeed() async throws {
        let phone = try await PhoneTest.backend(chosen: ["utilities", "rent"])
        _ = try await phone.importFiles([PhoneTest.fixture("dkb.csv")], auth: BackendAuth(token: nil))
        let payments = try await phone.ledger.payments()
        let power = try #require(payments.first { $0.text == "Abschlag Strom Februar" })
        #expect(power.amount == "-36.40" && power.bookingDate == "2026-02-06" && power.source == "bank")
        #expect(power.counterpartyIban == "DE34701500000000246810")
        let accounts = try await phone.ledger.accounts()
        #expect(accounts.map(\.id) == ["iban:DE55120300000000556699"] && accounts.first?.iban == "DE55120300000000556699")
        let snapshot = try await phone.ledger.sortingSnapshot()
        #expect(snapshot.payments.allSatisfy { $0.accountIban == "DE55120300000000556699" && $0.raw != nil })
        let detail = try await phone.transactionDetail(id: power.id, auth: BackendAuth(token: nil))
        #expect(detail.place == "Fiktiv Stadtwerke" && detail.amount == -36.4 && detail.account == accounts.first?.name)
        #expect(detail.originalRows?.contains { $0.label == "Verwendungszweck" && $0.value == "Abschlag Strom Februar" } == true)
        #expect(detail.category == "Utilities" && detail.categorySource == "starter")
    }

    @Test func savedLayoutsReplaceTheSameTable() async throws {
        let phone = try await PhoneTest.backend()
        let guess = try #require(try await phone.engine.readBankFile(PhoneTest.fixture("unknown-fiktivbank.csv").data,
                                                                    layouts: []).needsLayout)
        var layout = try #require(guess.layout)
        try await phone.saveLayout(layout)
        layout.numberFormat = "en"
        try await phone.saveLayout(layout)
        #expect(try await phone.ledger.layouts() == [layout])
    }

    // MARK: export and restore

    @Test func exportRoundTripsIntoAnEmptyStore() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "rent", "utilities"])
        try await phone.addCustom(named: "Fictional hobby")
        _ = try await phone.importFiles([PhoneTest.fixture("dkb.csv")], auth: BackendAuth(token: nil))
        let guess = try #require(try await phone.engine.readBankFile(PhoneTest.fixture("unknown-fiktivbank.csv").data,
                                                                    layouts: []).needsLayout)
        try await phone.saveLayout(try #require(guess.layout))
        try await phone.ledger.remember(["fiktiv laden": "groceries"])
        let export = try await phone.export()
        #expect(export.schema == 3 && export.fileName.hasPrefix("Aresium-") && export.fileName.hasSuffix(".json"))
        let data = try export.encoded()

        let fresh = try await PhoneTest.backend()
        try await fresh.restore(data)
        let restored = try await fresh.export()
        #expect(restored == export)
        #expect(fresh.summary.payments == phone.summary.payments && fresh.summary.layouts == 1 && fresh.summary.learned == 1)
        // A restored store works as before: its dashboard is the same.
        let one = try await phone.dashboard(auth: BackendAuth(token: nil))
        let two = try await fresh.dashboard(auth: BackendAuth(token: nil))
        #expect(one.total.expense == two.total.expense && one.transactions.map(\.id) == two.transactions.map(\.id))
    }

    @Test func restoreGoesOnlyIntoAnEmptyStore() async throws {
        let phone = try await PhoneTest.backend(chosen: ["rent"])
        _ = try await phone.importFiles([PhoneTest.fixture("dkb.csv")], auth: BackendAuth(token: nil))
        let data = try await phone.export().encoded()
        let before = try await phone.export()
        await #expect(throws: LedgerError.notEmpty) { try await phone.restore(data) }
        #expect(try await phone.export() == before)
    }

    @Test func aDamagedExportChangesNothing() async throws {
        let source = try await PhoneTest.backend(chosen: ["rent"])
        _ = try await source.importFiles([PhoneTest.fixture("dkb.csv")], auth: BackendAuth(token: nil))
        var export = try await source.export()
        let target = try await PhoneTest.backend(chosen: ["groceries"])

        var orphan = export
        orphan.accounts = []                                               // payments without their account
        await #expect(throws: LedgerError.self) { try await target.restore(orphan.encoded()) }
        var unknown = export
        unknown.payments[0].category = "custom-not-on-the-list"
        unknown.payments[0].categorySource = .manual
        await #expect(throws: LedgerError.self) { try await target.restore(unknown.encoded()) }
        var badDate = export
        badDate.payments[0] = LedgerPayment(id: "x", account: export.payments[0].account, source: "bank", externalId: "x",
                                            bookingDate: "2026-02-30", amount: "1.00", currency: "EUR", text: "x",
                                            categorySource: .none, extraCategories: [], sequence: 1)
        await #expect(throws: LedgerError.self) { try await target.restore(badDate.encoded()) }
        export.schema = LedgerExport.currentSchema + 1                     // a version this app does not know
        await #expect(throws: LedgerError.self) { try await target.restore(export.encoded()) }
        await #expect(throws: LedgerError.self) { try await target.restore(Data(#"{"files":[]}"#.utf8)) }
        // Nothing was written: the store is as it was (its one chosen category, no data).
        #expect(target.summary.isEmpty && target.summary.chosen.map(\.id) == ["groceries"])
        #expect(try await target.ledger.payments().isEmpty)
    }

    @Test func exportChecksDaysAndAmounts() {
        #expect(LedgerExport.isDay("2026-02-28") && !LedgerExport.isDay("2026-02-29") && LedgerExport.isDay("2028-02-29"))
        #expect(!LedgerExport.isDay("27.10.2026") && !LedgerExport.isDay("2026-13-01"))
        #expect(LedgerExport.isAmount("-1080.00") && LedgerExport.isAmount("3.2") && !LedgerExport.isAmount("1,00"))
    }
}
