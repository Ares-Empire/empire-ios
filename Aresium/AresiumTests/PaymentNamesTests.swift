import Foundation
import SwiftData
import Testing
@testable import Aresium

@MainActor
struct PaymentNamesTests {
    private let auth = BackendAuth(token: nil)

    private func phone(_ rows: [(String, String, String, Int)] = [],
                       chosen: [String] = ["groceries"]) async throws -> PhoneBackend {
        let phone = try await PhoneCountingTests.backend(chosen: chosen)
        if !rows.isEmpty { _ = try await phone.importFiles([PhoneTest.vrBank(rows)], auth: auth) }
        return phone
    }

    private func pennyPhone() async throws -> PhoneBackend {
        try await phone([("01.09.2026", "PENNY Markt GmbH München", "Purchase", -1000),
                         ("02.10.2026", "Kartenzahlung PENNY Markt 12345", "Purchase", -2000),
                         ("03.10.2026", "PENNY Markt Berlin", "Purchase", -3000)])
    }

    @Test func shopRuleNamesAllSpellingsAndLaterImportsWithoutChangingSorting() async throws {
        let phone = try await pennyPhone()
        let before = try await phone.ledger.payments()
        let first = try #require(before.first)
        #expect(try await phone.renameInfo(id: first.id).otherPaymentCount == 2)
        let sortedBefore = try await phone.ledger.sortingSnapshot()
        _ = try await phone.rename(id: first.id, name: "  My supermarket\n", scope: .shop)
        let dashboard = try await phone.dashboard(auth: auth)
        #expect(dashboard.transactions.count == 3)
        #expect(dashboard.transactions.allSatisfy { $0.place == "My supermarket" && $0.isOwnName == true && $0.ownNameSource == .shop })
        #expect(dashboard.transactions.allSatisfy { $0.bankName != nil })
        #expect(try await phone.ledger.payments() == before, "A shop name changes neither bank values nor categories")
        let sortedAfter = try await phone.ledger.sortingSnapshot()
        #expect(sortedAfter.payments == sortedBefore.payments && sortedAfter.learned == sortedBefore.learned)
        try await phone.sort()
        #expect(try await phone.ledger.payments().map(\.category) == before.map(\.category))
        _ = try await phone.importFiles([PhoneTest.vrBank([("04.10.2026", "PENNY Markt GmbH Hamburg", "Later", -4000)])], auth: auth)
        let later = try await phone.dashboard(auth: auth)
        #expect(later.transactions.count == 4 && later.transactions.allSatisfy { $0.place == "My supermarket" })
        #expect(later.nameGroups?.values.first?.count == 4)
        #expect(later.total.expense == 100)
    }

    @Test func paymentOverrideWinsAndEmptyRemovesOnlyTheChosenScope() async throws {
        let phone = try await pennyPhone()
        let payment = try #require(try await phone.ledger.payments().first)
        _ = try await phone.rename(id: payment.id, name: "Weekly shop", scope: .shop)
        let alone = try await phone.rename(id: payment.id, name: "Birthday", scope: .payment)
        #expect(alone.place == "Birthday" && alone.bankName == payment.place && alone.ownNameSource == .payment)
        let info = try await phone.renameInfo(id: payment.id)
        #expect(info.ownName == "Birthday" && info.source == .payment && info.shopOwnName == "Weekly shop")
        #expect(try await phone.dashboard(auth: auth).transactions.filter { $0.place == "Birthday" }.count == 1)
        _ = try await phone.rename(id: payment.id, name: " \n ", scope: .payment)
        #expect(try await phone.transactionDetail(id: payment.id, auth: auth).place == "Weekly shop")
        _ = try await phone.rename(id: payment.id, name: "", scope: .shop)
        let restored = try await phone.dashboard(auth: auth)
        #expect(restored.transactions.allSatisfy { $0.isOwnName == false && $0.bankName == nil && $0.ownNameSource == nil })
        #expect(try await phone.ledger.paymentNames().isEmpty)
        #expect(PaymentNames.normalized("  " + String(repeating: "👨‍👩‍👧‍👦", count: 61) + "\n").count == 60)
        _ = try await phone.rename(id: payment.id, name: String(repeating: "a", count: 70), scope: .payment)
        #expect(try await phone.renameInfo(id: payment.id).ownName?.count == 60)
    }

