import Foundation
import SwiftData
import Testing
@testable import Aresium

@MainActor
struct CategorySideTests {
    private let auth = BackendAuth(token: nil)

    private nonisolated static func payment(_ id: String, amount: String, category: String?, extras: [String] = []) -> LedgerPayment {
        LedgerPayment(id: id, account: "bank:fictional", source: "bank", externalId: id,
                      bookingDate: "2026-10-05", amount: amount, currency: "EUR", text: "Fictional payment",
                      category: category, categorySource: category == nil ? .none : .manual,
                      extraCategories: extras, sequence: 0)
    }

    nonisolated enum OldCase: CaseIterable, Sendable {
        case ownIncome, ownSpending, ownEmpty, ownTied, friendsIncome, friendsSpending, incomeEmpty, incomeWithOut
        case cashIncome, waitingCard, joinedCard, foreignCard, tagOnly

        var id: String {
            switch self {
            case .friendsIncome, .friendsSpending: "friends"
            case .incomeEmpty, .incomeWithOut: "selling-things"
            default: "custom-example"
            }
        }
        var amounts: [String] {
            switch self {
            case .ownIncome, .friendsIncome: ["-10", "20"]
            case .ownSpending, .friendsSpending: ["-20", "10"]
            case .ownTied: ["-10", "10"]
            case .incomeWithOut: ["-10"]
            case .waitingCard, .joinedCard, .foreignCard: ["5"]
            default: []
            }
        }
        var side: String? {
            switch self {
            case .friendsIncome, .friendsSpending, .incomeEmpty, .incomeWithOut: nil
            case .ownIncome, .cashIncome, .joinedCard, .foreignCard: "income"
            default: "spend"
            }
        }
    }

    /// Written with the frozen version 5 models, without current-model attributes or a migration plan.
    private nonisolated static func makeVersion5(_ storage: PhoneStorage, scenario: OldCase) throws {
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        let schema = Schema(versionedSchema: LedgerSchemaV5.self)
        let config = ModelConfiguration("Aresium", schema: schema, url: storage.storeURL, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: config)
        let context = ModelContext(container)
        context.insert(LedgerSchemaV5.Account(id: "bank:fictional", name: "Fictional bank", iban: nil, bank: nil, currency: "EUR"))
        context.insert(LedgerSchemaV5.Chosen(id: scenario.id,
                                            customName: ChosenCategory.isCustom(scenario.id) ? "Fictional club" : nil, order: 0))
        for (index, amount) in scenario.amounts.enumerated() {
            context.insert(LedgerSchemaV5.Payment(payment("p\(index)", amount: amount, category: scenario.id)))
        }
        if scenario == .tagOnly {
            context.insert(LedgerSchemaV5.Payment(payment("tag", amount: "50", category: nil, extras: [scenario.id])))
        }
        if [.cashIncome, .waitingCard, .joinedCard, .foreignCard].contains(scenario) {
            let receipt = LedgerReceipt(id: "r1", date: "2026-10-05", time: nil, shop: "Fictional shop", total: "20",
                                        currency: scenario == .foreignCard ? "GBP" : "EUR", euroAmount: nil,
                                        method: scenario == .cashIncome ? .cash : .card,
                                        category: scenario.id, categorySource: .manual, rows: [], from: "text",
                                        paymentID: scenario == .joinedCard ? "p0" : nil, created: .distantPast,
                                        direction: scenario == .cashIncome ? .in : .out,
                                        kind: scenario == .cashIncome ? .manual : .receipt)
            context.insert(LedgerSchemaV5.Receipt(receipt))
        }
        try context.save()
    }

    @Test(arguments: OldCase.allCases)
    func version5GetsSidesOnce(scenario: OldCase) async throws {
        let storage = PhoneTest.storage()
        try await Task.detached { try Self.makeVersion5(storage, scenario: scenario) }.value
        let ledger = try await Task.detached { try storage.open() }.value
        let category = try #require(try await ledger.chosen().first)
        #expect(category.side == scenario.side)
        #expect(category.otherSide == (scenario == .friendsIncome))
        #expect(try await ledger.payments().count == scenario.amounts.count + (scenario == .tagOnly ? 1 : 0))
        // A later deliberate removal is never undone by reopening a migrated store.
        try await ledger.setOtherSide(false, for: scenario.id)
        if ChosenCategory.isCustom(scenario.id) { try await ledger.setSide(.spend, of: scenario.id) }
        let expected = try await ledger.chosen()
        let reopened = try await Task.detached { try storage.open() }.value
        #expect(try await reopened.chosen() == expected)
    }

