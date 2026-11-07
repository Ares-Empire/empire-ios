import Foundation
import Testing
@testable import Aresium

/// The quick sort (brief 99): what is Not sorted grouped by name and direction over every month, biggest first; a card
/// sorted with one tap (brief 81's switch: by hand, the name learned, the next import of it sorted by that), Skip and
/// Undo, brief 81's question applied only for the name's own Not sorted payments, the offer after an import, the card
/// on Not sorted's list and the words in both languages. Made-up payments only.
@MainActor
@Suite(.serialized)
struct QuickSortTests {
    private let auth = BackendAuth(token: nil)

    private func payment(_ id: String, _ who: String, amount: String = "-10.00", day: String = "2026-10-02",
                         text: String = "Fictional purchase", category: String? = nil,
                         source: CategorySource = .none, own: String? = nil) -> LedgerPayment {
        LedgerPayment(id: id, account: "fictional-quick", source: "bank", externalId: "fictional-" + id,
                      bookingDate: day, amount: amount, currency: "EUR", text: text, counterparty: who,
                      category: category, categorySource: source, extraCategories: [],
                      sequence: Int(id.filter(\.isNumber)) ?? 0, ownName: own)
    }

    private func cashReceipt(_ id: String, _ shop: String) -> LedgerReceipt {
        LedgerReceipt(id: id, date: "2026-10-03", time: nil, shop: shop, total: "4.00", currency: "EUR", euroAmount: nil,
                      method: .cash, category: nil, categorySource: .none, rows: [], from: "text", paymentID: nil,
                      created: Date(timeIntervalSince1970: 1), direction: .out, kind: .receipt)
    }

    private static let chosen = ["groceries", "household", "cash", "salary", "parents-family"]

    /// A store restored from these made-up payments (nothing sorted again), and its dashboard.
    private func setup(_ payments: [LedgerPayment], receipts: [LedgerReceipt] = []) async throws
        -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend()
        let chosen = Self.chosen.enumerated().map { ChosenCategory(id: $0.element, order: $0.offset) }
        try await phone.ledger.restore(LedgerExport(exported: "2026-10-30",
            accounts: [LedgerAccount(id: "fictional-quick", name: "Fictional quick bank")], payments: payments,
            categories: chosen, learned: [], layouts: [], receipts: receipts, nameRules: []),
            catalog: #require(phone.catalog))
        try await phone.refresh()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    /// A store filled through the real import from a made-up VR Bank file, with these categories chosen.
    private func imported(_ rows: [(String, String, String, Int)]) async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneTest.backend(chosen: Self.chosen)
        _ = try await phone.importFiles([PhoneTest.vrBank(rows)], auth: auth)
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    private func name(_ id: String, _ phone: PhoneBackend) async throws -> String {
        try #require(try await phone.categories().name(of: id))
    }

    // MARK: the groups

    @Test func groupsByNameAndDirectionOverEveryMonthBiggestFirst() async throws {
        let (_, store) = try await setup([
            payment("g1", "Fictional Grocer", day: "2026-08-03", text: "Fictional purchase 1"),
            payment("g2", "Fictional Grocer", day: "2026-09-03", text: "fictional  purchase 1"),   // the same text
            payment("g3", "Fictional Grocer", day: "2026-10-03", text: "Fictional Grocer"),        // only the name
            payment("g4", "Fictional Grocer", day: "2026-10-09", text: "Fictional purchase 2"),
            payment("g5", "Fictional Grocer", category: "groceries", source: .starter),            // sorted: not in it
            payment("e1", "Erika Beispiel", amount: "150.00", day: "2026-08-02", text: "Taschengeld August"),
            payment("e2", "Erika Beispiel", amount: "150.00", day: "2026-09-02", text: "Taschengeld September"),
            payment("e3", "Erika Beispiel", amount: "150.00", day: "2026-10-02", text: "Taschengeld Oktober"),
            payment("e4", "Erika Beispiel", amount: "-24.00", day: "2026-10-19", text: "Kinokarten"),
            payment("k1", "Fiktiv Kiosk", amount: "-20.00", day: "2026-09-05"),
            payment("k2", "Fiktiv Kiosk", amount: "-20.00", day: "2026-09-06"),
            payment("k3", "Fiktiv Kiosk", amount: "-20.00", day: "2026-10-05"),
            payment("o1", "Fiktiva Muster", day: "2026-10-11", own: "Grandma"),
            payment("o2", "F. Muster Fiktiva", day: "2026-09-11", own: "grandma"),
            payment("w1", "Geldautomat Fiktivbank", amount: "-100.00", category: "cash", source: .starter),
        ], receipts: [cashReceipt("r1", "Fictional Bakery Cash")])
        let dashboard = try #require(store.dashboard)
        let groups = store.quickSortGroups
        #expect(groups == QuickSort.groups(in: dashboard), "built with the dashboard, off the main thread")
        #expect(groups.map(\.name) == ["Fictional Grocer", "Erika Beispiel", "Fiktiv Kiosk", "Grandma",
                                       "Erika Beispiel", "Fictional Bakery Cash"])
        #expect(groups.map(\.count) == [4, 3, 3, 2, 1, 1], "more payments first, then more money")

