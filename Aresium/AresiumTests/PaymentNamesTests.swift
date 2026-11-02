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

    @Test func newestBankNameFollowsEveryRowDetailListAndRenameStart() async throws {
        let phone = try await pennyPhone()
        let payments = try await phone.ledger.payments()
        let oldest = try #require(payments.first)
        let newest = try #require(payments.last)
        let before = try await phone.ledger.sortingSnapshot()
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let store = DashboardStore(session: session, backend: phone)
        await store.reload()
        let rows = try #require(store.dashboard?.transactions)
        #expect(rows.allSatisfy { $0.place == newest.place && $0.isOwnName == false && $0.ownNameSource == nil })
        #expect(rows.first { $0.id == oldest.id }?.bankName == oldest.place)
        #expect(rows.first { $0.id == newest.id }?.bankName == nil)
        let detail = try await phone.transactionDetail(id: oldest.id, auth: auth)
        #expect(detail.place == newest.place && detail.bankName == oldest.place && detail.isOwnName == false)
        let info = try await phone.renameInfo(id: oldest.id)
        let plan = RenamePlan(info: info)
        #expect(plan.start == newest.place && plan.intent(plan.start) == .nothing)
        #expect(plan.intent("") == .nothing && plan.intent(oldest.place) == .nothing)
        let group = try #require(store.nameGroup(for: rows[0]))
        #expect(group.rows.allSatisfy { $0.place == newest.place })
        let page = try #require(store.namePage(rows[0].nameKey!))
        #expect(page.months.flatMap(\.rows).allSatisfy { $0.transaction.place == newest.place })
        store.sums.setEverywhere(true)
        let list = store.paymentList(category: "Groceries", month: "2026-10", side: .expenses)
        #expect(list.entries.contains { if case let .summed(sum) = $0 { return sum.title == newest.place }; return false })
        #expect(store.searchNames(oldest.place).first?.matchedName == oldest.place)
        #expect(try await phone.ledger.sortingSnapshot().payments == before.payments)

        _ = try await phone.rename(id: oldest.id, name: "Weekly shop", scope: .shop)
        _ = try await phone.rename(id: oldest.id, name: "Party", scope: .payment)
        let own = try await phone.dashboard(auth: auth)
        #expect(own.transactions.first { $0.id == oldest.id }?.place == "Party")
        #expect(own.transactions.filter { $0.id != oldest.id }.allSatisfy { $0.place == "Weekly shop" })
        await store.setOwnNames(false)
        #expect(store.dashboard?.transactions.allSatisfy { $0.place == newest.place && $0.isOwnName == false } == true)
        #expect(store.searchNames("Party").first?.matchedName == "Party", "hidden own names remain searchable")
        #expect(store.searchNames("Weekly shop").first?.matchedName == "Weekly shop")
        let hit = try #require(store.searchNames("Party").first)
        #expect(store.nameGroup(hit.key)?.count == 3 && store.builtNameSearch.revision == store.revision)
        await store.setOwnNames(true)
        #expect(store.searchNames("Party").first?.key != hit.key, "a new dashboard rebuilds the cached index")
        #expect(store.builtNameSearch.revision == store.revision)
        await store.setOwnNames(false)
        #expect(try await phone.transactionDetail(id: oldest.id, auth: auth).bankName == oldest.place)
    }

    @Test func bankNameUsesBookingDateThenStoreOrderAndNeverGroupsEmptyKeys() async throws {
        let phone = try await pennyPhone()
        let payments = try await phone.ledger.payments()
        var old = payments[0], first = payments[1], last = payments[2]
        // The dates are immutable; use the two October rows as a same-day pair copied from one payment.
        first.counterparty = "Fictional earlier line"
        last = first
        last.counterparty = "Fictional later line"
        old.counterparty = "Fictional older line"
        let identities = ShopIdentities(byKey: ["old": "shop", "new": "shop", "": "shop"])
        let names = PaymentNames.bankNames(payments: [first, last, old], keys: ["old", "new", "old"],
                                           bankLineIdentities: ["shop", "shop", "shop"], identities: identities)
        #expect(names["shop"] == "Fictional later line", "later store order breaks a booking-date tie; older date cannot win")
        #expect(PaymentNames.bankNames(payments: [last], keys: [""], bankLineIdentities: ["shop"], identities: identities).isEmpty)
        let bare = try await self.phone([("01.10.2026", "PayPal", "Unspecified", -1000),
                                        ("02.10.2026", "PAYPAL", "Unspecified", -2000)])
        #expect(try await bare.dashboard(auth: auth).transactions.map(\.place) == ["PayPal", "PAYPAL"])
    }

    @Test func madeUpShopIdentitySharesNewestBankLineIncludingCashWithdrawals() async throws {
        let phone = try await pennyPhone()
        var payments = try await phone.ledger.payments()
        payments[0].counterparty = "MGP Luma - Old Market"
        payments[1].counterparty = "Luma, Ltd"
        payments[2].counterparty = "Luma, Ltd"
        var dashboard = try Dashboard.sample()
        dashboard.transactions = payments.map {
            Transaction(id: $0.id, date: $0.bookingDate, day: Int($0.bookingDate.suffix(2))!, month: String($0.bookingDate.prefix(7)),
                        amount: $0.amountValue, categoryName: "Groceries", tags: [], place: $0.place, city: "",
                        categoriesIn: ["Groceries"], incomeBuckets: [])
        }
        let receipt = LedgerReceipt(id: "typed-shop", date: "2026-10-04", time: nil, shop: "Luma receipt as typed", total: "2.00",
                                    currency: "EUR", euroAmount: nil, method: .cash, category: "groceries", categorySource: .manual,
                                    rows: [], from: "text", paymentID: nil, created: .now)
        dashboard.transactions.append(Transaction(id: "receipt:typed-shop", date: receipt.date, day: 4, month: "2026-10", amount: -2,
                                                   categoryName: "Groceries", tags: [], place: receipt.shop!, city: "",
                                                   categoriesIn: ["Groceries"], incomeBuckets: [], receiptId: receipt.id))
        dashboard.cash = CashView(months: [:], movements: [CashMovement(id: payments[0].id, date: payments[0].bookingDate,
                                  amount: 10, kind: .withdrawal, place: payments[0].place, category: "Cash withdrawals",
                                  paidFrom: nil, coveredBy: [], left: 10)])
        let source = dashboard, bank = payments
        let named = await Task.detached {
            var result = source
            PaymentNames.apply(to: &result, payments: bank, paymentKeys: ["old luma", "luma", "luma"],
                               bankLineIdentities: ["luma-shop", "luma-shop", "luma-shop"], receipts: [receipt], receiptKeys: ["receipt luma"], rules: [:],
                               identities: ShopIdentities(byKey: ["old luma": "luma-shop", "luma": "luma-shop", "receipt luma": "luma-shop"]),
                               enabled: true)
            return result
        }.value
        #expect(named.transactions.prefix(3).allSatisfy { $0.place == "Luma, Ltd" && $0.isOwnName == false })
        #expect(named.transactions.first?.bankName == "MGP Luma - Old Market")
        #expect(named.cash?.movements.first?.place == "Luma, Ltd")
        #expect(named.transactions.last?.place == "Luma receipt as typed")
        let groups = try #require(named.nameGroups)
        let hit = try #require(NameSearch.results(for: "mgp luma", in: groups).first)
        #expect(hit.count == 4 && hit.matchedName == "MGP Luma - Old Market")
    }

    @Test(arguments: [true, false])
    func paymentServiceLineCannotBecomeItsShopsName(ownNames: Bool) async throws {
        let phone = try await self.phone()
        let shopName = "Fictional Shop, UAB"
        let serviceName = "PayPal Europe S.a.r.l. et Cie S.C.A"
        let paypal = ImportFile(name: "fictional-shop-paypal.csv", data: Data("""
        Datum,Name,Typ,Währung,Brutto,Netto,Transaktionscode,Auswirkung auf Guthaben
        01.10.2026,"Fictional Shop, UAB",Allgemeine Zahlung,EUR,"-10,00","-10,00",FICTIONAL-SHOP-PURCHASE,Debit
        """.utf8))
        _ = try await phone.importFiles([paypal, PhoneTest.vrBank([
            ("02.10.2026", serviceName, "Ihr Einkauf bei Fictional Shop, UAB", -2000)])], auth: auth)
        let payments = try await phone.ledger.payments()
        let older = try #require(payments.first { $0.source == "paypal" })
        let newer = try #require(payments.first { $0.source == "bank" })
        for payment in payments { try await phone.ledger.setCategory(payment.id, category: "groceries", source: .manual) }
        let snapshot = try await phone.ledger.shopSnapshot(engine: phone.engine)
        let olderIndex = try #require(snapshot.payments.firstIndex { $0.id == older.id })
        let newerIndex = try #require(snapshot.payments.firstIndex { $0.id == newer.id })
        let identity = snapshot.shops.identity(snapshot.paymentKeys[olderIndex])
        #expect(!identity.isEmpty && identity == snapshot.shops.identity(snapshot.paymentKeys[newerIndex]))
        #expect(snapshot.bankLineIdentities[olderIndex] == identity)
        #expect(snapshot.bankLineIdentities[newerIndex] != identity, "the engine sees only the payment service in its line")
        let before = try await phone.ledger.payments()
        phone.setOwnNames(ownNames)
        let dashboard = try await phone.dashboard(auth: auth)
        #expect(dashboard.transactions.count == 2)
        #expect(dashboard.transactions.allSatisfy { $0.place == shopName && $0.isOwnName == false && $0.ownNameSource == nil })
        #expect(dashboard.transactions.first { $0.id == older.id }?.bankName == nil)
        #expect(dashboard.transactions.first { $0.id == newer.id }?.bankName == serviceName)
        for payment in [older, newer] {
            let detail = try await phone.transactionDetail(id: payment.id, auth: auth)
            #expect(detail.place == shopName && detail.isOwnName == false)
            #expect(detail.bankName == (payment.id == newer.id ? serviceName : nil))
            let info = try await phone.renameInfo(id: payment.id)
            #expect(info.shopBankName == shopName && RenamePlan(info: info).start == shopName)
        }
        let groups = try #require(dashboard.nameGroups)
        let group = try #require(groups.values.first)
        #expect(groups.count == 1 && group.count == 2 && group.moneyOut == 30)
        #expect(group.rows.allSatisfy { $0.place == shopName })
        #expect(NameSearch.results(for: serviceName, in: groups).first?.matchedName == serviceName)
        #expect(try await phone.ledger.payments() == before, "original fields and categories remain unchanged")
    }

    @Test(arguments: [true, false])
    func newerCardStatementUsesTheShopsPlainPayPalLine(ownNames: Bool) async throws {
        let phone = try await self.phone()
        let shopName = "Fictional Shop, UAB"
        let cardLine = "FICTIONAL SHOP, UAB   IRL CORK   EUR  14,99   Umsatz vom 02.10.2026   MC Fictional Card"
        let paypal = ImportFile(name: "fictional-card-shop-paypal.csv", data: Data("""
        Datum,Name,Typ,Währung,Brutto,Netto,Transaktionscode,Auswirkung auf Guthaben
        01.10.2026,"Fictional Shop, UAB",Allgemeine Zahlung,EUR,"-10,00","-10,00",FICTIONAL-PLAIN-SHOP,Debit
        """.utf8))
        _ = try await phone.importFiles([paypal, PhoneTest.vrBank([
            ("02.10.2026", cardLine, "Fictional card purchase", -1499)])], auth: auth)
        let payments = try await phone.ledger.payments()
        let plain = try #require(payments.first { $0.source == "paypal" })
        let card = try #require(payments.first { $0.source == "bank" })
        for payment in payments { try await phone.ledger.setCategory(payment.id, category: "groceries", source: .manual) }
        let snapshot = try await phone.ledger.shopSnapshot(engine: phone.engine)
        let plainIndex = try #require(snapshot.payments.firstIndex { $0.id == plain.id })
        let cardIndex = try #require(snapshot.payments.firstIndex { $0.id == card.id })
        let identity = snapshot.shops.identity(snapshot.paymentKeys[plainIndex])
        #expect(!identity.isEmpty && snapshot.shops.identity(snapshot.paymentKeys[cardIndex]) == identity)
        var lineOnly = card.sorting(raw: false)
        lineOnly.counterparty = card.place
        lineOnly.description = ""
        let keys = try await phone.engine.merchantKeys([lineOnly])
        #expect(snapshot.shops.identity(keys[0]) == identity, "the card line names the shop but still cannot name other rows")
        #expect(snapshot.bankLineIdentities[plainIndex] == identity && snapshot.bankLineIdentities[cardIndex].isEmpty)
        phone.setOwnNames(ownNames)
        let dashboard = try await phone.dashboard(auth: auth)
        #expect(dashboard.transactions.count == 2)
        #expect(dashboard.transactions.allSatisfy { $0.place == shopName && $0.isOwnName == false })
        #expect(dashboard.transactions.first { $0.id == card.id }?.bankName == cardLine)
        #expect(dashboard.transactions.first { $0.id == plain.id }?.bankName == nil)
        for payment in [plain, card] {
            let detail = try await phone.transactionDetail(id: payment.id, auth: auth)
            #expect(detail.place == shopName && detail.isOwnName == false)
            #expect(detail.bankName == (payment.id == card.id ? cardLine : nil))
            let info = try await phone.renameInfo(id: payment.id)
            #expect(info.shopBankName == shopName && RenamePlan(info: info).start == shopName)
        }
        let groups = try #require(dashboard.nameGroups)
        #expect(groups.count == 1 && groups.values.first?.count == 2 && groups.values.first?.moneyOut == 24.99)
        #expect(groups.values.first?.rows.allSatisfy { $0.place == shopName } == true)
        #expect(try await phone.ledger.payments().map(\.place) == payments.map(\.place))
    }

    @Test func aShopWithOnlyCardStatementsKeepsEachPaymentsOwnLine() async throws {
        let first = "FICTIONAL SHOP, UAB   IRL CORK   EUR  10,00   Umsatz vom 01.10.2026   MC Fictional Card"
        let second = "FICTIONAL SHOP, UAB   IRL CORK   EUR  20,00   Umsatz vom 02.10.2026   MC Fictional Card"
        let phone = try await self.phone([
            ("01.10.2026", first, "Fictional card purchase", -1000),
            ("02.10.2026", second, "Fictional card purchase", -2000)])
        let payments = try await phone.ledger.payments()
        for payment in payments { try await phone.ledger.setCategory(payment.id, category: "groceries", source: .manual) }
        let snapshot = try await phone.ledger.shopSnapshot(engine: phone.engine)
        #expect(!snapshot.shops.identity(snapshot.paymentKeys[0]).isEmpty)
        #expect(snapshot.shops.identity(snapshot.paymentKeys[0]) == snapshot.shops.identity(snapshot.paymentKeys[1]))
        #expect(snapshot.bankLineIdentities == ["", ""])
        for enabled in [true, false] {
            phone.setOwnNames(enabled)
            let dashboard = try await phone.dashboard(auth: auth)
            #expect(dashboard.transactions.map(\.place) == [first, second])
            #expect(dashboard.transactions.allSatisfy { $0.bankName == nil && $0.isOwnName == false })
            for payment in payments {
                let detail = try await phone.transactionDetail(id: payment.id, auth: auth)
                #expect(detail.place == payment.place && detail.bankName == nil)
                let info = try await phone.renameInfo(id: payment.id)
                #expect(info.shopBankName == nil && RenamePlan(info: info).start == payment.place)
            }
        }
    }

    @Test func aShopWithoutAnyQualifyingBankLineKeepsEachPaymentsOwnLine() async throws {
        let phone = try await self.phone([
            ("02.10.2026", "PayPal Europe S.a.r.l. et Cie S.C.A", "Ihr Einkauf bei Fictional Shop, UAB", -1000),
            ("03.10.2026", "PayPal", "Ihr Einkauf bei Fictional Shop, UAB", -2000)])
        let snapshot = try await phone.ledger.shopSnapshot(engine: phone.engine)
        let identity = snapshot.shops.identity(snapshot.paymentKeys[0])
        #expect(!identity.isEmpty && identity == snapshot.shops.identity(snapshot.paymentKeys[1]))
        #expect(snapshot.bankLineIdentities.allSatisfy { $0 != identity })
        let dashboard = try await phone.dashboard(auth: auth)
        let originals = Dictionary(uniqueKeysWithValues: snapshot.payments.map { ($0.id, $0.place) })
        for row in dashboard.transactions {
            #expect(row.place == originals[row.id] && row.bankName == nil && row.isOwnName == false)
            let detail = try await phone.transactionDetail(id: row.id, auth: auth)
            #expect(detail.place == originals[row.id] && detail.bankName == nil)
            #expect(try await phone.renameInfo(id: row.id).shopBankName == nil)
        }
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
        #expect(restored.transactions.allSatisfy { $0.isOwnName == false && $0.place == "PENNY Markt Berlin" && $0.ownNameSource == nil })
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

    /// Brief 71: money out counts as spending whatever its category's side, so it belongs to its name's group too.
    @Test func moneyOutInAnIncomeCategoryJoinsItsNamesGroup() async throws {
        let phone = try await phone([("01.10.2026", "Fictional Buyer", "Sale", 4000),
                                     ("03.10.2026", "Fictional Buyer", "Sale given back", -1500)],
                                    chosen: ["groceries", "selling-things"])
        for payment in try await phone.ledger.payments() {
            try await phone.ledger.setCategory(payment.id, category: "selling-things", source: .manual)
        }
        let dashboard = try await phone.dashboard(auth: auth)
        let back = try #require(dashboard.transactions.first { $0.amount < 0 })
        #expect(!back.categoriesIn.isEmpty && back.incomeBuckets.isEmpty, "spending under Selling things")
        let group = try #require(dashboard.nameGroups?["merchant:fictional buyer"])
        #expect(group.count == 2 && group.moneyIn == 40 && group.moneyOut == 15)
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
        #expect(export.schema == 7 && export.nameRules.count == 1)
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
