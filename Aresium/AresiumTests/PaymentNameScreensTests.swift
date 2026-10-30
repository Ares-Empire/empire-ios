import Foundation
import Testing
@testable import Aresium

/// Brief 44's logic behind the screens: the row swipe's direction and threshold, what renaming saves and when it asks,
/// the long press following the payment's page, the "All from" line only for a name with other payments, the name's
/// page and how it follows a rename, and the words in both languages. Brief 47: the name edited where it stands (the
/// field starts with the name shown), "Use the bank's name" for this payment alone, the receipts' and the Cash page's
/// rows following their pages. Everything is made up.
struct RowSwipeRuleTests {
    @Test func startsOnlyForAClearlySidewaysDragToTheLeft() {
        #expect(RowSwipeRule.begins(dx: -20, dy: 3, isOpen: false))
        #expect(RowSwipeRule.begins(dx: -20, dy: -9, isOpen: false), "up to about 27° from level")
        #expect(!RowSwipeRule.begins(dx: -20, dy: 11, isOpen: false), "slanted more: the list scrolls")
        #expect(!RowSwipeRule.begins(dx: -4, dy: 20, isOpen: false), "vertical: the list scrolls")
        #expect(!RowSwipeRule.begins(dx: 0, dy: 0, isOpen: false))
        #expect(!RowSwipeRule.begins(dx: 25, dy: 2, isOpen: false), "to the right: the back swipe's")
        #expect(RowSwipeRule.begins(dx: 25, dy: 2, isOpen: true), "to the right on an open row: it closes")
        #expect(!RowSwipeRule.begins(dx: 5, dy: 20, isOpen: true))
    }

    @Test func theRowFollowsTheFingerWithinItsRoom() {
        let width: CGFloat = 378
        #expect(RowSwipeRule.offset(translation: -50, wasOpen: false, width: width) == -50)
        #expect(RowSwipeRule.offset(translation: 40, wasOpen: false, width: width) == 0, "never right of its place")
        #expect(RowSwipeRule.offset(translation: 30, wasOpen: true, width: width) == -RowSwipeRule.actionWidth + 30)
        #expect(RowSwipeRule.offset(translation: 200, wasOpen: true, width: width) == 0)
        #expect(RowSwipeRule.offset(translation: -900, wasOpen: false, width: width) == -width)
    }

    @Test func aFullSwipeIsPastHalfTheRowAndAtLeastTwoActions() {
        #expect(RowSwipeRule.fullSwipe(width: 378) == 378 * 0.55)
        #expect(RowSwipeRule.fullSwipe(width: 200) == RowSwipeRule.actionWidth * 2)
        #expect(!RowSwipeRule.isArmed(offset: -207, width: 378))
        #expect(RowSwipeRule.isArmed(offset: -208, width: 378))
    }

    @Test func lettingGoOpensClosesOrDoesTheAction() {
        let width: CGFloat = 378
        #expect(RowSwipeRule.end(offset: -230, velocity: 0, width: width) == .perform)
        #expect(RowSwipeRule.end(offset: -230, velocity: 900, width: width) == .perform, "past the threshold it counts")
        #expect(RowSwipeRule.end(offset: -60, velocity: 0, width: width) == .open, "past half the action")
        #expect(RowSwipeRule.end(offset: -30, velocity: 0, width: width) == .closed)
        #expect(RowSwipeRule.end(offset: -20, velocity: -600, width: width) == .open, "a fling left")
        #expect(RowSwipeRule.end(offset: -80, velocity: 600, width: width) == .closed, "a fling right")
    }
}

struct RenamePlanTests {
    private func info(payment: String? = nil, shop: String? = nil, key: String = "penny", others: Int = 2)
        -> PaymentRenameInfo {
        PaymentRenameInfo(bankName: "PENNY Markt Berlin", merchantKey: key, paymentOwnName: payment, shopOwnName: shop,
                          otherPaymentCount: others)
    }

    @Test func saveIsOffWhileNothingChanged() {
        #expect(RenamePlan(info: info()).intent("") == .nothing, "no name and nothing typed")
        #expect(RenamePlan(info: info()).intent("  PENNY Markt Berlin ") == .nothing, "the bank's name itself")
        #expect(RenamePlan(info: info(shop: "Weekly shop")).intent(" Weekly shop\n") == .nothing)
        #expect(RenamePlan(info: info(shop: "Weekly shop")).intent("weekly shop") == .name("weekly shop"))
        #expect(RenamePlan(info: info(shop: "Weekly shop")).intent("") == .bankName, "emptied: the bank's name")
        #expect(RenamePlan(info: info(payment: "Party")).intent("PENNY Markt Berlin") == .bankName)
        // Brief 47: the field starts with the name the page shows, the bank's too (all of it selected).
        #expect(RenamePlan(info: info()).start == "PENNY Markt Berlin")
        #expect(RenamePlan(info: info(payment: "Party", shop: "Shop")).start == "Party")
        #expect(RenamePlan(info: info(shop: "Shop")).start == "Shop")
    }