        // Every month; the sorted payment of the same shop left out; the texts once each, newest first, never the name.
        let grocer = groups[0]
        #expect(grocer.ids == ["g1", "g2", "g3", "g4"] && grocer.side == .spend && grocer.cents == 4000)
        #expect(grocer.first == "2026-08-03" && grocer.last == "2026-10-09")
        #expect(grocer.examples == ["Fictional purchase 2", "fictional purchase 1"])
        // A person paying in and paid by you: two cards.
        let erikaIn = groups[1], erikaOut = groups[4]
        #expect(erikaIn.nameKey == erikaOut.nameKey && erikaIn.id != erikaOut.id)
        #expect(erikaIn.side == .income && erikaIn.signedTotal == 450 && erikaIn.ids == ["e1", "e2", "e3"])
        #expect(erikaIn.examples == ["Taschengeld Oktober", "Taschengeld September", "Taschengeld August"])
        #expect(erikaOut.side == .spend && erikaOut.signedTotal == -24 && erikaOut.ids == ["e4"])
        // An own name groups as the name groups do: two bank lines, one name.
        #expect(groups[3].ids == ["o1", "o2"])
        // Covered rows are no payments of their own: never in a card.
        let covered = Set(dashboard.transactions.filter { $0.coveredBy != nil }.map(\.id))
        try #require(!covered.isEmpty, "the cash receipt covers the withdrawal")
        #expect(groups.allSatisfy { $0.ids.isDisjoint(with: covered) })
        // Every Not sorted payment is in exactly one card.
        let notSorted = dashboard.transactions.filter { $0.categoryName == CategoryName.uncategorised && $0.coveredBy == nil }
        #expect(groups.reduce(0) { $0 + $1.count } == notSorted.count)
        #expect(Set(groups.flatMap(\.ids)) == Set(notSorted.map(\.id)))

