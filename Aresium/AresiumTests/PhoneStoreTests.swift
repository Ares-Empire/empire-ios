import Foundation
import Testing
@testable import Aresium

/// Phone mode's storage (`PhoneLedger`, `PhoneStorage`): one store per account, payments unique by (account, source,
/// export id), categories, rules and layouts kept, export and restore.
@MainActor
struct PhoneStoreTests {
    @Test func eachAccountHasItsOwnProtectedStore() async throws {
        let storage = PhoneTest.storage()
        let first = try await PhoneTest.backend(account: "fictionalA", storage: storage, chosen: ["groceries"])
        _ = try await first.importFiles([PhoneTest.fixture("dkb.csv")], auth: BackendAuth(token: nil))
        #expect(first.summary.payments > 0)
        let other = try await PhoneTest.backend(account: "fictionalB", storage: storage)
        #expect(other.summary.payments == 0 && other.summary.chosen.isEmpty)
        // Opened again later (a new login of the same account), the data is there.
        let again = try await PhoneTest.backend(account: "fictionalA", storage: storage)
        #expect(again.summary.payments == first.summary.payments)
        #expect(again.summary.chosen.map(\.id) == ["groceries"])
        #expect(storage.directory(for: "fictionalA") != storage.directory(for: "fictionalB"))
        #expect(storage.directory(for: "../escape").lastPathComponent != "..")
        let attributes = try FileManager.default.attributesOfItem(atPath: storage.directory(for: "fictionalA").path)
        if let protection = attributes[.protectionKey] as? FileProtectionType { #expect(protection == .complete) }
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
        #expect(export.schema == 1 && export.fileName.hasPrefix("Aresium-") && export.fileName.hasSuffix(".json"))
        let data = try export.encoded()

        let fresh = try await PhoneTest.backend(account: "fictionalB")
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
        let target = try await PhoneTest.backend(account: "fictionalB", chosen: ["groceries"])

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
        export.schema = 2
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