    @Test func theQuestionOnlyWithOtherPaymentsAndAMerchantKey() {
        let asked = RenamePlan(info: info()).outcome(.name("Weekly shop"))
        guard case let .ask(question)? = asked else { Issue.record("asks"); return }
        #expect(question.others == 2 && question.allCount == 3 && question.bankName == "PENNY Markt Berlin")
        #expect(question.all == [.shop("Weekly shop")] && question.onlyThis == [.payment("Weekly shop")])

        #expect(RenamePlan(info: info(others: 0)).outcome(.name("Mine")) == .save([.payment("Mine")]), "N = 0")
        #expect(RenamePlan(info: info(key: "", others: 0)).outcome(.name("Mine")) == .save([.payment("Mine")]),
                "no merchant key")
        #expect(!RenamePlan(info: info(key: "", others: 3)).asksAboutOthers)
    }

    @Test func allAlsoDropsThisPaymentsOwnNameSoItFollowsTheShop() {
        guard case let .ask(question)? = RenamePlan(info: info(payment: "Party", shop: "Shop")).outcome(.name("New"))
        else { Issue.record("asks"); return }
        #expect(question.all == [.shop("New"), .payment("")])
        #expect(question.onlyThis == [.payment("New")])
    }

    @Test func theBanksNameRemovesEveryNameShownAndAsksWhenOthersLoseTheirs() {
        #expect(RenamePlan(info: info(payment: "Party")).outcome(.bankName) == .save([.payment("")]))
        #expect(RenamePlan(info: info(shop: "Shop", others: 0)).outcome(.bankName) == .save([.shop("")]))
        guard case let .confirmBankName(question)? = RenamePlan(info: info(payment: "Party", shop: "Shop"))
            .outcome(.bankName) else { Issue.record("asks first"); return }
        #expect(question.count == 3 && question.shopName == "Shop" && question.steps == [.payment(""), .shop("")])
        #expect(question.onlyThis == [.payment("PENNY Markt Berlin")], "brief 47: the bank's name kept for this one")
        #expect(RenamePlan(info: info()).outcome(.bankName) == nil, "no own name to remove")
    }

    @Test func theBanksNameKeptForOnePaymentReadsAsTheBanksName() {
        // Brief 47: "Only this one" stores the bank's name as the payment's own name.
        let kept = info(payment: "PENNY Markt Berlin", shop: "Weekly shop")
        #expect(kept.keepsBankName && kept.ownName == nil && kept.source == nil)
        let plan = RenamePlan(info: kept)
        #expect(plan.start == "PENNY Markt Berlin")
        #expect(plan.intent("PENNY Markt Berlin") == .nothing && plan.intent("") == .nothing)
        #expect(plan.outcome(.bankName) == nil, "it shows the bank's name already")
        guard case let .ask(question)? = plan.outcome(.name("Party")) else { Issue.record("asks"); return }
        #expect(question.all == [.shop("Party"), .payment("")], "All drops the kept bank's name, so it follows the shop")
        #expect(question.onlyThis == [.payment("Party")])
        // Kept as names are: a long bank line is cut to 60 characters, and still reads as the bank's name.
        let long = String(repeating: "Kartenzahlung PENNY ", count: 4)
        let longInfo = PaymentRenameInfo(bankName: long, merchantKey: "penny", paymentOwnName: PaymentNames.keptBankName(long),
                                         shopOwnName: "Shop", otherPaymentCount: 2)
        #expect(longInfo.keepsBankName && longInfo.ownName == nil)
        #expect(PaymentNames.shown(payment: nil, shop: "Shop", bankName: long) == "Shop")
        #expect(PaymentNames.shown(payment: "Mine", shop: "Shop", bankName: long) == "Mine")
        // A bank line without words cannot be kept: no Only this one.
        let blank = PaymentRenameInfo(bankName: "  ", merchantKey: "x", paymentOwnName: nil, shopOwnName: "Shop",
                                      otherPaymentCount: 2)
        guard case let .confirmBankName(none)? = RenamePlan(info: blank).outcome(.bankName) else {
            Issue.record("asks"); return
        }
        #expect(none.onlyThis == nil)
    }
}

@MainActor
struct PaymentNameScreensTests {
    private let auth = BackendAuth(token: nil)