    @Test func sourcesAndOfferingMatchTheEngineForEveryChosenCategory() async throws {
        let phone = try await PhoneTest.backend()
        let catalog = try #require(phone.catalog)
        for category in catalog.defaults { try await phone.choose(category.id, sorting: false) }
        let spend = try await phone.addCustom(named: "Fictional hobby", side: .spend)
        let income = try await phone.addCustom(named: "Fictional work", side: .income)
        for id in ["friends", "selling-things", spend, income] { try await phone.setOtherSide(true, for: id) }
        // Include primary payments and tags; none may change a category's explicit home side.
        try await phone.ledger.addReceipt(CashEntryDraft(direction: .in, amount: 20, date: "2026-10-05",
                                                        what: "Fictional repayment", category: "friends").receipt(id: "repayment"))
        let list = try await phone.categories()
        let source = list.sourceCategories
        #expect(source.first { $0.name == "Friends" }?.side == "spend")
        #expect(source.first { $0.name == "Selling things" }?.side == "income")
        #expect(source.first { $0.name == "Fictional work" }?.side == "income")
        #expect(source.first { $0.name == "Friends" }?.otherSide == true)
        #expect(source.filter(\.excludeFromTotals).allSatisfy { $0.side == nil && $0.otherSide == nil })
        let encoded = try JSONSerialization.jsonObject(with: JSONEncoder().encode(source)) as! [[String: Any]]
        #expect(encoded.first { $0["name"] as? String == "Groceries" }?["otherSide"] == nil)
        let dashboard = try await phone.dashboard(auth: auth)
        for direction in [ReceiptDirection.out, .in] {
            let names = list.offered(for: direction).compactMap { list.name(of: $0) }
            let picks = direction == .in ? dashboard.pick.income : dashboard.pick.spend
            #expect(Set(names) == Set(picks))
            #expect(names.count == Set(names).count && picks.count == Set(picks).count)
            let home = CategorySide(direction: direction)
            let offered = list.offered(for: direction, includingTransfers: false)
            #expect(offered.allSatisfy { !list.isTransfer($0) })
            let firstOther = offered.firstIndex { list.side(of: $0) != home } ?? offered.endIndex
            #expect(offered[..<firstOther].allSatisfy { list.side(of: $0) == home })
            #expect(offered[firstOther...].allSatisfy { list.hasOtherSide($0) })
            #expect(CashCategories.choices(list, for: direction).map(\.id) == offered.map(Optional.some) + [nil])
        }
        #expect(dashboard.categories.first { $0.name == "Friends" }?.kind == .spend)
        #expect(dashboard.categories.first { $0.name == "Friends" }?.otherSide == true)
        let reading = ReceiptReading(shop: "Fictional shop", categoryId: nil, date: "2026-10-05", time: nil, total: 5,
                                     currency: "EUR", method: .cash, language: "en", from: "text", rows: [],
                                     sure: .init(shop: true, date: true, total: true, method: true))
        let check = ReceiptCheckModel(reading: reading, phone: phone, language: .english)
        await check.load()
        #expect(check.choices.map(\.id) == list.offered(for: .out, includingTransfers: false).map(Optional.some) + [nil])
    }

