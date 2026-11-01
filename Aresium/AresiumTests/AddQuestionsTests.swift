import Foundation
import Testing
@testable import Aresium

@MainActor
@Suite(.serialized)
struct AddQuestionsTests {
    private let auth = BackendAuth(token: nil)

    private func payment(_ id: String, shop: String = "Vinted UAB", category: String? = "groceries",
                         extras: [String] = [], source: CategorySource = .starter) -> LedgerPayment {
        LedgerPayment(id: id, account: "fictional-add", source: "bank", externalId: "fictional-" + id,
                      bookingDate: "2026-10-03", amount: "-10.00", currency: "EUR", text: "Fictional purchase",
                      counterparty: shop, category: category, categorySource: category == nil ? .none : source,
                      extraCategories: extras, sequence: Int(id.filter(\.isNumber)) ?? 0)
    }

    private func receipt(_ id: String, entry: Bool = false) -> LedgerReceipt {
        LedgerReceipt(id: id, date: "2026-10-03", time: nil, shop: "Vinted UAB", total: "4.00", currency: "EUR",
                      euroAmount: nil, method: entry ? .cash : .card, category: "groceries", categorySource: .manual,
                      rows: [], from: "text", paymentID: nil, created: Date(timeIntervalSince1970: 1),
                      direction: .out, kind: entry ? .manual : .receipt)
    }

    private func setup(_ payments: [LedgerPayment], receipts: [LedgerReceipt] = []) async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend()
        let chosen = ["groceries", "clothes", "gifts", "hobbies", "household"].enumerated().map {
            ChosenCategory(id: $0.element, order: $0.offset)
        }
        try await phone.ledger.restore(LedgerExport(exported: "2026-10-30",
            accounts: [LedgerAccount(id: "fictional-add", name: "Fictional bank")], payments: payments,
            categories: chosen, learned: [], layouts: [], receipts: receipts), catalog: #require(phone.catalog))
        try await phone.refresh()
        let dashboard = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await dashboard.reload()
        #expect(dashboard.error == nil)
        return (phone, dashboard)
    }

    private func window(_ dashboard: DashboardStore, id: String = "p1") async throws -> TransactionDetailStore {
        let row = try #require(dashboard.dashboard?.transactions.first { $0.id == id })
        let store = dashboard.transactionDetailStore(for: row)
        await store.load()
        store.beginRecategorisation(mode: .add)
        return store
    }

    private func snapshot(_ phone: PhoneBackend) async throws -> LedgerExport {
        try await phone.ledger.export(on: Date(timeIntervalSince1970: 0))
    }

    @Test func saveAsksRemovalBeforeChangingAnythingAndKeepBothAsksAboutExtras() async throws {
        let (phone, dashboard) = try await setup([payment("p1"), payment("p2")])
        let store = try await window(dashboard)
        #expect(!store.choices.contains { $0.name == "Own transfers" })
        store.select("Clothes")
        let before = try await snapshot(phone)
        await store.save()
        let question = try #require(store.removeCurrentQuestion)
        #expect(question.category == "Groceries" && question.categories == ["Clothes"])
        #expect(store.followUp == nil && store.showsRecategorisation && !store.isSaving)
        #expect(try await snapshot(phone) == before)
        await store.answerRemoveCurrent(remove: false)
        #expect(store.removeCurrentQuestion == nil && store.saveError == nil)
        let saved = try #require(try await phone.ledger.payment("p1"))
        #expect(saved.category == "groceries" && saved.categorySource == .starter && saved.extraCategories == ["clothes"])
        let followUp = try #require(store.followUp)
        #expect(followUp.added == ["Clothes"] && followUp.removed.isEmpty && followUp.count == 1)
        #expect(followUp.wording.allTitle() == "All 2")
        await store.answerFollowUp(moveOthers: false)
        #expect(!store.showsRecategorisation && store.followUp == nil)
        #expect(try await phone.ledger.payment("p2") == before.payments.first { $0.id == "p2" })
        #expect(try await phone.ledger.learned().isEmpty)
    }