    /// Three Penny payments (one merchant), two Café Fiktiva visits on another key and one lone shop, in two months.
    private func store(defaults: UserDefaults = PhoneTest.defaults()) async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries", "eating-out"], defaults: defaults)
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.09.2026", "PENNY Markt GmbH München", "Purchase", -1000),
            ("02.10.2026", "Kartenzahlung PENNY Markt 12345", "Purchase", -2000),
            ("03.10.2026", "PENNY Markt Berlin", "Purchase", -3000),
            ("05.10.2026", "PENNY Markt Berlin", "Refund", 500),
            ("04.10.2026", "Fiktiv Einzelladen", "Purchase", -1500)])], auth: auth)
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()
        return (phone, dashboard)
    }

    private func row(_ text: String, amount: Double? = nil, in dashboard: DashboardStore) throws -> Transaction {
        try #require(dashboard.dashboard?.transactions.first {
            $0.place.contains(text) && (amount == nil || $0.amount == amount)
        })
    }

    // MARK: the long press follows the page

    @Test func theMenuOffersWhatThePageOffers() async throws {
        let (_, dashboard) = try await store()
        let transactions = try #require(dashboard.dashboard?.transactions)
        for transaction in transactions {
            let page = dashboard.transactionDetailStore(for: transaction)
            await page.load()
            let actions = dashboard.rowActions(for: transaction)
            #expect(actions.contains(.rename) == page.offersRename, "\(transaction.place)")
            #expect(actions.contains(.allFromName) == (page.nameRoute() != nil), "\(transaction.place)")
            #expect(actions.contains(.changeCategory) == !page.choices.isEmpty)
            // On the name's own page neither offers it.
            if let key = transaction.nameKey {
                #expect(!dashboard.rowActions(for: transaction, namePage: key).contains(.allFromName))
                #expect(page.nameRoute(namePage: key) == nil)
            }
        }
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        #expect(dashboard.rowActions(for: penny) == [.changeCategory, .rename, .allFromName])
        let lone = try row("Einzelladen", in: dashboard)
        #expect(dashboard.rowActions(for: lone) == [.changeCategory, .rename], "a name with one payment has no line")
    }

    @Test func ownNamesOffOffersNoRenameAndShowsTheBanksName() async throws {
        let (phone, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        _ = try await phone.rename(id: penny.id, name: "Weekly shop", scope: .payment)
        await dashboard.setOwnNames(false)
        let shown = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        #expect(!dashboard.rowActions(for: shown).contains(.rename))
        let page = dashboard.transactionDetailStore(for: shown)
        await page.load()
        #expect(!page.offersRename && page.canRename, "the names are kept, the page offers no Rename")
        #expect(page.detail?.place == "PENNY Markt Berlin" && page.detail?.bankName == nil)
    }

    @Test func theLineOnlyForANameWithOtherPaymentsThatCount() async throws {
        let (_, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        let key = try #require(penny.nameKey)
        let group = try #require(dashboard.shownNameGroup(id: penny.id, key: key))
        #expect(group.count == 4 && group.moneyOut == 60 && group.moneyIn == 5)
        #expect(dashboard.shownNameGroup(id: "not-in-it", key: key) == nil, "a row outside the group (an own transfer)")
        #expect(dashboard.nameRoute(for: penny)?.name == PaymentNameRoute(key: key, title: "PENNY Markt Berlin"))
        #expect(dashboard.nameRoute(for: try row("Einzelladen", in: dashboard)) == nil)
    }

    // MARK: renaming through the window's model

    @Test func aNewNameAsksAndAllNamesTheShop() async throws {
        let (phone, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        let page = dashboard.transactionDetailStore(for: penny)
        await page.prepareRename()
        #expect(page.offersRename && page.renameInfo?.otherPaymentCount == 3)
        let model = PaymentRenameModel(store: page)
        #expect(!model.canSave && !model.hasChanges && model.text == "PENNY Markt Berlin", "the name shown, selected")
        model.text = "Weekly shop"
        #expect(model.canSave && model.hasChanges)
        await model.save()
        let question = try #require(model.question)
        #expect(question.others == 3 && !model.isDone, "asked while the field is open")
        await model.answer(all: true)
        #expect(model.isDone && model.question == nil, "the field closes")
        let names = try #require(dashboard.dashboard?.transactions).filter { $0.bankName != nil }.map(\.place)
        #expect(names == Array(repeating: "Weekly shop", count: 4))
        #expect(try await phone.renameInfo(id: penny.id).shopOwnName == "Weekly shop")
        #expect(page.detail?.place == "Weekly shop" && page.detail?.bankName == "PENNY Markt Berlin")
    }

    @Test func onlyThisOneNamesThePaymentAlone() async throws {
        let (phone, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        let page = dashboard.transactionDetailStore(for: penny)
        await page.prepareRename()
        let model = PaymentRenameModel(store: page)
        model.text = "Party"
        await model.save()
        await model.answer(all: false)
        let info = try await phone.renameInfo(id: penny.id)
        #expect(info.paymentOwnName == "Party" && info.shopOwnName == nil)
        #expect(try #require(dashboard.dashboard?.transactions).filter { $0.isOwnName == true }.count == 1)
    }

    @Test func returnWithoutAChangeOnlyClosesTheField() async throws {
        let (phone, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        let page = dashboard.transactionDetailStore(for: penny)
        await page.prepareRename()
        let model = PaymentRenameModel(store: page)
        await model.save()
        #expect(model.isDone && model.question == nil)
        #expect(try await phone.renameInfo(id: penny.id).paymentOwnName == nil, "nothing saved")
    }

    @Test func aLoneShopIsRenamedWithoutAQuestion() async throws {
        let (phone, dashboard) = try await store()
        let lone = try row("Einzelladen", in: dashboard)
        let page = dashboard.transactionDetailStore(for: lone)
        await page.prepareRename()
        let model = PaymentRenameModel(store: page)
        model.text = "Gift shop"
        await model.save()
        #expect(model.question == nil, "N = 0: only this payment, no question")
        #expect(try await phone.renameInfo(id: lone.id).paymentOwnName == "Gift shop")
    }

    @Test func theBanksNameForAShopAsksThenRemovesIt() async throws {
        let (phone, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        _ = try await phone.rename(id: penny.id, name: "Weekly shop", scope: .shop)
        await dashboard.reloadAfterTransactionChange()
        let page = dashboard.transactionDetailStore(for: penny)
        await page.prepareRename()
        let model = PaymentRenameModel(store: page)
        #expect(model.text == "Weekly shop")
        await model.useBankName()
        #expect(model.bankNameQuestion?.count == 4)
        await model.answerBankName(.cancel)
        #expect(try await phone.renameInfo(id: penny.id).shopOwnName == "Weekly shop", "Cancel keeps it")
        await model.useBankName()
        await model.answerBankName(.all)
        #expect(try await phone.renameInfo(id: penny.id).ownName == nil)
        #expect(try #require(dashboard.dashboard?.transactions).allSatisfy { $0.isOwnName != true })
    }

    @Test func theBanksNameForThisOneKeepsTheShopsNameForTheOthers() async throws {
        // Brief 47: "Use the bank's name" on a payment named through its shop → Only this one.
        let (phone, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        _ = try await phone.rename(id: penny.id, name: "Weekly shop", scope: .shop)
        await dashboard.reloadAfterTransactionChange()
        let page = dashboard.transactionDetailStore(for: penny)
        await page.prepareRename()
        let model = PaymentRenameModel(store: page)
        await model.useBankName()
        #expect(model.bankNameQuestion?.onlyThis != nil)
        await model.answerBankName(.onlyThis)
        #expect(model.isDone)

        let info = try await phone.renameInfo(id: penny.id)
        #expect(info.shopOwnName == "Weekly shop" && info.keepsBankName && info.ownName == nil && info.source == nil)
        let rows = try #require(dashboard.dashboard?.transactions)
        let alone = try #require(rows.first { $0.id == penny.id })
        #expect(alone.place == "PENNY Markt Berlin" && alone.bankName == nil && alone.isOwnName == false
                && alone.ownNameSource == nil, "this payment shows the bank's name")
        let others = rows.filter { $0.id != penny.id && $0.place == "Weekly shop" }
        #expect(others.count == 3 && others.allSatisfy { $0.ownNameSource == .shop }, "the others keep the shop's name")
        let shopKey = try #require(others.first?.nameKey)
        #expect(alone.nameKey != shopKey, "it counts with the bank's name, not the shop's")
        #expect(dashboard.dashboard?.nameGroups?[shopKey]?.count == 3)
        #expect(page.detail?.place == "PENNY Markt Berlin" && page.detail?.bankName == nil)
        #expect(!dashboard.rowActions(for: alone).contains(.allFromName), "its name has no other payment")

        // A later name for the whole shop takes it along again; one for this payment alone replaces the kept name.
        let again = PaymentRenameModel(store: page)
        #expect(again.text == "PENNY Markt Berlin")
        again.text = "Groceries run"
        await again.save()
        await again.answer(all: true)
        #expect(try await phone.renameInfo(id: penny.id).paymentOwnName == nil)
        #expect(try #require(dashboard.dashboard?.transactions).filter { $0.place == "Groceries run" }.count == 4)
    }

    @Test func theBanksNameForThisOneSurvivesExportAndRestore() async throws {
        let (phone, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        _ = try await phone.rename(id: penny.id, name: "Weekly shop", scope: .shop)
        _ = try await phone.rename(id: penny.id, name: PaymentNames.keptBankName(penny.place), scope: .payment)
        let export = try await phone.export()
        let restored = try await PhoneCountingTests.backend(chosen: ["groceries", "eating-out"])
        try await restored.restore(LedgerExport.decode(export.encoded()).encoded())
        let info = try await restored.renameInfo(id: penny.id)
        #expect(info.keepsBankName && info.shopOwnName == "Weekly shop")
        let rows = try await restored.dashboard(auth: auth).transactions
        #expect(rows.first { $0.id == penny.id }?.place == "PENNY Markt Berlin")
        #expect(rows.filter { $0.place == "Weekly shop" }.count == 3)
    }

    // MARK: the name's page

    @Test func theNamesPageCountsItsMonthsAndListsNewestFirst() async throws {
        let (_, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        let board = try #require(dashboard.dashboard)
        let group = try #require(dashboard.shownNameGroup(id: penny.id, key: penny.nameKey))
        let page = NamePage(group: group, dashboard: board, language: .english)
        #expect(page.count == 4 && page.moneyOut == 60 && page.moneyIn == 5 && page.spends)
        #expect(page.months.map(\.month.key) == ["2026-09", "2026-10"], "as the category page: oldest first")
        #expect(page.months.map(\.total) == [10, 50])
        #expect(page.chart.count == board.months.count && page.chart.map(\.value).reduce(0, +) == 60)
        #expect(page.sections.map(\.month) == ["2026-10", "2026-09"], "the payments newest first")
        #expect(page.sections.first?.rows.map(\.amount) == [5, -30, -20])
        #expect(page.range == "Sep 2026 – Oct 2026")
        #expect(page.category.name == "Groceries")
    }

    @Test func thePageFollowsARenameOfItsWholeName() async throws {
        let (phone, dashboard) = try await store()
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        let route = PaymentNameRoute(key: try #require(penny.nameKey), title: penny.place)

        // Only this one: the payment leaves, the page stays.
        _ = try await phone.rename(id: penny.id, name: "Party", scope: .payment)
        await dashboard.reloadAfterTransactionChange()
        #expect(route.following(try row("Party", in: dashboard), groups: dashboard.dashboard?.nameGroups) == nil)

        // The shop renamed: the page follows to the new name.
        _ = try await phone.rename(id: penny.id, name: "", scope: .payment)
        _ = try await phone.rename(id: penny.id, name: "Weekly shop", scope: .shop)
        await dashboard.reloadAfterTransactionChange()
        let renamed = try row("Weekly shop", amount: -30, in: dashboard)
        let next = try #require(route.following(renamed, groups: dashboard.dashboard?.nameGroups))
        #expect(next == PaymentNameRoute(key: try #require(renamed.nameKey), title: "Weekly shop"))

        // The same name spelt differently: the title follows, the key stays.
        _ = try await phone.rename(id: penny.id, name: "WEEKLY SHOP", scope: .shop)
        await dashboard.reloadAfterTransactionChange()
        let shouted = try row("WEEKLY SHOP", amount: -30, in: dashboard)
        #expect(next.following(shouted, groups: dashboard.dashboard?.nameGroups)
                == PaymentNameRoute(key: next.key, title: "WEEKLY SHOP"))
        #expect(next.following(nil, groups: dashboard.dashboard?.nameGroups) == nil)
    }

    // MARK: the words

    @Test func theWordsInBothLanguages() {
        #expect(NameWording.allFrom("Penny", language: .english) == "All from Penny")
        #expect(NameWording.allFrom("Penny", language: .german) == "Alle von Penny")
        #expect(NameWording.summary(count: 23, moneyOut: 412.3, moneyIn: 0, language: .english)
                == "23 payments · €412.30 spent")
        #expect(NameWording.summary(count: 1, moneyOut: 0, moneyIn: 12, language: .english) == "1 payment · €12.00 received")
        #expect(NameWording.summary(count: 23, moneyOut: 412.3, moneyIn: 12, language: .german)
                == "23 Buchungen · 412,30\u{a0}€ ausgegeben · 12,00\u{a0}€ erhalten")
        #expect(NameWording.pageLine(count: 2, range: "Sep 2026 – Oct 2026", language: .german)
                == "2 Buchungen · Sep 2026 – Oct 2026")
    }
}
