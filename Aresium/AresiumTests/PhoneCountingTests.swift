import Foundation
import SwiftData
import Testing
@testable import Aresium

/// Counting paths use the real bank readers, sorting and dashboard over an isolated in-memory store.
@MainActor
struct PhoneCountingTests {
    private let auth = BackendAuth(token: nil)
    private let iban = "DE02120300000000202051" // Made-up test account.

    static func backend(chosen: [String] = [], engine: AresiumEngine? = nil,
                        defaults: UserDefaults? = nil, version: String = "counting-test") async throws -> PhoneBackend {
        let schema = Schema(versionedSchema: LedgerSchemaV3.self)
        let ledger = try await Task.detached {
            let container = try ModelContainer(for: schema,
                configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
            return PhoneLedger(modelContainer: container)
        }.value
        let phone = PhoneBackend(ledger: ledger, engine: try engine ?? PhoneTest.engine(),
                                 defaults: defaults ?? PhoneTest.defaults(), engineVersion: { version })
        phone.today = { "2026-10-30" }
        try await phone.load()
        for id in chosen { try await phone.choose(id) }
        return phone
    }

    private func totals(_ phone: PhoneBackend, spending: Double, income: Double = 0, waiting: Int = 0) async throws {
        let dashboard = try await phone.dashboard(auth: auth)
        #expect(abs(dashboard.total.expense - spending) < 0.000001)
        #expect(abs(dashboard.total.income - income) < 0.000001)
        #expect(phone.summary.unsorted == waiting)
        #expect(dashboard.transactions.filter { $0.categoryName == CategoryName.uncategorised }.count == waiting)
    }

    @Test func theSameFileTwice() async throws {
        let phone = try await Self.backend(chosen: ["groceries", "salary"])
        let file = PhoneTest.vrBank([("01.10.2026", "REWE", "REWE", -2000),
                                     ("02.10.2026", "Fictional Works", "Gehalt", 100000)])
        _ = try await phone.importFiles([file], auth: auth)
        let again = PhoneTest.phoneResults(try await phone.importFiles([file], auth: auth))
        #expect(again.first?.added == 0 && again.first?.already == 2 && phone.summary.payments == 2)
        try await totals(phone, spending: 20, income: 1000)
    }

    @Test func overlappingBankMonths() async throws {
        let phone = try await Self.backend(chosen: ["groceries", "salary"])
        let overlap = ("01.10.2026", "REWE", "REWE", -2000)
        let first = PhoneTest.vrBank([("30.09.2026", "REWE", "REWE", -1000), overlap], name: "sep-oct.csv")
        let second = PhoneTest.vrBank([overlap, ("02.10.2026", "Fictional Works", "Gehalt", 100000)], name: "oct.csv")
        _ = try await phone.importFiles([first], auth: auth)
        let result = PhoneTest.phoneResults(try await phone.importFiles([second], auth: auth))
        #expect(result.first?.added == 1 && result.first?.already == 1 && phone.summary.payments == 3)
        try await totals(phone, spending: 30, income: 1000)
    }

    @Test(arguments: [true, false])
    func csvAndCamtOfTheSameAccountCountOnce(camtFirst: Bool) async throws {
        let phone = try await Self.backend(chosen: ["groceries", "salary"])
        let file = bankWithIBAN([("01.10.2026", "REWE", "REWE", -2000),
                                 ("02.10.2026", "Fictional Works", "Gehalt", 100000)], iban: iban)
        let xml = camt(iban: iban, entries: """
        <Ntry><Amt Ccy="EUR">20.00</Amt><CdtDbtInd>DBIT</CdtDbtInd>
        <BookgDt><Dt>2026-10-01</Dt></BookgDt><ValDt><Dt>2026-10-01</Dt></ValDt>
        <NtryDtls><TxDtls><RltdPties><Cdtr><Nm>REWE</Nm></Cdtr></RltdPties>
        <RmtInf><Ustrd>REWE</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
        <Ntry><Amt Ccy="EUR">1000.00</Amt><CdtDbtInd>CRDT</CdtDbtInd>
        <BookgDt><Dt>2026-10-02</Dt></BookgDt><ValDt><Dt>2026-10-02</Dt></ValDt>
        <NtryDtls><TxDtls><RltdPties><Dbtr><Nm>Fictional Works</Nm></Dbtr></RltdPties>
        <RmtInf><Ustrd>Gehalt</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
        """)
        let csvIDs = try await phone.engine.readBankFile(file.data, layouts: []).transactions.map(\.externalId)
        let camtIDs = try await phone.engine.readBankFile(xml.data, layouts: []).transactions.map(\.externalId)
        #expect(Set(csvIDs).isDisjoint(with: camtIDs))
        let results = PhoneTest.phoneResults(try await phone.importFiles(camtFirst ? [xml, file] : [file, xml], auth: auth))
        #expect(results.count == 2 && results.allSatisfy { $0.error == nil })
        #expect(results.first?.added == 2 && results.first?.already == 0)
        #expect(results.last?.added == 0 && results.last?.already == 2 && results.last?.newIDs.isEmpty == true)
        #expect(results.last?.sorted == 0 && results.last?.waiting == 0)
        #expect(phone.summary.accounts == 1 && phone.summary.payments == 2)
        try await totals(phone, spending: 20, income: 1000)
    }

    @Test(arguments: [true, false])
    func csvAndMt940OfTheSameAccountCountOnce(mt940First: Bool) async throws {
        let phone = try await Self.backend(chosen: ["groceries", "salary"])
        let csv = bankWithIBAN([("01.10.2026", "REWE", "REWE", -2000),
                                ("02.10.2026", "Fictional Works", "Gehalt", 100000)], iban: iban)
        let mt940 = ImportFile(name: "fictional-bank.sta", data: Data("""
        :20:FICTIONAL
        :25:\(iban)
        :28C:1/1
        :60F:C260930EUR0,00
        :61:2610011001D20,00NTRFNONREF
        :86:105?00Kartenzahlung?20REWE?32REWE
        :61:2610021002C1000,00NTRFNONREF
        :86:105?00Gutschrift?20Gehalt?32Fictional Works
        :62F:C261002EUR980,00
        -
        """.utf8))
        let results = PhoneTest.phoneResults(try await phone.importFiles(mt940First ? [mt940, csv] : [csv, mt940], auth: auth))
        #expect(results.count == 2 && results.allSatisfy { $0.error == nil })
        #expect(results.first?.added == 2 && results.first?.already == 0)
        #expect(results.last?.added == 0 && results.last?.already == 2)
        #expect(phone.summary.accounts == 1 && phone.summary.payments == 2)
        try await totals(phone, spending: 20, income: 1000)
    }

    @Test(arguments: [1, 2, 3])
    func sameDayAndAmountMatchOneToOne(incomingCount: Int) async throws {
        let phone = try await Self.backend(chosen: ["groceries"])
        let csv = bankWithIBAN([("01.10.2026", "REWE", "First purchase", -2000),
                                ("01.10.2026", "REWE", "Second purchase", -2000)], iban: iban)
        _ = try await phone.importFiles([csv], auth: auth)
        let storedIDs = Set(try await phone.ledger.payments().map(\.id))
        let xml = camt(iban: iban, entries: (1...incomingCount).map {
            camtEntry(day: "2026-10-01", amount: "20.00", text: "Purchase \($0) in another format")
        }.joined())
        let result = try #require(PhoneTest.phoneResults(try await phone.importFiles([xml], auth: auth)).first)
        #expect(result.error == nil && result.already == min(2, incomingCount))
        #expect(result.added == max(0, incomingCount - 2))
        let payments = try await phone.ledger.payments()
        #expect(payments.count == max(2, incomingCount))
        #expect(storedIDs.isSubset(of: Set(payments.map(\.id))))
        if incomingCount == 3 {
            #expect(payments.last?.text == "Purchase 3 in another format")
        }
        try await totals(phone, spending: Double(max(2, incomingCount) * 20))
    }

    @Test func csvWithMoreDaysOnlyMatchesTheSharedDays() async throws {
        let phone = try await Self.backend(chosen: ["groceries"])
        let xml = camt(iban: iban, entries: camtEntry(day: "2026-10-02", amount: "20.00"))
        _ = try await phone.importFiles([xml], auth: auth)
        let csv = bankWithIBAN([("01.10.2026", "REWE", "Before", -2000),
                                ("02.10.2026", "REWE", "Shared", -2000),
                                ("03.10.2026", "REWE", "After", -2000)], iban: iban)
        let result = try #require(PhoneTest.phoneResults(try await phone.importFiles([csv], auth: auth)).first)
        #expect(result.error == nil && result.added == 2 && result.already == 1)
        #expect(phone.summary.payments == 3)
        try await totals(phone, spending: 60)
        let again = try #require(PhoneTest.phoneResults(try await phone.importFiles([csv], auth: auth)).first)
        #expect(again.error == nil && again.added == 0 && again.already == 3)
        try await totals(phone, spending: 60)
    }

    @Test func sameDayAndAmountNeverMatchAcrossAccounts() async throws {
        let phone = try await Self.backend(chosen: ["groceries"])
        let csv = bankWithIBAN([("01.10.2026", "REWE", "REWE", -2000)], iban: iban)
        let xml = camt(iban: "DE61120300000000202052", entries: camtEntry(day: "2026-10-01", amount: "20.00"))
        let results = PhoneTest.phoneResults(try await phone.importFiles([csv, xml], auth: auth))
        #expect(results.count == 2 && results.allSatisfy { $0.error == nil && $0.added == 1 && $0.already == 0 })
        #expect(phone.summary.accounts == 2 && phone.summary.payments == 2)
        try await totals(phone, spending: 40)
    }

    @Test(arguments: [true, false])
    func keyMatchesCannotAlsoAnswerANewRow(keyMatchFirst: Bool) async throws {
        let phone = try await Self.backend(chosen: ["groceries"])
        let existing = ("01.10.2026", "REWE", "Existing purchase", -2000)
        let new = ("01.10.2026", "REWE", "New purchase", -2000)
        _ = try await phone.importFiles([bankWithIBAN([existing], iban: iban)], auth: auth)
        let overlap = bankWithIBAN(keyMatchFirst ? [existing, new] : [new, existing], iban: iban)
        let result = try #require(PhoneTest.phoneResults(try await phone.importFiles([overlap], auth: auth)).first)
        #expect(result.error == nil && result.added == 1 && result.already == 1)
        #expect(phone.summary.payments == 2)
        try await totals(phone, spending: 40)
    }

    @Test func differentCentsCurrenciesAndSignsAreNew() async throws {
        let phone = try await Self.backend(chosen: ["groceries"])
        let csv = bankWithIBAN([("01.10.2026", "REWE", "REWE", -2000)], iban: iban)
        _ = try await phone.importFiles([csv], auth: auth)
        let entries = camtEntry(day: "2026-10-01", amount: "20.01")
            + camtEntry(day: "2026-10-01", amount: "20.00", currency: "GBP")
            + camtEntry(day: "2026-10-01", amount: "20.00", direction: "CRDT")
            + camtEntry(day: "2026-10-01", amount: "20.00", text: "Different payment text")
        let result = try #require(PhoneTest.phoneResults(try await phone.importFiles([camt(iban: iban, entries: entries)], auth: auth)).first)
        #expect(result.error == nil && result.added == 3 && result.already == 1)
        let payments = try await phone.ledger.payments()
        #expect(payments.count == 4)
        #expect(payments.filter { $0.amountValue == -20 && $0.currency == "EUR" }.count == 1)
        #expect(payments.contains { $0.amountValue == -20.01 && $0.currency == "EUR" })
        #expect(payments.contains { $0.amountValue == -20 && $0.currency == "GBP" })
        #expect(payments.contains { $0.amountValue == 20 && $0.currency == "EUR" })
    }

    @Test func overlappingPaypalExports() async throws {
        let phone = try await Self.backend(chosen: ["groceries"])
        let file = paypal()
        _ = try await phone.importFiles([file], auth: auth)
        let overlap = paypal(extra: "03.10.2026,REWE,Allgemeine Zahlung,EUR,\"-20,00\",\"-20,00\",FICTIONAL-SECOND,Debit")
        let result = PhoneTest.phoneResults(try await phone.importFiles([overlap], auth: auth))
        #expect(result.first?.added == 1 && result.first?.already == 2)
        try await totals(phone, spending: 127.69, waiting: 1)
    }

    @Test(arguments: [true, false])
    func paypalAndBankInEitherOrder(paypalFirst: Bool) async throws {
        let phone = try await Self.backend(chosen: ["groceries"])
        let bank = paypalBank()
        for file in paypalFirst ? [paypal(), bank] : [bank, paypal()] {
            _ = try await phone.importFiles([file], auth: auth)
        }
        #expect(try await phone.ledger.payments().filter { $0.categorySource == .structural }.count == 2)
        try await totals(phone, spending: 107.69, waiting: 1)
    }

    @Test func switchAndFollowUpNeverMoveStructuralTransfers() async throws {
        let phone = try await Self.backend(chosen: ["hobbies", "groceries"])
        _ = try await phone.importFiles([paypal(), paypalBank(), PhoneTest.vrBank([
            ("10.10.2026", "Fictional Pizzeria", "Dinner", -1000),
        ])], auth: auth)
        let payments = try await phone.ledger.payments()
        let purchase = try #require(payments.first { $0.source == "paypal" && $0.amountValue < 0 })
        let transfers = payments.filter { $0.categorySource == .structural }
        let result = try await phone.switchCategory(id: purchase.id, to: "Hobbies", auth: auth)
        let followUp = try #require(result.followUp)
        #expect(followUp.count == 1) // The ordinary second purchase only, neither funding leg.
        try await followUp.apply()
        try await totals(phone, spending: 117.69)
        // Also protect against a stale follow-up captured before these rows became structural.
        try await phone.ledger.move(transfers.map(\.id), to: "hobbies", source: .learned)
        for transfer in transfers {
            #expect(try await phone.ledger.payment(transfer.id)?.category == "own-transfers")
        }
        try await totals(phone, spending: 117.69)
        // Explicit Switch on one transfer remains available.
        let direct = try await phone.switchCategory(id: transfers[0].id, to: "Groceries", auth: auth)
        #expect(direct.detail.categorySource == "manual")
    }

    @Test func paypalTripleAloneStillCountsOnceAfterSwitch() async throws {
        let phone = try await Self.backend(chosen: ["hobbies"])
        _ = try await phone.importFiles([paypal(), paypalBank()], auth: auth)
        let purchase = try #require(try await phone.ledger.payments().first { $0.source == "paypal" && $0.amountValue < 0 })
        let result = try await phone.switchCategory(id: purchase.id, to: "Hobbies", auth: auth)
        #expect(result.followUp == nil)
        #expect(try await phone.ledger.payments().filter { $0.category == "own-transfers" && $0.categorySource == .structural }.count == 2)
        try await totals(phone, spending: 107.69)
    }

    @Test func extraCategoryCountsOnce() async throws {
        let phone = try await Self.backend(chosen: ["groceries", "hobbies"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE", "REWE", -2000)])], auth: auth)
        let id = try #require(try await phone.ledger.payments().first?.id)
        _ = try await phone.setTags(id: id, categories: ["Hobbies"], dropCurrent: false, auth: auth)
        try await totals(phone, spending: 20)
    }

    @Test(arguments: [true, false])
    func cardReceiptJoinedToBank(receiptFirst: Bool) async throws {
        let phone = try await Self.backend(chosen: ["groceries"])
        let bank = PhoneTest.vrBank([("02.10.2026", "Fictional Pizzeria", "Dinner", -2000)])
        if !receiptFirst { _ = try await phone.importFiles([bank], auth: auth) }
        let saved = try await phone.saveReceipt(receipt(method: .card))
        if receiptFirst {
            #expect(saved == .waiting)
            try await totals(phone, spending: 20)
            _ = try await phone.importFiles([bank], auth: auth)
        }
        #expect(try await phone.receipts().first?.paymentID != nil)
        try await totals(phone, spending: 20)
    }

    @Test func cashReceiptCoveredByWithdrawal() async throws {
        let phone = try await Self.backend(chosen: ["groceries", "cash"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "Fictional ATM", "Bargeldauszahlung", -10000)])], auth: auth)
        #expect(try await phone.saveReceipt(receipt(method: .cash)) == .cash)
        try await totals(phone, spending: 100)
        let cash = try #require(try await phone.cash())
        #expect(cash.months["2026-10"]?.spent == 20)
    }

