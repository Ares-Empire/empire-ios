import Foundation
import Testing
@testable import Aresium

/// Phone mode's backend: imports with and without a known layout, sorting into the chosen categories, corrections that
/// teach, categories ticked and unticked, the dashboard and the widget, all on the phone.
@MainActor
struct PhoneBackendTests {
    private let none = BackendAuth(token: nil)

    // MARK: imports

    @Test func importSortsNewPaymentsAndCountsThem() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "rent"])
        let file = PhoneTest.vrBank([
            ("01.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345),
            ("02.10.2026", "Fiktiv Hausverwaltung", "Miete Oktober", -78000),
            ("03.10.2026", "Fiktiv Laden", "Einkauf", -500),
        ])
        let results = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        #expect(results == [PhoneImportResult(name: "vr.csv", added: 3, already: 0, sorted: 2, waiting: 1,
                                               account: results.first?.account, newIDs: results.first?.newIDs ?? [])])
        #expect(Set(results.first?.newIDs ?? []) == Set(try await phone.ledger.payments().map(\.id)))
        #expect(phone.importSummary(results.map { .phone($0) })
                == "3 new · 0 already there · 2 sorted · 1 not sorted")
        #expect(results.first?.displayMessage == "vr.csv: 3 new · 0 already there")
        let payments = try await phone.ledger.payments()
        #expect(payments.map(\.category) == ["groceries", "rent", nil])
        #expect(payments.map(\.categorySource) == [.starter, .starter, .none])
        #expect(phone.summary.unsorted == 1)
    }

    @Test func anUnknownLayoutWaitsForTheConfirmedOne() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let file = try PhoneTest.fixture("unknown-fiktivbank.csv")
        let first = try await phone.importFiles([file], auth: none)
        let guess = try #require(first.first?.layoutGuess)
        #expect(!(first.first?.failed ?? true) && phone.summary.payments == 0)
        #expect(first.first?.displayMessage == "unknown-fiktivbank.csv: check its columns")

        // Confirmed as guessed: saved, then the file reads with it.
        let layout = try #require(LayoutDraft(guess: guess).layout)
        try await phone.saveLayout(layout)
        let second = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        #expect(second.first?.layout == nil && second.first?.added == 4 && phone.summary.payments == 4)
        let payments = try await phone.ledger.payments()
        #expect(Set(payments.map(\.amount)) == ["-23.17", "-3.20", "1181.60"])
        // The next file of that bank needs no question, and its payments are already there.
        let third = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        #expect(third.first?.layout == nil && third.first?.added == 0 && third.first?.already == 4)
    }

    @Test func importStoreAsksForTheLayoutThenImports() async throws {
        let transport = RoutedTransport()
        let session = await PhoneTest.session(transport: transport)
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let dashboard = DashboardStore(session: session, backend: phone)
        let imports = ImportStore(dashboard: dashboard, background: PhoneActivity())
        let directory = PhoneTest.storage().root
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "Fiktivbank.csv")
        try PhoneTest.fixture("unknown-fiktivbank.csv").data.write(to: url)

        await imports.receive([url])
        await imports.importPendingFiles()
        let request = try #require(imports.layoutRequest)
        #expect(request.file.name == "Fiktivbank.csv" && phone.summary.payments == 0)
        #expect(transport.requests.allSatisfy { $0.url?.host != "aresium.de" })   // nothing left the phone

        let model = ColumnCheckModel(request: request, phone: phone, imports: imports)
        #expect(model.canConfirm)
        #expect(await model.confirm())
        #expect(imports.layoutRequest == nil)
        await imports.importPendingFiles()
        #expect(phone.summary.payments == 4)
        // How many the shop rules sort depends on the engine's shop list; the counts add up either way.
        let line = try #require(imports.banner?.message)
        #expect(line.hasPrefix("4 new · 0 already there · ") && line.hasSuffix(" not sorted"))
        #expect(dashboard.dashboard?.transactions.count == 4)
        #expect(transport.requests.allSatisfy { $0.url?.host != "aresium.de" })
    }

    @Test func aSkippedLayoutImportsNothing() async throws {
        let transport = RoutedTransport()
        let session = await PhoneTest.session(transport: transport)
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let imports = ImportStore(dashboard: DashboardStore(session: session, backend: phone), background: PhoneActivity())
        imports.debugImport([try PhoneTest.fixture("unknown-fiktivbank.csv")])
        await imports.importPendingFiles()
        let request = try #require(imports.layoutRequest)
        ColumnCheckModel(request: request, phone: phone, imports: imports).cancel()
        #expect(imports.layoutRequest == nil && imports.waitingCount == 0)
        #expect(phone.summary.payments == 0 && phone.summary.layouts == 0)
    }

    @Test func zipAndBrokenFilesAreWordedAndKeptForRetry() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let zip = ImportFile(name: "Sparkasse.zip", data: Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]))
        let results = try await phone.importFiles([zip, PhoneTest.fixture("dkb.csv")], auth: none)
        #expect(results.map(\.failed) == [true, false])
        #expect(results.first?.displayMessage == "Sparkasse.zip: Unzip the file first, then import what is inside.")
        #expect(phone.importSummary(results).hasSuffix(" · 1 file failed"))
    }

    // MARK: sorting and learning

    @Test func aSwitchLearnsTheMerchantAndAsksAboutTheOthers() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "hobbies"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "Fiktiv Laden", "Einkauf", -500),
            ("08.10.2026", "Fiktiv Laden", "Einkauf", -700),
            ("15.10.2026", "Fiktiv Laden", "Einkauf", -900),
            ("16.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2000),
        ])], auth: none)
        var payments = try await phone.ledger.payments()
        // One of the others was set by hand before: it is never moved.
        try await phone.ledger.setCategory(payments[2].id, category: "groceries", source: .manual)

        let result = try await phone.switchCategory(id: payments[0].id, to: "Hobbies", auth: none)
        #expect(result.detail.category == "Hobbies" && result.detail.categorySource == "manual")
        let followUp = try #require(result.followUp)
        #expect(followUp.count == 1 && followUp.shop == "Fiktiv Laden" && followUp.category == "Hobbies")
        #expect(try await phone.ledger.learned().values.contains("hobbies"))

        try await followUp.apply()
        payments = try await phone.ledger.payments()
        #expect(payments.map(\.category) == ["hobbies", "hobbies", "groceries", "groceries"])
        #expect(payments.map(\.categorySource) == [.manual, .learned, .manual, .starter])

        // A new payment of that merchant follows the learned rule.
        _ = try await phone.importFiles([PhoneTest.vrBank([("20.10.2026", "Fiktiv Laden", "Einkauf", -300)], name: "next.csv")],
                                        auth: none)
        let newest = try #require(try await phone.ledger.payments().last)
        #expect(newest.category == "hobbies" && newest.categorySource == .learned)
    }

    @Test func noQuestionWhenTheMerchantHasNoOtherPayments() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "hobbies"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "Fiktiv Laden", "Einkauf", -500)])], auth: none)
        let payment = try #require(try await phone.ledger.payments().first)
        let result = try await phone.switchCategory(id: payment.id, to: "Hobbies", auth: none)
        #expect(result.followUp == nil)
    }

    @Test func theDetailStoreAsksAndClosesWithTheAnswer() async throws {
        let transport = RoutedTransport()
        let session = await PhoneTest.session(transport: transport)
        let phone = try await PhoneTest.backend(chosen: ["groceries", "hobbies"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "Fiktiv Laden", "Einkauf", -500), ("02.10.2026", "Fiktiv Laden", "Einkauf", -600),
        ])], auth: none)
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()
        let transaction = try #require(dashboard.dashboard?.transactions.first)
        let detail = dashboard.transactionDetailStore(for: transaction)
        await detail.load()
        detail.beginRecategorisation()
        detail.select("Hobbies")
        await detail.save()
        #expect(detail.followUp?.count == 1 && detail.showsRecategorisation)    // asked in the open sheet
        await detail.answerFollowUp(moveOthers: true)
        #expect(detail.followUp == nil && !detail.showsRecategorisation)
        #expect(dashboard.dashboard?.transactions.allSatisfy { $0.categoryName == "Hobbies" } == true)
        #expect(transport.requests.allSatisfy { $0.url?.host != "aresium.de" })
    }

    @Test func addListsUnderMoreCategoriesOrMovesToTheFirst() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "household", "gifts"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000)])], auth: none)
        let id = try #require(try await phone.ledger.payments().first?.id)
        let tagged = try await phone.setTags(id: id, categories: ["Household"], dropCurrent: false, auth: none)
        #expect(tagged.category == "Groceries" && tagged.tags == ["Household"])
        let moved = try await phone.setTags(id: id, categories: ["Gifts", "Household"], dropCurrent: true, auth: none)
        #expect(moved.category == "Gifts" && moved.tags == ["Household"] && moved.categorySource == "manual")
        let dashboard = try await phone.dashboard(auth: none)
        #expect(dashboard.transactions.first?.categoriesIn == ["Gifts", "Household"])
    }

    @Test func paypalsBankLinesAreOwnTransfersOnceItsExportIsThere() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "shopping"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("03.10.2026", "PayPal Europe S.a.r.l. et Cie S.C.A", "Ihr Einkauf bei Fiktivladen", -1890),
        ])], auth: none)
        #expect(try await phone.ledger.payments().first?.category == nil)
        let paypal = """
        Datum,Name,Typ,Währung,Brutto,Netto,Transaktionscode,Auswirkung auf Guthaben
        03.10.2026,Fiktivladen,Allgemeine Zahlung,EUR,"-18,90","-18,90",FICTIONAL-PAY-9,Debit
        03.10.2026,Fiktivladen,Bankgutschrift auf PayPal-Konto,EUR,"18,90","18,90",FICTIONAL-FUND-9,Credit
        """
        _ = try await phone.importFiles([ImportFile(name: "paypal.csv", data: Data(paypal.utf8))], auth: none)
        let payments = try await phone.ledger.payments()
        let bankLine = try #require(payments.first { $0.source == "bank" })
        // An older payment re-sorted because the new import changed it (structural).
        #expect(bankLine.category == "own-transfers" && bankLine.categorySource == .structural)
        let dashboard = try await phone.dashboard(auth: none)
        #expect(dashboard.total.expense == 18.9)       // counted once, as PayPal's purchase
    }

    // MARK: categories

    @Test func tickingSortsWhatWaitedAndUntickingAsksWhereTheyGo() async throws {
        let phone = try await PhoneTest.backend(chosen: ["rent"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "REWE Markt GmbH", "REWE", -2000), ("02.10.2026", "Fiktiv Hausverwaltung", "Miete", -78000),
        ])], auth: none)
        #expect(phone.summary.unsorted == 1)
        let changes = ChangeCounter()
        let picker = CategoryPickerModel(phone: phone) { changes.count += 1 }
        await picker.load()
        #expect(picker.groups.first?.title == "Everyday" && picker.groups.first?.items.first?.name == "Groceries")
        await picker.toggle("groceries")
        #expect(await picker.flush())
        #expect(phone.summary.unsorted == 0 && changes.count == 1)

        await picker.toggle("groceries")                      // it has a payment: asks first
        let untick = try #require(picker.untick)
        #expect(untick.count == 1 && untick.targets.map(\.id) == ["rent"] && untick.notSortedName == "Not sorted")
        await picker.resolveUntick(moveTo: nil)
        #expect(await picker.flush())
        #expect(picker.list?.isChosen("groceries") == false)
        let rewe = try #require(try await phone.ledger.payments().first { $0.counterparty == "REWE Markt GmbH" })
        #expect(rewe.category == nil && rewe.categorySource == .none)

        picker.newName = "  Fictional club  "
        await picker.addCustom()
        #expect(picker.custom.map(\.name) == ["Fictional club"] && picker.newName.isEmpty)
        picker.newName = "lebensmittel"
        await picker.addCustom()
        #expect(picker.problem == "There is already a category with this name.")
        await picker.flush()
    }

    @Test func untickingIntoAnotherCategoryMovesThePaymentsByHand() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "household"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000)])], auth: none)
        try await phone.unchoose("groceries", moveTo: "household")
        let payment = try #require(try await phone.ledger.payments().first)
        #expect(payment.category == "household" && payment.categorySource == .manual)
    }

    @Test func categoryNamesFollowTheLanguageAndStayUnique() async throws {
        let catalog = try await PhoneTest.engine().catalog()
        let chosen = [ChosenCategory(id: "groceries", order: 0), ChosenCategory(id: "custom-1", name: "Climbing", order: 1)]
        let german = PhoneCategoryList(catalog: catalog, chosen: chosen, language: .german)
        #expect(german.name(of: "groceries") == "Lebensmittel" && german.id(named: "Lebensmittel") == "groceries")
        #expect(german.name(of: "own-transfers") == "Eigene Umbuchungen" && german.notSortedName == "Nicht sortiert")
        #expect(german.sourceCategories.map(\.name) == ["Lebensmittel", "Climbing", "Eigene Umbuchungen"])
        #expect(german.sourceCategories.last?.excludeFromTotals == true)
        let english = PhoneCategoryList(catalog: catalog, chosen: chosen, language: .english)
        #expect(english.id(named: "Climbing") == "custom-1" && english.id(named: "Lebensmittel") == nil)
        #expect(throws: LedgerError.nameTaken) { try english.checkedName("Lebensmittel") }
        #expect(throws: LedgerError.nameTaken) { try english.checkedName("climbing") }
        #expect(throws: LedgerError.nameTaken) { try english.checkedName("Uncategorised") }
        #expect(throws: LedgerError.emptyName) { try english.checkedName("   ") }
        #expect(try english.checkedName(" Bouldern ") == "Bouldern")
        #expect(german.groups.flatMap(\.items).contains { $0.name == "Lebensmittel" && $0.chosen })
        #expect(CategoryGroup.title("Something new") == "Something new")
    }

    // MARK: the dashboard

    @Test func theDashboardIsBuiltFromTheStoreAndPublishedForTheWidget() async throws {
        let transport = RoutedTransport()
        let session = await PhoneTest.session(transport: transport)
        let phone = try await PhoneTest.backend(chosen: ["groceries", "salary"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "Fiktiv Werke GmbH", "Gehalt Oktober", 200000),
            ("02.10.2026", "REWE Markt GmbH", "REWE", -2345),
            ("03.10.2026", "Fiktiv Laden", "Einkauf", -500),
        ])], auth: none)
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()
        let loaded = try #require(dashboard.dashboard)
        #expect(loaded.months.map(\.key) == ["2026-10"] && loaded.months.first?.partial == true)
        #expect(loaded.total.expense == 28.45 && loaded.total.income == 2000)
        #expect(loaded.pick.spend.contains("Groceries") && loaded.pick.income.contains("Salary & side jobs"))
        #expect(loaded.pick.income.contains("Own transfers"))
        let snapshot = try #require(dashboard.widgetPublisher.store.load())
        #expect(snapshot.phone && snapshot.account == nil && snapshot.expense == 28.45)   // the iPhone's, not the login's
        #expect(transport.requests.allSatisfy { $0.url?.host != "aresium.de" })
    }

    @Test func importWordingSaysWhatHappened() {
        let results = [PhoneImportResult(name: "a.csv", added: 12, already: 3, sorted: 10, waiting: 2),
                       PhoneImportResult(name: "b.zip", error: "Unzip the file first, then import what is inside.")]
        #expect(ImportWording.summary(results)
                == "12 new · 3 already there · 10 sorted · 2 not sorted · 1 file failed")
        #expect(ImportWording.bankFileProblem("noTable") == "No table of payments was found in this file.")
    }
}

@MainActor
final class ChangeCounter { var count = 0 }

@MainActor
final class PhoneActivity: ImportBackgroundActivity {
    func begin(expiration: @escaping @MainActor () -> Void) {}
    func end() {}
}