    private func world() async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "friends", "salary", "selling-things", "savings-investing"])
        try await phone.setOtherSide(false, for: "friends")
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("05.10.2026", "REWE Markt GmbH", "REWE", -2000),
            ("06.10.2026", "REWE Markt GmbH", "REWE", -1500),
            ("01.10.2026", "Fictional employer", "Gehalt", 200000)])], auth: auth)
        let dashboard = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await dashboard.reload()
        return (phone, dashboard)
    }

    private func window(_ dashboard: DashboardStore, income: Bool,
                        mode: RecategorisationMode = .switchCategory) async throws -> TransactionDetailStore {
        let row = try #require(dashboard.dashboard?.transactions.first { ($0.amount > 0) == income })
        let window = dashboard.transactionDetailStore(for: row)
        await window.load()
        window.beginRecategorisation(mode: mode)
        return window
    }

    @Test(arguments: [false, true], [RecategorisationMode.switchCategory, .add])
    func otherSideIsOnlyStoredOnSave(income: Bool, mode: RecategorisationMode) async throws {
        let (phone, dashboard) = try await world()
        let window = try await window(dashboard, income: income, mode: mode)
        let name = income ? "Friends" : "Selling things"
        let id = income ? "friends" : "selling-things"
        let before = try await phone.export()
        #expect(window.otherSideChoices.contains { $0.name == name })
        #expect(!window.choices.contains { $0.name == name })
        window.pickFromOtherSide(name)
        #expect(window.choices.last?.name == name)
        #expect(!window.otherSideChoices.contains { $0.name == name })
        if mode == .switchCategory { #expect(window.target == name) }
        else { #expect(window.extras.contains(name)) }
        #expect(try await phone.export() == before, "selection alone stores nothing")
        // Cancel and reopen resets both the pick and the temporary choice.
        window.showsRecategorisation = false
        window.beginRecategorisation(mode: mode)
        #expect(!window.choices.contains { $0.name == name })
        #expect(window.otherSideChoices.contains { $0.name == name })
        #expect(try await phone.export() == before)
        window.pickFromOtherSide(name)
        await window.save()
        if window.removeCurrentQuestion != nil { await window.answerRemoveCurrent(remove: false) }
        #expect(window.saveError == nil)
        #expect(try await phone.categories().hasOtherSide(id))
        let saved = try #require(try await phone.ledger.payment(window.paymentID))
        if mode == .switchCategory {
            #expect(saved.category == id)
            if !income { #expect(window.followUp?.count == 1) }
        } else { #expect(saved.extraCategories.contains(id)) }
        #expect(dashboard.dashboard?.recategorisationChoices(amount: income ? 1 : -1).contains { $0.name == name } == true)
    }

    @Test func anUnpickedOtherSideCategoryIsNotStored() async throws {
        let (phone, dashboard) = try await world()
        let window = try await window(dashboard, income: false, mode: .add)
        window.pickFromOtherSide("Selling things")
        window.select("Selling things")
        await window.save()
        if window.removeCurrentQuestion != nil { await window.answerRemoveCurrent(remove: false) }
        #expect(window.saveError == nil)
        #expect(try await !phone.categories().hasOtherSide("selling-things"))
    }

    @Test func stopOfferingPersistsAndProtectsHomeTransfersAndCurrentCategory() async throws {
        let (phone, dashboard) = try await world()
        try await phone.setOtherSide(true, for: "selling-things")
        try await phone.setOtherSide(true, for: "groceries")
        await dashboard.reloadIfCategoriesChanged()
        let window = try await window(dashboard, income: false)
        #expect(window.choices.contains { $0.name == "Selling things" })
        await window.stopOffering("Selling things")
        #expect(!window.choices.contains { $0.name == "Selling things" })
        #expect(window.otherSideChoices.contains { $0.name == "Selling things" })
        #expect(try await !phone.categories().hasOtherSide("selling-things"))
        await window.stopOffering("Groceries")
        #expect(try await phone.categories().hasOtherSide("groceries"), "a home/current category is protected")
        // The current category is protected even when it is here through otherSide alone.
        try await phone.setOtherSide(true, for: "selling-things")
        _ = try await phone.switchCategory(id: window.paymentID, to: "Selling things", auth: auth)
        await dashboard.reloadAfterTransactionChange()
        let row = try #require(dashboard.dashboard?.transactions.first { $0.id == window.paymentID })
        let again = dashboard.transactionDetailStore(for: row)
        await again.load()
        again.beginRecategorisation()
        await again.stopOffering("Selling things")
        #expect(try await phone.categories().hasOtherSide("selling-things"))
        await #expect(throws: LedgerError.self) { try await phone.setOtherSide(true, for: "savings-investing") }
        await #expect(throws: LedgerError.self) { try await phone.setSide(.income, of: "friends") }
    }

    @Test(arguments: [CategorySide.spend, .income])
    func changingHomeKeepsTheOldDirectionOnlyWhenItHasPayments(side: CategorySide) async throws {
        let phone = try await PhoneTest.backend()
        let used = try await phone.addCustom(named: "Fictional used", side: side)
        let empty = try await phone.addCustom(named: "Fictional empty", side: side)
        let tagOnly = try await phone.addCustom(named: "Fictional tag", side: side)
        try await phone.ledger.addReceipt(CashEntryDraft(direction: side.direction, amount: 10, date: "2026-10-05",
                                                        what: "Fictional cash", category: used).receipt(id: "cash"))
        let other: CategorySide = side == .spend ? .income : .spend
        for id in [used, empty, tagOnly] { try await phone.setSide(other, of: id) }
        let list = try await phone.categories()
        #expect(list.side(of: used) == other && list.hasOtherSide(used))
        #expect(list.side(of: empty) == other && !list.hasOtherSide(empty))
        #expect(!list.hasOtherSide(tagOnly))
        try await phone.setOtherSide(false, for: used)
        #expect(try await !phone.categories().hasOtherSide(used))
    }

    @Test(arguments: [CategorySide.spend, .income])
    func bankPaymentsKeepTheirOldDirectionButExtraCategoriesDoNot(side: CategorySide) async throws {
        let (phone, _) = try await world()
        let used = try await phone.addCustom(named: "Fictional primary", side: side)
        let tag = try await phone.addCustom(named: "Fictional extra", side: side)
        let payment = try #require(try await phone.ledger.payments().first { ($0.amountValue > 0) == (side == .income) })
        try await phone.ledger.setCategory(payment.id, category: used, extras: [tag], source: .manual)
        let other: CategorySide = side == .spend ? .income : .spend
        try await phone.setSide(other, of: used)
        try await phone.setSide(other, of: tag)
        #expect(try await phone.categories().hasOtherSide(used))
        #expect(try await !phone.categories().hasOtherSide(tag))
    }

    @Test(arguments: [false, true])
    func addCreatesACategoryOnThePaymentsSide(income: Bool) async throws {
        let (phone, dashboard) = try await world()
        let window = try await window(dashboard, income: income, mode: .add)
        window.newCategory.name = "Fictional addition"
        await window.createCategory()
        let made = try #require(try await phone.ledger.chosen().first { $0.name == "Fictional addition" })
        #expect(made.side == (income ? "income" : "spend"))
        #expect(window.extras == ["Fictional addition"])
        await window.save()
        if window.removeCurrentQuestion != nil { await window.answerRemoveCurrent(remove: false) }
        #expect(window.saveError == nil)
        #expect(try await phone.ledger.payment(window.paymentID)?.extraCategories == [made.id])
    }

    @Test func exportFiveRoundTripsAndFourGetsLegacySidesAfterPayments() async throws {
        let (phone, _) = try await world()
        let own = try await phone.addCustom(named: "Fictional work", side: .income)
        try await phone.setOtherSide(true, for: own)
        let file = try await phone.export()
        #expect(file.schema == 7)
        let restored = try await PhoneTest.backend()
        try await restored.restore(file.encoded())
        #expect(try await restored.ledger.chosen() == file.categories)
        var old = file
        old.schema = 4
        old.categories = old.categories.map { ChosenCategory(id: $0.id, name: $0.name, order: $0.order, look: $0.look) }
        // A custom category's old net is income; a default spending category's net is income too.
        old.payments += [Self.payment("own-in", amount: "50", category: own), Self.payment("friends-in", amount: "20", category: "friends")]
        let account = old.payments[0].account
        old.payments = old.payments.map { payment in
            LedgerPayment(id: payment.id, account: account, source: payment.source, externalId: payment.externalId,
                          bookingDate: payment.bookingDate, amount: payment.amount, currency: payment.currency,
                          text: payment.text, category: payment.category, categorySource: payment.categorySource,
                          extraCategories: payment.extraCategories, sequence: payment.sequence)
        }
        let legacy = try await PhoneTest.backend()
        try await legacy.restore(old.encoded())
        let list = try await legacy.categories()
        #expect(list.side(of: own) == .income && !list.hasOtherSide(own))
        #expect(list.side(of: "friends") == .spend && list.hasOtherSide("friends"))
        #expect(list.side(of: "selling-things") == .income && !list.hasOtherSide("selling-things"))
        var invalid = file
        invalid.categories[invalid.categories.count - 1].side = "transfer"
        #expect(throws: LedgerError.self) { try invalid.validate(catalog: #require(phone.catalog)) }
    }
}