        let tally = store.quickSortTally
        #expect(tally.names == 6 && tally.payments == 14 && tally.hasRepeats)
    }

    @Test func serverModeHasNoGroups() async throws {
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), sample: true)
        await store.reload()
        #expect(store.dashboard != nil && store.quickSortGroups.isEmpty)
        let route = DashboardRoute(category: CategoryName.uncategorised, side: .expenses, month: "2026-10")
        #expect(!store.offersQuickSort(on: route))
    }

    // MARK: sorting a card

    @Test func aTapSortsTheCardByHandLearnsTheNameAndTheNextImportFollows() async throws {
        let (phone, store) = try await imported([
            ("02.08.2026", "Erika Beispiel", "Taschengeld August", 15000),
            ("02.09.2026", "Erika Beispiel", "Taschengeld September", 15000),
            ("02.10.2026", "Erika Beispiel", "Taschengeld Oktober", 15000),
            ("05.10.2026", "Fiktiv Kiosk", "Einkauf", -500),
            ("06.10.2026", "Fiktiv Kiosk", "Einkauf", -700),
        ])
        let family = try await name("parents-family", phone)
        let flow = QuickSortFlow(store: store)
        #expect(flow.groups.map(\.name) == ["Erika Beispiel", "Fiktiv Kiosk"])
        #expect(flow.progress == "1 of 2")
        let card = try #require(flow.card)
        #expect(card.group.side == .income && card.ids.count == 3)
        #expect(card.choices.contains { $0.name == family }, "the income side's categories, as the change window offers")
        #expect(!card.choices.contains { $0.name == CategoryName.uncategorised })
        #expect(card.offersNewCategory)

        await card.sort(family)
        #expect(card.saveError == nil)
        let erika = try await phone.ledger.payments().filter { $0.counterparty == "Erika Beispiel" }
        #expect(erika.count == 3 && erika.allSatisfy { $0.category == "parents-family" && $0.categorySource == .manual })
        let keys = try await phone.engine.merchantKeys(erika.map { $0.sorting(raw: false) })
        let learned = try await phone.ledger.learned()
        #expect(!keys.isEmpty && keys.allSatisfy { !$0.isEmpty && learned[$0] == "parents-family" }, "the name learned")
        #expect(flow.position == 1 && flow.sortedPayments == 3 && flow.lastSorted == 0 && flow.canUndo)
        #expect(flow.card?.group.name == "Fiktiv Kiosk" && flow.progress == "2 of 2 · 3 sorted")
        #expect(store.quickSortGroups.map(\.name) == ["Fiktiv Kiosk"], "the dashboard built again, its groups with it")

        // The next import of that name is sorted by what was learned.
        _ = try await phone.importFiles([PhoneTest.vrBank([("20.10.2026", "Erika Beispiel", "Taschengeld extra", 5000)],
                                                          name: "later.csv")], auth: auth)
        let newcomer = try #require(try await phone.ledger.payments().first { $0.text == "Taschengeld extra" })
        #expect(newcomer.category == "parents-family" && newcomer.categorySource == .learned)
    }

    @Test func skipLeavesACardAndUndoBringsTheLastSortedOneBack() async throws {
        let (phone, store) = try await imported([
            ("02.09.2026", "Erika Beispiel", "Taschengeld September", 15000),
            ("02.10.2026", "Erika Beispiel", "Taschengeld Oktober", 15000),
            ("05.10.2026", "Fiktiv Kiosk", "Einkauf", -500),
        ])
        let before = try await phone.ledger.export(on: Date(timeIntervalSince1970: 0))
        let family = try await name("parents-family", phone)
        let flow = QuickSortFlow(store: store)
        #expect(!flow.canUndo)
        await flow.card?.sort(family)
        flow.skip()
        #expect(flow.isFinished && flow.card == nil && flow.sortedPayments == 2 && flow.skipped == 1)
        #expect(flow.summaryTitle == "2 payments sorted" && flow.summaryLine == "From 1 name · 1 skipped")
        #expect(flow.canUndo, "the last card sorted can still be put back at the end")

        await flow.undo()
        #expect(flow.problem == nil && flow.position == 0 && flow.cameBack)
        #expect(flow.card?.group.name == "Erika Beispiel" && flow.card?.ids.count == 2, "it shows again, Not sorted")
        #expect(flow.sortedPayments == 0 && flow.skipped == 0, "the cards after it come again")
        #expect(!flow.canUndo, "one undo, for the last card sorted")
        #expect(try await phone.ledger.export(on: Date(timeIntervalSince1970: 0)) == before, "and the name unlearned")
        #expect(store.quickSortGroups.map(\.name) == ["Erika Beispiel", "Fiktiv Kiosk"])
    }

    @Test func anUndoTheDataNoLongerAllowsSaysSoAndChangesNothing() async throws {
        let (phone, store) = try await imported([
            ("02.09.2026", "Erika Beispiel", "Taschengeld September", 15000),
            ("02.10.2026", "Erika Beispiel", "Taschengeld Oktober", 15000),
            ("05.10.2026", "Fiktiv Kiosk", "Einkauf", -500),
        ])
        let flow = QuickSortFlow(store: store)
        await flow.card?.sort(try await name("parents-family", phone))
        // Another change saved meanwhile: brief 81's undo refuses.
        let kiosk = try #require(try await phone.ledger.payments().first { $0.counterparty == "Fiktiv Kiosk" })
        try await phone.ledger.setCategory(kiosk.id, category: "household", source: .manual)
        await flow.undo()
        #expect(flow.problem == "Cannot undo because the data changed.")
        #expect(flow.position == 1 && !flow.canUndo && flow.sortedPayments == 2)
        #expect(try await phone.ledger.payments().filter { $0.counterparty == "Erika Beispiel" }
            .allSatisfy { $0.category == "parents-family" })
    }

    /// Brief 81's question about the shop's other payments: never asked, applied by itself only when it moves the name's
    /// own Not sorted payments in this direction (by construction those are in the card; one that came in while the
    /// flow was open is the case). The other direction (its own card) and payments already sorted stay as they are.
    @Test func theShopsQuestionIsTakenOnlyForTheNamesOwnNotSortedPayments() async throws {
        let (phone, store) = try await setup([
            payment("v1", "Fiktiv Versand", amount: "-30.00", day: "2026-09-04"),
            payment("v2", "Fiktiv Versand", amount: "-40.00", day: "2026-10-04"),
            payment("v3", "Fiktiv Versand", amount: "30.00", day: "2026-10-08", text: "Retoure"),
            payment("v4", "Fiktiv Versand", amount: "-15.00", day: "2026-08-04", category: "household", source: .starter),
        ])
        let groceries = try await name("groceries", phone)
        let flow = QuickSortFlow(store: store)
        let card = try #require(flow.card)
        #expect(card.group.ids == ["v1", "v2"] && card.group.side == .spend)
        await card.sort(groceries)
        let after = Dictionary(uniqueKeysWithValues: try await phone.ledger.payments().map { ($0.id, $0) })
        #expect(after["v1"]?.category == "groceries" && after["v2"]?.category == "groceries")
        #expect(after["v3"]?.category == nil, "the refund is a card of its own")
        #expect(after["v4"]?.category == "household" && after["v4"]?.categorySource == .starter, "sorted ones stay")
        #expect(flow.sortedPayments == 2 && flow.card?.group.ids == ["v3"] && flow.card?.group.side == .income)
        #expect(!QuickSort.takesFollowUp(["v3"], of: card.group, in: store.dashboard))
        #expect(!QuickSort.takesFollowUp([], of: card.group, in: store.dashboard))
    }

    @Test func aPaymentOfTheNameThatCameInMeanwhileIsSortedWithIt() async throws {
        let (phone, store) = try await imported([
            ("02.09.2026", "Erika Beispiel", "Taschengeld September", 15000),
            ("02.10.2026", "Erika Beispiel", "Taschengeld Oktober", 15000),
        ])
        let flow = QuickSortFlow(store: store)
        let card = try #require(flow.card)
        // A file shared into Aresium while the flow is open: another of her transfers, Not sorted.
        _ = try await phone.importFiles([PhoneTest.vrBank([("12.10.2026", "Erika Beispiel", "Taschengeld extra", 5000)],
                                                          name: "shared.csv")], auth: auth)
        await store.reloadAfterImport()
        #expect(card.ids.count == 2)
        await card.sort(try await name("parents-family", phone))
        #expect(try await phone.ledger.payments().allSatisfy { $0.category == "parents-family" })
        #expect(flow.sortedPayments == 3 && flow.isFinished)
        #expect(store.quickSortGroups.isEmpty)
        #expect(flow.summaryLine == "From 1 name. Everything is sorted.")
    }

    @Test func aNewCategoryMadeOnTheCardSortsIntoIt() async throws {
        let (phone, store) = try await imported([
            ("02.09.2026", "Erika Beispiel", "Taschengeld September", 15000),
            ("02.10.2026", "Erika Beispiel", "Taschengeld Oktober", 15000),
        ])
        let flow = QuickSortFlow(store: store)
        let card = try #require(flow.card)
        card.beginNewCategory()
        card.newCategory.name = "Fictional Gifts"
        await card.createAndSort()
        let list = try await phone.categories()
        let id = try #require(list.id(named: "Fictional Gifts"))
        #expect(list.side(of: id) == .income, "made for the card's side")
        #expect(try await phone.ledger.payments().allSatisfy { $0.category == id && $0.categorySource == .manual })
        #expect(flow.isFinished && flow.sortedPayments == 2)
    }

    // MARK: the offer after an import

    @Test func theOfferWaitsForEverythingElseAndEndsWithNothingNotSorted() {
        let free = QuickSortOffer.Moment(pending: true, tally: QuickSortTally([]))
        #expect(!QuickSortOffer.shows(free), "nothing Not sorted: nothing to offer")
        #expect(QuickSortOffer.expires(free, dashboardShown: true))
        #expect(!QuickSortOffer.expires(free, dashboardShown: false), "no dashboard yet")
        var picker = free
        picker.picker = true
        #expect(!QuickSortOffer.expires(picker, dashboardShown: true), "the picker may still change it")
    }

    @Test func theOfferComesAfterTheImportsWindowsInTheResultsPlace() async throws {
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let phone = try await PhoneTest.backend()
        let store = DashboardStore(session: session, backend: phone)
        let imports = ImportStore(dashboard: store, background: PhoneActivity(), bannerScheduler: ImportTestTimer().schedule)
        func moment(window: Bool = false, tour: Bool = false, locked: Bool = false) -> QuickSortOffer.Moment {
            QuickSortOffer.Moment(imports: imports, store: store, tour: tour, locked: locked, window: window)
        }
        #expect(!QuickSortOffer.shows(moment()), "nothing imported yet")
        imports.debugImport([ImportThenCategoriesTests.bankFile])
        await imports.importAndWait()
        #expect(imports.offersQuickSort)
        // No category chosen: the picker first, then the result counted again.
        #expect(imports.asksForCategories && !QuickSortOffer.shows(moment()))
        await imports.categoriesClosed()?.value
        #expect(imports.banner != nil && !QuickSortOffer.shows(moment()))
        imports.close()
        // Brief 215 changed this on purpose (the first-run review's finding 1): with no category chosen the quick sort
        // cannot help, so its offer waits until one is. One none of these payments fits keeps the tally as it was.
        #expect(!QuickSortOffer.shows(moment()) && moment().categories)
        try await phone.choose("salary")
        await store.reloadAfterTransactionChange()
        let shown = moment()
        #expect(QuickSortOffer.shows(shown))
        #expect(shown.tally.payments == 4 && shown.tally.names == 3)
        #expect(QuickSortWording.offerTitle(shown.tally) == "4 payments not sorted")
        #expect(QuickSortWording.offerLine(shown.tally) == "From 3 names. One tap sorts all payments of a name.")
        // Never over another window, in the tour or behind the lock; the messages' offer waits for it.
        #expect(!QuickSortOffer.shows(moment(window: true)) && !QuickSortOffer.shows(moment(tour: true))
                && !QuickSortOffer.shows(moment(locked: true)))
        #expect(!ReminderOffer.shows(ReminderOffer.Moment(ready: true, quickSort: true)))
        // Answered (Go through or Later): not again until the next import that adds payments.
        imports.quickSortOfferAnswered()
        #expect(!QuickSortOffer.shows(moment()))
        imports.debugImport([ImportThenCategoriesTests.bankFile])     // all there already: adds nothing
        await imports.importAndWait()
        imports.dismiss()
        #expect(!imports.offersQuickSort && !QuickSortOffer.shows(moment()))
        imports.debugImport([PhoneTest.vrBank([("09.10.2026", "Fiktiv Laden", "Einkauf", -990)], name: "more.csv")])
        await imports.importAndWait()
        imports.categoriesClosed()
        imports.dismiss()
        #expect(imports.offersQuickSort && QuickSortOffer.shows(moment()))
        #expect(moment().tally.payments == 5)
    }

    @Test func anImportThatLeftNothingNotSortedEndsTheOffer() async throws {
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let store = DashboardStore(session: session, backend: phone)
        let imports = ImportStore(dashboard: store, background: PhoneActivity(), bannerScheduler: ImportTestTimer().schedule)
        imports.debugImport([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345)])])
        await imports.importAndWait()
        imports.dismiss()
        let moment = QuickSortOffer.Moment(imports: imports, store: store, tour: false, locked: false, window: false)
        #expect(moment.pending && moment.tally.payments == 0)
        #expect(!QuickSortOffer.shows(moment) && QuickSortOffer.expires(moment, dashboardShown: true))
    }

    // MARK: the card on Not sorted's list

    @Test func theCardShowsOnNotSortedsMonthListWhileANameHasMore() async throws {
        let (_, store) = try await setup([
            payment("k1", "Fiktiv Kiosk", day: "2026-09-05"), payment("k2", "Fiktiv Kiosk", day: "2026-10-05"),
            payment("l1", "Fiktiv Laden", day: "2026-10-06"),
            payment("g1", "Fictional Grocer", category: "groceries", source: .manual),
        ])
        let notSorted = store.route(category: CategoryName.uncategorised, side: .expenses, scope: .month("2026-10"))
        #expect(store.offersQuickSort(on: notSorted))
        #expect(store.offersQuickSort(on: store.route(category: CategoryName.uncategorised, side: .income,
                                                      scope: .month("2026-10"))), "both sides open the same cards")
        #expect(!store.offersQuickSort(on: store.route(category: CategoryName.uncategorised, side: .expenses,
                                                       scope: .overview)), "its months: no list yet")
        #expect(!store.offersQuickSort(on: store.route(category: "Groceries", side: .expenses, scope: .month("2026-10"))))
        #expect(QuickSortWording.cardLine(store.quickSortTally) == "2 names · 3 payments · all months")

        // Only single payments left: a list's own tap is as quick, so no card.
        let (_, singles) = try await setup([payment("k1", "Fiktiv Kiosk"), payment("l1", "Fiktiv Laden")])
        #expect(!singles.offersQuickSort(on: singles.route(category: CategoryName.uncategorised, side: .expenses,
                                                           scope: .month("2026-10"))))
    }

    // MARK: words

    @Test func theWordsInBothLanguages() {
        let big = QuickSortTally(names: 12, payments: 34), one = QuickSortTally(names: 1, payments: 1)
        #expect(QuickSortWording.offerTitle(big) == "34 payments not sorted")
        #expect(QuickSortWording.offerTitle(big, language: .german) == "34 Buchungen nicht sortiert")
        #expect(QuickSortWording.offerTitle(one, language: .german) == "1 Buchung nicht sortiert")
        #expect(QuickSortWording.offerLine(big, language: .german)
                == "Von 12 Namen. Einmal tippen sortiert alle Buchungen eines Namens.")
        #expect(QuickSortWording.offerLine(one) == "From 1 name. One tap sorts all payments of a name.")
        #expect(QuickSortWording.goThrough(language: .german) == "Durchgehen")
        #expect(QuickSortWording.later(language: .german) == "Später")

        #expect(QuickSortWording.cardTitle() == "Sort name by name")
        #expect(QuickSortWording.cardTitle(language: .german) == "Name für Name sortieren")
        #expect(QuickSortWording.cardLine(QuickSortTally(names: 12, payments: 150), language: .german)
                == "12 Namen · 150 Buchungen · alle Monate")
        #expect(QuickSortWording.cardLine(QuickSortTally(names: 1, payments: 2)) == "1 name · 2 payments · all months")

        #expect(QuickSortWording.progress(card: 3, of: 12, sorted: 41) == "3 of 12 · 41 sorted")
        #expect(QuickSortWording.progress(card: 3, of: 12, sorted: 41, language: .german) == "3 von 12 · 41 sortiert")
        #expect(QuickSortWording.progress(card: 1, of: 12, sorted: 0, language: .german) == "1 von 12")
        #expect(QuickSortWording.side(.income) == "Money in" && QuickSortWording.side(.spend) == "Money out")
        #expect(QuickSortWording.side(.income, language: .german) == "Einnahmen")
        #expect(QuickSortWording.side(.spend, language: .german) == "Ausgaben")
        #expect(QuickSortWording.tapLine(18) == "A tap sorts all 18 and Aresium remembers the name.")
        #expect(QuickSortWording.tapLine(1) == "A tap sorts it and Aresium remembers the name.")
        #expect(QuickSortWording.tapLine(18, language: .german) == "Einmal tippen sortiert alle 18, und Aresium merkt sich den Namen.")
        #expect(QuickSortWording.skip(language: .german) == "Überspringen")

        // Foundation's range in each language (thin spaces around the dash in English and across years).
        #expect(QuickSortWording.range(first: "2026-01-04", last: "2026-10-20") == "Jan\u{2009}–\u{2009}Oct 2026")
        #expect(QuickSortWording.range(first: "2026-01-04", last: "2026-10-20", language: .german) == "Jan.–Okt. 2026")
        #expect(QuickSortWording.range(first: "2026-10-04", last: "2026-10-20") == "Oct 2026")
        #expect(QuickSortWording.range(first: "2025-11-04", last: "2026-10-20") == "Nov 2025\u{2009}–\u{2009}Oct 2026")
        #expect(QuickSortWording.range(first: "2025-11-04", last: "2026-10-20", language: .german)
                == "Nov. 2025\u{2009}–\u{2009}Okt. 2026")

        #expect(QuickSortWording.summaryTitle(sorted: 84) == "84 payments sorted")
        #expect(QuickSortWording.summaryTitle(sorted: 84, language: .german) == "84 Buchungen sortiert")
        #expect(QuickSortWording.summaryTitle(sorted: 0) == "Nothing sorted")
        #expect(QuickSortWording.summaryTitle(sorted: 0, language: .german) == "Nichts sortiert")
        #expect(QuickSortWording.summaryLine(names: 9, skipped: 3, left: 20) == "From 9 names · 3 skipped")
        #expect(QuickSortWording.summaryLine(names: 9, skipped: 3, left: 20, language: .german)
                == "Von 9 Namen · 3 übersprungen")
        #expect(QuickSortWording.summaryLine(names: 9, skipped: 0, left: 0, language: .german)
                == "Von 9 Namen. Alles ist sortiert.")
        #expect(QuickSortWording.summaryLine(names: 0, skipped: 2, left: 5) == "2 skipped")
    }

    @Test func voiceOverReadsACardAsOne() async throws {
        let (_, store) = try await imported([
            ("02.09.2026", "Erika Beispiel", "Taschengeld September", 15000),
            ("02.10.2026", "Erika Beispiel", "Taschengeld Oktober", 15000),
        ])
        let card = try #require(QuickSortFlow(store: store).card)
        #expect(QuickSortWording.spoken(card.group, title: card.title)
                == "Erika Beispiel, Money in, 2 payments, +300.00, Sep\u{2009}–\u{2009}Oct 2026, Taschengeld Oktober, Taschengeld September")
    }
}

extension QuickSortTally {
    /// Tests: a tally of these numbers (a card of every name with two payments at most).
    init(names: Int, payments: Int) {
        self.init((0..<names).map { index in
            QuickSortGroup(id: "\(index)", nameKey: "\(index)", side: .spend,
                           newest: Transaction(id: "\(index)", date: "2026-10-01", day: 1, month: "2026-10", amount: -1,
                                               categoryName: CategoryName.uncategorised, tags: [], place: "Fictional",
                                               city: "", categoriesIn: [], incomeBuckets: []),
                           count: index == 0 ? payments - (names - 1) : 1, cents: 100, first: "2026-10-01",
                           last: "2026-10-01", examples: [], ids: [])
        })
    }
}
