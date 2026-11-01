import Foundation
import Testing
@testable import Aresium

/// The engine host (`AresiumEngine`): one JSContext with the app's bundle, typed calls, JSON across the bridge, bytes as
/// a Uint8Array, JavaScript exceptions as Swift errors with the readers' codes kept.
@MainActor
struct EngineHostTests {
    @Test func readsABankFileFromItsBytes() async throws {
        let engine = try PhoneTest.engine()
        let file = try await engine.readBankFile(PhoneTest.fixture("dkb.csv").data, layouts: [])
        #expect(file.format == "csv")
        #expect(file.bank?.name.contains("DKB") == true)
        #expect(file.account?.iban == "DE55120300000000556699")
        #expect(file.transactions.count >= 2)
        let rent = try #require(file.transactions.first { $0.description == "Miete Februar" })
        #expect(rent.amount == "-1080.00" && rent.day == "2026-02-04" && rent.counterparty == "Fiktiv Vermietung")
        if case let .object(raw)? = rent.raw { #expect(raw["Verwendungszweck"] == .string("Miete Februar")) }
        else { Issue.record("the original row is missing") }
    }

    @Test func decodesWindows1252ByItself() async throws {
        let engine = try PhoneTest.engine()
        let text = PhoneTest.vrBank([("03.02.2026", "Bäckerei Fiktiv", "Brötchen", -320)]).content
        let latin1 = try #require(text.data(using: .windowsCP1252))
        let file = try await engine.readBankFile(latin1, layouts: [])
        #expect(file.encoding == "windows-1252")
        #expect(file.transactions.first?.counterparty == "Bäckerei Fiktiv")
    }

    @Test func bankFileErrorsKeepTheirCodeAndAreWorded() async throws {
        let engine = try PhoneTest.engine()
        let zip = Data([0x50, 0x4B, 0x03, 0x04, 0x00, 0x00])
        await #expect(throws: EngineError.bankFile(code: "zip", message: "This is a ZIP archive; open it and import the files inside.")) {
            try await engine.readBankFile(zip, layouts: [])
        }
        await #expect(throws: EngineError.self) { try await engine.readBankFile(Data(), layouts: []) }
        do { _ = try await engine.readBankFile(Data("   ".utf8), layouts: []) }
        catch let error as EngineError {
            guard case .bankFile(let code, _) = error else { Issue.record("not a bank-file error"); return }
            #expect(code == "empty")
            #expect(error.localizedDescription == "The file is empty.")
        }
        #expect(EngineError.bankFile(code: "zip", message: "").localizedDescription
                == "Unzip the file first, then import what is inside.")
        for code in ["empty", "noTable", "headerMismatch", "camt", "mt940", "unknown", "new-code"] {
            #expect(!ImportWording.bankFileProblem(code).isEmpty)
        }
    }

    @Test func javascriptExceptionsBecomeSwiftErrors() async throws {
        await #expect(throws: EngineError.self) { _ = try AresiumEngine(script: "throw new Error('fictional')") }
        await #expect(throws: EngineError.self) { _ = try AresiumEngine(script: "globalThis.Other = {}") }
        let engine = try PhoneTest.engine()
        // A dashboard input the engine refuses (a date that is not one).
        let bad = DashboardSourceInput(transactions: [SourcePayment(id: "x", externalId: "x", date: "27.10.2026", amount: -1,
                                                                    currency: "EUR", description: "x", tags: [])],
                                       categories: [], today: "2026-10-27")
        await #expect(throws: EngineError.self) { try await engine.dashboard(bad) }
    }

    @Test func catalogHasTheDefaultListWithLooks() async throws {
        let catalog = try await PhoneTest.engine().catalog()
        #expect(catalog.defaults.count > 30)
        #expect(catalog.builtIns.map(\.id) == ["own-transfers", "not-sorted"])
        #expect(catalog.defaults.allSatisfy { catalog.looks[$0.id] != nil })
        #expect(catalog.category("groceries")?.name == .init(en: "Groceries", de: "Lebensmittel"))
        #expect(catalog.look("custom-x") == catalog.custom)
        // Every icon of the list maps to an SF Symbol (not the "tag" fallback, except the custom look's own Tag).
        #expect(catalog.looks.values.allSatisfy { $0.icon == "Tag" || CategorySymbol.name(for: $0.icon) != "tag" })
    }

    @Test func sortsOnlyIntoChosenCategoriesAndLearns() async throws {
        let engine = try PhoneTest.engine()
        let rewe = SortingPayment(counterparty: "REWE Markt GmbH", description: "REWE SAGT DANKE", source: "bank",
                                  account: "a", amount: -12.3, currency: "EUR", date: "2026-10-01")
        let shop = SortingPayment(counterparty: "Fiktiv Laden", description: "Einkauf", source: "bank", account: "a",
                                  amount: -5, currency: "EUR", date: "2026-10-02")
        let sorted = try await engine.sortPayments([rewe, shop], categories: ["groceries", "own-transfers"], learned: [:])
        #expect(sorted == [SortResult(categoryId: "groceries", source: "starter"), SortResult(categoryId: nil, source: nil)])
        let none = try await engine.sortPayments([rewe], categories: ["rent"], learned: [:])
        #expect(none == [SortResult(categoryId: nil, source: nil)])
        let rule = try await engine.learn(shop, categoryID: "hobbies")
        #expect(rule.count == 1 && rule.values.first == "hobbies")
        let learned = try await engine.sortPayments([shop], categories: ["hobbies"], learned: rule)
        #expect(learned == [SortResult(categoryId: "hobbies", source: "learned")])
        let keys = try await engine.merchantKeys([rewe, shop, shop])
        #expect(keys[1] == keys[2] && keys[0] != keys[1] && keys[1] == rule.keys.first)
    }

    @Test func nameJobChecksCardStatementsAlongsideMerchantKeys() async throws {
        let engine = try PhoneTest.engine()
        let plain = SortingPayment(counterparty: "Fictional Shop, UAB", description: "", source: "paypal", account: "sample",
                                   amount: -10, currency: "EUR", date: "2026-10-01")
        var card = plain
        card.counterparty = "FICTIONAL SHOP, UAB   IRL CORK   EUR  14,99   Umsatz vom 02.10.2026   MC Fictional Card"
        let checked = try await engine.nameKeys([plain, card], lines: [plain, card, plain])
        #expect(checked.keys.count == 2 && checked.keys[0] == checked.keys[1])
        #expect(checked.lineKeys == [checked.keys[0], checked.keys[0], checked.keys[0]])
        #expect(checked.cardLines == [false, true, false])
        let empty = try await engine.nameKeys([], lines: [])
        #expect(empty.keys.isEmpty && empty.lineKeys.isEmpty && empty.cardLines.isEmpty)
    }

    @Test func ownTransfersNeedProof() async throws {
        let engine = try PhoneTest.engine()
        let out = SortingPayment(counterparty: "Fiktiv Person", description: "Umbuchung", source: "bank", account: "a",
                                 accountIban: "DE89370400440532013000", counterpartyIban: "DE02120300000000202051",
                                 amount: -200, currency: "EUR", date: "2026-10-01")
        let incoming = SortingPayment(counterparty: "Fiktiv Person", description: "Umbuchung", source: "bank", account: "b",
                                      accountIban: "DE02120300000000202051", amount: 200, currency: "EUR", date: "2026-10-02")
        let sorted = try await engine.sortPayments([out, incoming], categories: ["other"], learned: [:])
        #expect(sorted.allSatisfy { $0 == SortResult(categoryId: "own-transfers", source: "structural") })
        var unrelated = incoming
        unrelated.description = "Rückzahlung Kino"
        unrelated.counterparty = "Fiktiv Freund"
        var paid = out
        paid.description = "Kino"
        paid.counterpartyIban = nil
        let neither = try await engine.sortPayments([paid, unrelated], categories: ["other"], learned: [:])
        #expect(neither.allSatisfy { $0.source != "structural" })
    }

    @Test func buildsTheSameDashboardTypeFromStoredPayments() async throws {
        let engine = try PhoneTest.engine()
        let input = DashboardSourceInput(
            transactions: [
                SourcePayment(id: "p1", externalId: "e1", date: "2026-09-03", amount: -40, currency: "EUR", balance: 960,
                              description: "REWE", counterparty: "REWE", category: "Groceries", tags: []),
                SourcePayment(id: "p2", externalId: "e2", date: "2026-10-01", amount: 1000, currency: "EUR", balance: 1960,
                              description: "Gehalt", counterparty: "Fiktiv Werke", category: "Salary & side jobs", tags: []),
                SourcePayment(id: "p3", externalId: "e3", date: "2026-10-02", amount: -9, currency: "EUR",
                              description: "Laden", category: nil, tags: []),
            ],
            categories: [SourceCategory(name: "Groceries", icon: "ShoppingCart", color: "#26E07A", excludeFromTotals: false),
                         SourceCategory(name: "Salary & side jobs", icon: "Wallet", color: "#25E07A", excludeFromTotals: false)],
            today: "2026-10-27")
        let dashboard = try await engine.dashboard(input)
        #expect(dashboard.version == 2)
        #expect(dashboard.months.map(\.key) == ["2026-09", "2026-10"])
        #expect(dashboard.months.last?.partial == true && dashboard.months.last?.days == 27)
        #expect(dashboard.total.expense == 49 && dashboard.total.income == 1000)
        #expect(dashboard.categories.contains { $0.name == "Uncategorised" })
        #expect(dashboard.pick.spend.contains("Groceries") && !dashboard.pick.spend.contains("Uncategorised"))
        #expect(try await engine.version().isEmpty == false)
    }
}