    @Test(arguments: [false, true])
    func removeAndUnsortedUseSwitchLearningQuestionAndAnswer(unsorted: Bool) async throws {
        let (phone, dashboard) = try await setup([payment("p1", category: unsorted ? nil : "groceries"), payment("p2")])
        let store = try await window(dashboard)
        store.select("Clothes")
        store.select("Gifts")
        await store.save()
        if unsorted { #expect(store.removeCurrentQuestion == nil) }
        else {
            #expect(store.removeCurrentQuestion != nil)
            await store.answerRemoveCurrent(remove: true)
        }
        #expect(store.saveError == nil)
        let saved = try #require(try await phone.ledger.payment("p1"))
        #expect(saved.category == "clothes" && saved.categorySource == .manual && saved.extraCategories == ["gifts"])
        let rules = try await phone.ledger.learned()
        #expect(rules.values.contains("clothes"))
        let followUp = try #require(store.followUp)
        #expect(followUp.added.isEmpty && followUp.removed.isEmpty && followUp.count == 1)
        #expect(followUp.wording.question() == "Also the other payments from Vinted UAB?")
        await store.answerFollowUp(moveOthers: true)
        let other = try #require(try await phone.ledger.payment("p2"))
        #expect(other.category == "clothes" && other.categorySource == .learned && other.extraCategories.isEmpty)
        #expect(!store.showsRecategorisation)
    }

    @Test func noRemovalQuestionForNothingAddedOrOnlyTheCurrentCategory() async throws {
        let (phone, dashboard) = try await setup([payment("p1", extras: ["clothes"]), payment("p2")])
        let store = try await window(dashboard)
        store.select("Groceries") // The current tile cannot become an extra.
        #expect(store.extras == ["Clothes"] && !store.canRemoveCurrent)
        await store.save()
        #expect(store.removeCurrentQuestion == nil && store.followUp == nil && !store.showsRecategorisation)
        #expect(try await phone.ledger.payment("p2")?.extraCategories.isEmpty == true)
        store.beginRecategorisation(mode: .add)
        store.select("Clothes")
        #expect(store.extras.isEmpty && !store.canRemoveCurrent)
        await store.save()
        #expect(store.removeCurrentQuestion == nil && store.followUp == nil)
    }

    @Test func extrasCountOnlyRowsThatWouldChangeAndAllPreservesEveryPrimaryAndSource() async throws {
        let payments = [payment("p1", shop: "MGP Vinted - Kleiderkreisel"),
                        payment("p2"), payment("p3", category: "clothes"),
                        payment("p4", extras: ["clothes"]),
                        payment("p5", category: CategoryCatalog.ownTransfers, source: .learned),
                        payment("p6", source: .structural), payment("p7", source: .manual),
                        payment("p8", source: .receipt), payment("p9", shop: "dm Drogeriemarkt")]
        let (phone, dashboard) = try await setup(payments, receipts: [receipt("r1"), receipt("e1", entry: true)])
        let store = try await window(dashboard)
        store.select("Clothes")
        await store.save()
        await store.answerRemoveCurrent(remove: false)
        let question = try #require(store.followUp)
        #expect(question.count == 3) // p2, p7 and p8, including the shop's bank-name aliases.
        let beforeAll = try await snapshot(phone)
        let revision = dashboard.revision
        await store.answerFollowUp(moveOthers: true)
        #expect(dashboard.revision == revision + 1)
        let after = try await snapshot(phone)
        for old in beforeAll.payments {
            let saved = try #require(after.payments.first { $0.id == old.id })
            #expect(saved.category == old.category && saved.categorySource == old.categorySource)
            if ["p2", "p7", "p8"].contains(old.id) { #expect(saved.extraCategories == ["clothes"]) }
            else { #expect(saved == old) }
        }
        #expect(after.learned.isEmpty)
        // A later import from the shop does not inherit the occasion's extra.
        _ = try await phone.importFiles([PhoneTest.vrBank([("04.10.2026", "Vinted UAB", "Fictional purchase", -1500)])], auth: auth)
        #expect(try await phone.ledger.payments().last?.extraCategories.isEmpty == true)
    }

    @Test(arguments: [false, true])
    func removeAnExtraOrAddAndRemoveTogetherAsksOnce(both: Bool) async throws {
        let (phone, dashboard) = try await setup([
            payment("p1", extras: ["clothes"]), payment("p2", extras: ["clothes"]),
            payment("p3", category: "clothes"), payment("p4", extras: both ? ["gifts"] : [])])
        let store = try await window(dashboard)
        store.select("Clothes")
        if both { store.select("Gifts") }
        await store.save()
        if both { await store.answerRemoveCurrent(remove: false) }
        else { #expect(store.removeCurrentQuestion == nil) }
        let question = try #require(store.followUp)
        #expect(question.removed == ["Clothes"] && question.added == (both ? ["Gifts"] : []))
        #expect(question.count == (both ? 2 : 1)) // p3's primary Clothes is never removed.
        await store.answerFollowUp(moveOthers: true)
        let other = try #require(try await phone.ledger.payment("p2"))
        #expect(other.category == "groceries" && other.extraCategories == (both ? ["gifts"] : []))
        let primary = try #require(try await phone.ledger.payment("p3"))
        #expect(primary.category == "clothes" && primary.extraCategories == (both ? ["gifts"] : []))
        #expect(try await phone.ledger.learned().isEmpty)
    }

    @Test func noShopQuestionWhenNoOtherRowWouldChange() async throws {
        let (_, dashboard) = try await setup([payment("p1"), payment("p2", extras: ["clothes"])])
        let store = try await window(dashboard)
        store.select("Clothes")
        await store.save()
        await store.answerRemoveCurrent(remove: false)
        #expect(store.followUp == nil && !store.showsRecategorisation)
    }

    @Test func selectionKeepBothOneQuestionForAllShopsAndUndoIncludesAppliedAnswer() async throws {
        let (phone, dashboard) = try await setup([payment("p1"), payment("p2", shop: "dm Drogeriemarkt"),
                                                payment("p3"), payment("p4", shop: "dm-drogerie markt")])
        let before = try await snapshot(phone), revision = dashboard.revision
        let request = try dashboard.prepareAddCategories(ids: ["p1", "p2"], names: ["Clothes"], currentCategory: "Groceries")
        #expect(request.question?.selection == true && request.question?.category == "Groceries")
        #expect(try await snapshot(phone) == before)
        let result = try await request.save()
        let question = try #require(result.followUp)
        #expect(result.changed.bankPayments == 2 && dashboard.revision == revision + 1)
        #expect(question.count == 2 && question.shopCount == 2 && question.shop == nil)
        #expect(question.question == "Also add Clothes to the other 2 payments from these 2 shops?")
        #expect(question.wording.allTitle() == "All 4")
        _ = try await question.apply()
        #expect(dashboard.revision == revision + 2)
        #expect(try await phone.ledger.payments().allSatisfy { $0.category == "groceries" && $0.extraCategories == ["clothes"] })
        #expect(try await phone.ledger.learned().isEmpty)
        #expect(try await result.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
        #expect(dashboard.revision == revision + 3)
    }

    @Test func selectionRemoveSwitchesOnlyCurrentRowsOthersAddAndOneUndoRestoresBoth() async throws {
        let (phone, dashboard) = try await setup([payment("p1"), payment("p2", category: "hobbies", extras: ["groceries"]),
                                                payment("p3"), payment("p4", source: .manual)])
        let before = try await snapshot(phone)
        let request = try dashboard.prepareAddCategories(ids: ["p1", "p2"], names: ["Clothes", "Gifts"], currentCategory: "Groceries")
        #expect(request.question != nil)
        let result = try await request.save(removeCurrent: true)
        #expect(try await phone.ledger.payment("p1")?.category == "clothes")
        #expect(try await phone.ledger.payment("p1")?.extraCategories == ["gifts"])
        #expect(try await phone.ledger.payment("p2")?.category == "hobbies")
        #expect(try await phone.ledger.payment("p2")?.extraCategories == ["groceries", "clothes", "gifts"])
        let question = try #require(result.followUp)
        #expect(question.count == 1 && question.added.isEmpty) // Switch rules leave the manually set p4 alone.
        _ = try await question.apply()
        #expect(try await phone.ledger.payment("p3")?.category == "clothes")
        #expect(try await phone.ledger.payment("p3")?.extraCategories.isEmpty == true)
        #expect(try await phone.ledger.learned().values.contains("clothes"))
        #expect(try await result.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
    }

    @Test func selectionUnsortedAndNoNewCategoryDoNotAskRemoval() async throws {
        let (phone, dashboard) = try await setup([payment("p1", category: nil), payment("p2", category: nil), payment("p3")])
        let before = try await snapshot(phone)
        let request = try dashboard.prepareAddCategories(ids: ["p1", "p2"], names: ["Clothes"], currentCategory: CategoryName.uncategorised)
        #expect(request.question == nil)
        let result = try await request.save()
        #expect(try await phone.ledger.payment("p1")?.category == "clothes")
        #expect(try await phone.ledger.payment("p2")?.category == "clothes")
        #expect(result.followUp?.added.isEmpty == true)
        #expect(try await result.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
        let currentOnly = try dashboard.prepareAddCategories(ids: ["p3"], names: ["Groceries"], currentCategory: "Groceries")
        #expect(currentOnly.question == nil)
        let empty = try dashboard.prepareAddCategories(ids: ["p3"], names: [], currentCategory: "Groceries")
        #expect(empty.question == nil)
    }

    @Test(arguments: [false, true])
    func selectionRemovesExtrasWithOptionalAddAndUndoRestoresEveryRow(add: Bool) async throws {
        let (phone, dashboard) = try await setup([
            payment("p1", extras: ["clothes"]), payment("p2", shop: "dm Drogeriemarkt", extras: ["clothes"]),
            payment("p3", extras: ["clothes"]), payment("p4", shop: "dm-drogerie markt", extras: ["clothes"])])
        let before = try await snapshot(phone)
        let request = try dashboard.prepareAddCategories(ids: ["p1", "p2"], names: add ? ["Gifts"] : [],
                                                        currentCategory: "Groceries", removing: ["Clothes"])
        #expect((request.question != nil) == add)
        let result = try await request.save()
        let question = try #require(result.followUp)
        #expect(question.count == 2 && question.shopCount == 2)
        #expect(question.added == (add ? ["Gifts"] : []) && question.removed == ["Clothes"])
        _ = try await question.apply()
        #expect(try await phone.ledger.payments().allSatisfy {
            $0.category == "groceries" && $0.extraCategories == (add ? ["gifts"] : [])
        })
        #expect(try await phone.ledger.learned().isEmpty)
        #expect(try await result.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
    }

    @Test func staleExtrasFollowUpRefusesAllWritesAndUndo() async throws {
        let (phone, dashboard) = try await setup([payment("p1"), payment("p2")])
        let result = try await dashboard.addCategory(ids: ["p1"], name: "Clothes")
        let question = try #require(result.followUp)
        try await phone.ledger.setCategory("p2", category: "hobbies", source: .manual)
        let before = try await snapshot(phone)
        await #expect(throws: BatchChangeError.changed) { _ = try await question.apply() }
        #expect(try await snapshot(phone) == before)
        #expect(try await result.undo.perform() == .unavailable)
    }

    @Test func questionWordsInBothLanguagesAndFoundationLists() {
        let en = RemoveCurrentQuestion(category: "Groceries", categories: ["Clothes", "Gifts"])
        let de = RemoveCurrentQuestion(category: "Lebensmittel", categories: ["Kleidung", "Geschenke"])
        #expect(en.title(language: .english) == "Also remove from Groceries?")
        #expect(en.message(language: .english) == "Then it counts only under Clothes and Gifts.")
        #expect(de.title(language: .german) == "Auch aus Lebensmittel entfernen?")
        #expect(de.message(language: .german) == "Dann zählt sie nur unter Kleidung und Geschenke.")
        #expect(en.removeTitle(language: .english) == "Remove" && de.removeTitle(language: .german) == "Entfernen")
        #expect(en.keepTitle(language: .english) == "Keep both" && de.keepTitle(language: .german) == "Beide behalten")
        let selection = RemoveCurrentQuestion(category: "Groceries", categories: ["Clothes"], selection: true)
        #expect(selection.title(language: .english) == "Also remove them from Groceries?")
        #expect(selection.message(language: .english) == "Then they count only under Clothes.")
        let deSelection = RemoveCurrentQuestion(category: "Lebensmittel", categories: ["Kleidung"], selection: true)
        #expect(deSelection.title(language: .german) == "Auch aus Lebensmittel entfernen?")
        #expect(deSelection.message(language: .german) == "Dann zählen sie nur unter Kleidung.")
        let singular = CategoryQuestionWording(count: 1, selectedCount: 1, shopCount: 1, shop: "Vinted", category: "",
                                               added: ["Gifts"], removed: ["Clothes"])
        #expect(singular.question(language: .english) == "Also add Gifts and remove Clothes for the other 1 payment from Vinted?")
        let singularDE = CategoryQuestionWording(count: 1, selectedCount: 1, shopCount: 1, shop: "Vinted", category: "",
                                                 added: ["Geschenke"], removed: ["Kleidung"])
        #expect(singularDE.question(language: .german) == "Bei der anderen 1 Buchung von Vinted auch Geschenke hinzufügen und Kleidung entfernen?")
        for language in [AppLanguage.english, .german] {
            let clothes = language == .english ? "Clothes" : "Kleidung"
            let gifts = language == .english ? "Gifts" : "Geschenke"
            var wording = CategoryQuestionWording(count: 23, selectedCount: 1, shopCount: 1, shop: "Vinted", category: "", added: [clothes])
            #expect(wording.question(language: language) == (language == .english
                ? "Also add Clothes to the other 23 payments from Vinted?"
                : "Kleidung auch zu den anderen 23 Buchungen von Vinted hinzufügen?"))
            #expect(wording.allTitle(language: language) == (language == .english ? "All 24" : "Alle 24"))
            #expect(wording.onlyTitle(language: language) == (language == .english ? "Only this one" : "Nur diese"))
            #expect(wording.message(language: language) == nil)
            wording.added = []; wording.removed = [clothes]
            #expect(wording.question(language: language) == (language == .english
                ? "Also remove Clothes from the other 23 payments from Vinted?"
                : "Kleidung auch bei den anderen 23 Buchungen von Vinted entfernen?"))
            wording.added = [gifts]
            #expect(wording.question(language: language) == (language == .english
                ? "Also add Gifts and remove Clothes for the other 23 payments from Vinted?"
                : "Bei den anderen 23 Buchungen von Vinted auch Geschenke hinzufügen und Kleidung entfernen?"))
            let shops = CategoryQuestionWording(count: 23, selectedCount: 4, shopCount: 6, shop: nil, category: "", added: [clothes], selection: true)
            #expect(shops.question(language: language) == (language == .english
                ? "Also add Clothes to the other 23 payments from these 6 shops?"
                : "Kleidung auch zu den anderen 23 Buchungen von diesen 6 Geschäften hinzufügen?"))
        }
    }
}