    @Test func barePaypalOnlyRenamesAloneAndGroupsExactBankLines() async throws {
        let phone = try await phone([("01.10.2026", "PayPal", "Unspecified", -1000),
                                     ("02.10.2026", "PayPal", "Unspecified", -2000),
                                     ("03.10.2026", "PAYPAL", "Unspecified", -3000)])
        let payments = try await phone.ledger.payments()
        let first = try #require(payments.first)
        let info = try await phone.renameInfo(id: first.id)
        #expect(info.merchantKey.isEmpty && info.otherPaymentCount == 0 && !info.canRenameShop)
        await #expect(throws: LedgerError.notFound) { _ = try await phone.rename(id: first.id, name: "Shop", scope: .shop) }
        let bank = try await phone.dashboard(auth: auth)
        #expect(bank.nameGroups?.count == 2)
        #expect(bank.nameGroups?[PaymentNames.key(ownName: nil, merchant: "", bankName: "PayPal")]?.count == 2)
        _ = try await phone.rename(id: first.id, name: "Gift", scope: .payment)
        let after = try await phone.dashboard(auth: auth)
        #expect(after.transactions.filter { $0.place == "Gift" }.count == 1)
        #expect(try await phone.ledger.paymentNames().isEmpty)
    }

    @Test func settingRebuildsDashboardAndKeepsStoredNames() async throws {
        let defaults = PhoneTest.defaults()
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries"], defaults: defaults)
        #expect(phone.ownNames && defaults.object(forKey: PhoneBackend.ownNamesKey) == nil)
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "PENNY", "Purchase", -1000)])], auth: auth)
        let payment = try #require(try await phone.ledger.payments().first)
        _ = try await phone.rename(id: payment.id, name: "Local shop", scope: .shop)
        _ = try await phone.rename(id: payment.id, name: "Party", scope: .payment)
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let store = DashboardStore(session: session, backend: phone)
        await store.reload()
        #expect(store.dashboard?.transactions.first?.place == "Party")
        await store.setOwnNames(false)
        #expect(defaults.bool(forKey: "aresium.ownNames") == false)
        #expect(store.dashboard?.transactions.first?.place == "PENNY")
        #expect(store.dashboard?.transactions.first?.isOwnName == false)
        #expect(store.dashboard?.transactions.first?.nameKey == "merchant:penny")
        #expect(try await phone.transactionDetail(id: payment.id, auth: auth).place == "PENNY")
        #expect(try await phone.renameInfo(id: payment.id).ownName == "Party")
        let reopened = PhoneBackend(ledger: phone.ledger, engine: phone.engine, defaults: defaults)
        #expect(!reopened.ownNames)
        await store.setOwnNames(true)
        let row = try #require(store.dashboard?.transactions.first)
        #expect(row.place == "Party" && store.nameGroup(for: row)?.count == 1)
    }

    @Test func groupsUseMerchantOrFoldedOwnNameAndIncludeCashAcrossAllMonths() async throws {
        let phone = try await pennyPhone()
        var dashboard = try await phone.dashboard(auth: auth)
        #expect(dashboard.nameGroups?.count == 1 && dashboard.nameGroups?.values.first?.count == 3)
        let first = try #require(try await phone.ledger.payments().first)
        _ = try await phone.importFiles([PhoneTest.vrBank([("04.10.2026", "Fictional Green Shop", "Purchase", -4000),
                                                         ("05.10.2026", "Fictional Green Shop", "Refund", 500)])], auth: auth)
        let green = try #require(try await phone.ledger.payments().first { $0.place == "Fictional Green Shop" })
        try await phone.ledger.setCategory(green.id, category: "groceries", source: .manual)
        _ = try await phone.rename(id: first.id, name: "Súpermarkt", scope: .shop)
        _ = try await phone.rename(id: green.id, name: "SUPERMARKT", scope: .shop)
        let cash = LedgerReceipt(id: "cash-test", date: "2026-09-10", time: nil, shop: "PENNY Markt", total: "7.25",
                                 currency: "EUR", euroAmount: nil, method: .cash, category: "groceries",
                                 categorySource: .manual, rows: [], from: "text", paymentID: nil, created: .now)
        try await phone.ledger.addReceipt(cash)
        let entry = LedgerReceipt(id: "entry-test", date: "2026-10-06", time: nil, shop: "PENNY Markt", total: "2.75",
                              currency: "EUR", euroAmount: nil, method: .cash, category: "groceries",
                              categorySource: .manual, rows: [], from: "text", paymentID: nil, created: .now, kind: .manual)
        try await phone.ledger.addReceipt(entry)
        dashboard = try await phone.dashboard(auth: auth)
        let group = try #require(dashboard.nameGroups?["own:supermarkt"])
        #expect(group.count == 7 && group.moneyOut == 110 && group.moneyIn == 5)
        #expect(group.months["2026-09"] == PaymentNameAmounts(moneyOut: 17.25, moneyIn: 0))
        #expect(group.months["2026-10"] == PaymentNameAmounts(moneyOut: 92.75, moneyIn: 5))
        #expect(group.rows.map(\.date) == group.rows.map(\.date).sorted(by: >))
        #expect(group.rows.filter { $0.receiptId != nil }.allSatisfy { $0.place == "PENNY Markt" && $0.isOwnName == nil })
        phone.setOwnNames(false)
        dashboard = try await phone.dashboard(auth: auth)
        #expect(dashboard.nameGroups?["merchant:penny markt"]?.count == 5)
        #expect(dashboard.nameGroups?["merchant:fictional green shop"]?.count == 2)
    }

    @Test func excludedAndCoveredPaymentsNeverEnterGroupsAndEmptyMonthsArePresent() async throws {
        let phone = try await phone([("01.08.2026", "Fictional Shop", "Purchase", -1000),
                                     ("01.10.2026", "Fictional Shop", "Purchase", -2000),
                                     ("02.10.2026", "Fictional Shop", "Transfer", -3000),
                                     ("03.10.2026", "Fictional Shop", "Savings", -4000),
                                     ("04.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -5000)],
                                    chosen: ["groceries", "savings-investing", "cash"])
        let payments = try await phone.ledger.payments()
        try await phone.ledger.setCategory(payments[2].id, category: CategoryCatalog.ownTransfers, source: .structural)
        try await phone.ledger.setCategory(payments[3].id, category: "savings-investing", source: .manual)
        let receipt = LedgerReceipt(id: "covered-test", date: "2026-10-05", time: nil, shop: "Fictional Shop", total: "8.00",
                                    currency: "EUR", euroAmount: nil, method: .cash, category: "groceries",
                                    categorySource: .manual, rows: [], from: "text", paymentID: nil, created: .now)
        try await phone.ledger.addReceipt(receipt)
        let dashboard = try await phone.dashboard(auth: auth)
        #expect(dashboard.transactions.contains { $0.coveredBy != nil })
        let groups = try #require(dashboard.nameGroups)
        let all = groups.values.flatMap(\.rows)
        #expect(!all.contains { $0.coveredBy != nil || $0.id == payments[2].id || $0.id == payments[3].id })
        let shop = try #require(groups["merchant:fictional shop"])
        #expect(shop.count == 3 && shop.moneyOut == 38)
        #expect(shop.months["2026-09"] == PaymentNameAmounts())
        #expect(all.count == 4 && Set(all.map(\.id)).count == 4)
        let withdrawal = try #require(payments.first { $0.place == "Geldautomat Fiktivbank" })
        _ = try await phone.rename(id: withdrawal.id, name: "My cash source", scope: .payment)
        let renamed = try await phone.dashboard(auth: auth)
        #expect(renamed.cash?.movements.first { $0.id == withdrawal.id }?.place == "My cash source")
        phone.setOwnNames(false)
        let bank = try await phone.dashboard(auth: auth)
        #expect(bank.cash?.movements.first { $0.id == withdrawal.id }?.place == withdrawal.place)
    }

    @Test func exportFourRoundTripsAndSchemaThreeStillRestores() async throws {
        let phone = try await pennyPhone()
        let payment = try #require(try await phone.ledger.payments().first)
        _ = try await phone.rename(id: payment.id, name: "Supermarket", scope: .shop)
        _ = try await phone.rename(id: payment.id, name: "Birthday", scope: .payment)
        let export = try await phone.export()
        #expect(export.schema == 5 && export.nameRules.count == 1)
        let decoded = try LedgerExport.decode(export.encoded())
        let restored = try await self.phone()
        try await restored.restore(decoded.encoded())
        #expect(try await restored.ledger.payments() == export.payments)
        #expect(try await restored.ledger.paymentNames() == export.nameRules)
        #expect(try await restored.renameInfo(id: payment.id).ownName == "Birthday")
        var three = try JSONSerialization.jsonObject(with: export.encoded()) as! [String: Any]
        three["schema"] = 3
        three.removeValue(forKey: "nameRules")
        three["payments"] = (three["payments"] as! [[String: Any]]).map { $0.filter { $0.key != "ownName" } }
        let old = try await self.phone()
        try await old.restore(JSONSerialization.data(withJSONObject: three))
        #expect(try await old.ledger.payments().allSatisfy { $0.ownName == nil })
        #expect(try await old.ledger.paymentNames().isEmpty)
        // New fields cannot be smuggled into an older export version.
        three["nameRules"] = [["merchant": "penny markt", "name": "Supermarket"]]
        #expect(throws: LedgerError.self) { try LedgerExport.decode(JSONSerialization.data(withJSONObject: three)) }
        var invalid = export
        invalid.nameRules = [PaymentNameRule(merchant: "", name: "Bad")]
        #expect(throws: LedgerError.self) { try invalid.validate(catalog: #require(phone.catalog)) }
        invalid = export
        invalid.payments[0].ownName = String(repeating: "a", count: 61)
        #expect(throws: LedgerError.self) { try invalid.validate(catalog: #require(phone.catalog)) }
    }

    @Test func detailStoreRenamesAndServerOffersNothing() async throws {
        let phone = try await pennyPhone()
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()
        let row = try #require(dashboard.dashboard?.transactions.first)
        let page = dashboard.transactionDetailStore(for: row)
        await page.prepareRename()
        #expect(page.canRename && page.renameInfo?.otherPaymentCount == 2)
        await page.rename(to: "Neighbourhood shop", scope: .shop)
        #expect(page.detail?.place == "Neighbourhood shop" && page.saveError == nil && !page.isSaving)
        #expect(dashboard.dashboard?.transactions.allSatisfy { $0.place == "Neighbourhood shop" } == true)
        let server = DashboardStore(session: session, sample: true)
        await server.reload()
        let serverRow = try #require(server.dashboard?.transactions.first)
        let serverPage = server.transactionDetailStore(for: serverRow)
        await serverPage.prepareRename()
        #expect(!serverPage.canRename && serverPage.renameInfo == nil)
        #expect(server.dashboard?.nameGroups == nil && serverRow.nameKey == nil)
        // A receipt id cannot be renamed through the bank-payment API.
        await #expect(throws: LedgerError.notFound) { _ = try await phone.rename(id: "receipt-only", name: "No", scope: .payment) }
    }

    @Test func phoneSampleUsesItsTemporaryLedgerForRenameAsForCategories() async throws {
        let phone = try await PhoneSample.backend(empty: false, storage: PhoneTest.storage()).backend
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()
        let transaction = try #require(dashboard.dashboard?.transactions.first { $0.receiptId == nil && $0.coveredBy == nil })
        let page = dashboard.transactionDetailStore(for: transaction)
        await page.prepareRename()
        #expect(page.canRename)
        await page.rename(to: "Sample shop", scope: .payment)
        #expect(page.detail?.place == "Sample shop" && page.saveError == nil)
        #expect(try await phone.ledger.payment(transaction.id)?.ownName == "Sample shop")
    }

    @Test func namesAndGroupsRunOnTheLedgerWorker() async throws {
        let phone = try await pennyPhone()
        let payment = try #require(try await phone.ledger.payments().first)
        let recording = PickerTiming.Recording()
        try await PickerTiming.$recording.withValue(recording) {
            _ = try await phone.rename(id: payment.id, name: "Shop", scope: .shop)
            _ = try await phone.renameInfo(id: payment.id)
            _ = try await phone.dashboard(auth: auth)
        }
        let names = recording.values.filter { $0.name.hasPrefix("names.") }
        #expect(names.contains { $0.name == "names.identities" })
        #expect(names.contains { $0.name == "names.groups" })
        #expect(names.contains { $0.name == "names.normalize" })
        #expect(names.contains { $0.name == "names.snapshot" })
        #expect(names.allSatisfy { $0.kind == "worker" })
    }
    @Test func versionThreeMigratesThroughFiveKeepingEveryKindOfRecord() async throws {
        let source = try await pennyPhone()
        let payment = try #require(try await source.ledger.payments().first)
        _ = try await source.switchCategory(id: payment.id, to: "Groceries", auth: auth)
        _ = try await source.saveReceipt(ReceiptDraft(date: "2026-09-01", shop: "PENNY Markt", total: 10,
                                                     currency: "EUR", method: .card, category: "groceries",
                                                     categorySource: .manual, rows: ["Made-up item 10.00"], from: "text"))
        _ = try await source.saveReceipt(ReceiptDraft(date: "2026-10-05", shop: "Fictional Cafe", total: 3,
                                                     currency: "EUR", method: .cash, category: "groceries",
                                                     categorySource: .manual, rows: [], from: "text"))
        try await source.ledger.apply(.remember(ShopNameCorrection(read: "fictionalcafe", name: "Fictional Café")))
        let layout = CsvLayout(separator: ";", header: ["Day", "Shop", "Amount"], dateFormat: "YYYY-MM-DD",
                               numberFormat: "en", columns: .init(date: 0, amount: 2, counterparty: [1]))
        try await source.saveLayout(layout)
        let before = try await source.export()
        let storage = PhoneTest.storage()
        try await Task.detached { try Self.writeVersionThree(before, storage: storage) }.value
        let ledger = try await Task.detached { try storage.open() }.value
        let after = try await ledger.export()
        #expect(after.accounts == before.accounts && after.payments == before.payments)
        #expect(after.receipts == before.receipts && after.learned == before.learned)
        #expect(after.layouts == before.layouts && after.shopNames == before.shopNames)
        #expect(after.categories.map(\.id) == before.categories.map(\.id))
        #expect(after.nameRules.isEmpty && after.payments.allSatisfy { $0.ownName == nil })
        let migrated = PhoneBackend(ledger: ledger, engine: source.engine, defaults: PhoneTest.defaults())
        try await migrated.load()
        _ = try await migrated.rename(id: payment.id, name: "Weekly shop", scope: .shop)
        _ = try await migrated.rename(id: payment.id, name: "Party", scope: .payment)
        let reopened = try await Task.detached { try storage.open() }.value
        #expect(try await reopened.payment(payment.id)?.ownName == "Party")
        #expect(try await reopened.paymentNames().first?.name == "Weekly shop")
        try storage.delete()
        let fresh = try await Task.detached { try storage.open() }.value
        #expect(try await fresh.summary().isEmpty)
        #expect(try await fresh.paymentNames().isEmpty)
    }

    /// Write using only the frozen V3 model definitions, close it, then open with today's migration plan.
    nonisolated private static func writeVersionThree(_ export: LedgerExport, storage: PhoneStorage) throws {
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: LedgerSchemaV3.self)
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration("Aresium", schema: schema,
                                            url: storage.storeURL, cloudKitDatabase: .none))
        let context = ModelContext(container)
        for account in export.accounts {
            context.insert(LedgerSchemaV3.Account(id: account.id, name: account.name, iban: account.iban,
                                                  bank: account.bank, currency: account.currency))
        }
        for payment in export.payments { context.insert(LedgerSchemaV3.Payment(payment)) }
        for category in export.categories {
            context.insert(LedgerSchemaV3.Chosen(id: category.id, customName: category.name, order: category.order))
        }
        for rule in export.learned { context.insert(LedgerSchemaV3.Rule(merchant: rule.merchant, category: rule.category)) }
        for layout in export.layouts {
            context.insert(LedgerSchemaV3.Layout(id: "made-up-layout", layout: try JSONEncoder().encode(layout), savedAt: .now))
        }
        for receipt in export.receipts { context.insert(LedgerSchemaV3.Receipt(receipt)) }
        for correction in export.shopNames {
            context.insert(LedgerSchemaV3.ShopName(read: correction.read, name: correction.name, saved: .now))
        }
        try context.save()
    }

}