    @Test func handCashEntryCountsAtSpendingAndIncomeOnce() async throws {
        let phone = try await Self.backend(chosen: ["groceries", "gifts"])
        let gift = try await phone.addCashEntry(CashEntryDraft(direction: .in, amount: 50, date: "2026-10-01",
            what: "Fictional gift", category: "gifts", paidFrom: nil))
        _ = try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 20, date: "2026-10-02",
            what: "Fictional market", category: "groceries", paidFrom: gift.id))
        try await totals(phone, spending: 20, income: 50)
    }

    @Test func untickingMovesPaymentsWithoutCountingTwice() async throws {
        let phone = try await Self.backend(chosen: ["groceries", "household"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE", "REWE", -2000)])], auth: auth)
        let picker = CategoryPickerModel(phone: phone) {}
        await picker.load()
        await picker.toggle("groceries")
        #expect(picker.untick?.count == 1)
        await picker.resolveUntick(moveTo: "household")
        #expect(await picker.flush())
        #expect(try await phone.ledger.payments().first?.category == "household")
        try await totals(phone, spending: 20)
    }

    @Test func transferBetweenTwoImportedOwnAccounts() async throws {
        let phone = try await Self.backend()
        let out = bankWithIBAN([("01.10.2026", "Fictional Savings", "Umbuchung", -50000)], iban: iban)
        let incoming = bankWithIBAN([("02.10.2026", "Fictional Current", "Umbuchung", 50000)], iban: "DE61120300000000202052")
        _ = try await phone.importFiles([out], auth: auth)
        _ = try await phone.importFiles([incoming], auth: auth)
        #expect(phone.summary.accounts == 2)
        #expect(try await phone.ledger.payments().allSatisfy { $0.categorySource == .structural })
        try await totals(phone, spending: 0)
    }

    private func receipt(method: ReceiptMethod) -> ReceiptDraft {
        ReceiptDraft(date: "2026-10-02", shop: "Fictional Pizzeria", total: 20, currency: "EUR", method: method,
                     category: "groceries", categorySource: .manual, rows: [], from: "text")
    }

    private func paypal(extra: String = "") -> ImportFile {
        ImportFile(name: "fictional-paypal.csv", data: Data("""
        Datum,Name,Typ,Währung,Brutto,Netto,Transaktionscode,Auswirkung auf Guthaben
        01.10.2026,Fictional Pizzeria,Allgemeine Zahlung,EUR,"-107,69","-107,69",FICTIONAL-PURCHASE,Debit
        01.10.2026,Fictional Pizzeria,Bankgutschrift auf PayPal-Konto,EUR,"107,69","107,69",FICTIONAL-FUNDING,Credit
        \(extra)
        """.utf8))
    }

    private func paypalBank() -> ImportFile {
        PhoneTest.vrBank([("02.10.2026", "PayPal Europe S.a.r.l. et Cie S.C.A", "Ihr Einkauf bei Fictional Pizzeria", -10769)])
    }

    private func bankWithIBAN(_ rows: [(String, String, String, Int)], iban: String) -> ImportFile {
        let file = PhoneTest.vrBank(rows)
        let lines = String(decoding: file.data, as: UTF8.self).split(separator: "\n").enumerated().map { index, line in
            index == 0 ? String(line) : iban + line
        }
        return ImportFile(name: "fictional-bank.csv", data: Data(lines.joined(separator: "\n").utf8))
    }

    private func camtEntry(day: String, amount: String, currency: String = "EUR", direction: String = "DBIT",
                           text: String = "REWE") -> String {
        """
        <Ntry><Amt Ccy="\(currency)">\(amount)</Amt><CdtDbtInd>\(direction)</CdtDbtInd>
        <BookgDt><Dt>\(day)</Dt></BookgDt><ValDt><Dt>\(day)</Dt></ValDt>
        <NtryDtls><TxDtls><RltdPties><Cdtr><Nm>REWE</Nm></Cdtr></RltdPties>
        <RmtInf><Ustrd>\(text)</Ustrd></RmtInf></TxDtls></NtryDtls></Ntry>
        """
    }

    private func camt(iban: String, entries: String) -> ImportFile {
        ImportFile(name: "fictional-bank.xml", data: Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <Document xmlns="urn:iso:std:iso:20022:tech:xsd:camt.053.001.02"><BkToCstmrStmt><Stmt>
        <Id>FICTIONAL</Id><Acct><Id><IBAN>\(iban)</IBAN></Id><Ccy>EUR</Ccy></Acct>
        \(entries)</Stmt></BkToCstmrStmt></Document>
        """.utf8))
    }
}
