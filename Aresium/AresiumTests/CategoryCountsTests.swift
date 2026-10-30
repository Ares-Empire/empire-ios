import Foundation
import Testing
@testable import Aresium

/// The numbers in the category picker (brief 27, Patrik 2026-10-27): a ticked category and one's own show the payments
/// in them; a default category not ticked shows how many of the waiting payments ticking it would sort there (a dry run,
/// nothing stored); no number at 0 or before any payment; counted again after every tick. Made-up payments only.
@MainActor
struct CategoryCountsTests {
    private let none = BackendAuth(token: nil)

    /// 2 groceries (REWE), 1 rent (the landlord), 2 at a made-up climbing hall that fits no default category.
    static let bankFile = PhoneTest.vrBank([
        ("01.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345),
        ("02.10.2026", "Fiktiv Hausverwaltung", "Miete Oktober", -78000),
        ("03.10.2026", "Fiktiv Kletterhalle", "Eintritt", -1400),
        ("08.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -1210),
        ("10.10.2026", "Fiktiv Kletterhalle", "Eintritt", -1400),
    ])

    @Test func noNumbersBeforeAnyPayment() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        #expect(try await phone.categoryCounts().isEmpty)
        let picker = CategoryPickerModel(phone: phone) {}
        await picker.load()
        #expect(picker.count(of: "groceries") == nil && picker.count(of: "rent") == nil && !picker.showsCounts)
    }

    @Test func tickedUntickedAndOwnCategories() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let climbing = try await phone.addCustom(named: "Climbing")
        _ = try await phone.importFiles([Self.bankFile], auth: none)
        // One climbing payment put into one's own category by hand (the other stays Not sorted: not asked here).
        let hall = try #require(try await phone.ledger.payments().first { $0.counterparty == "Fiktiv Kletterhalle" })
        try await phone.ledger.setCategory(hall.id, category: climbing, source: .manual)
        try await phone.refresh()

        let counts = try await phone.categoryCounts()
        #expect(counts["groceries"] == 2, "ticked: the payments in it")
        #expect(counts["rent"] == 1, "not ticked: what ticking it would sort there")
        #expect(counts[climbing] == 1, "one's own: the payments in it")
        #expect(counts.values.allSatisfy { $0 > 0 }, "no entry at 0")
        #expect(counts["clothes"] == nil && counts["eating-out"] == nil)
        // Nothing was stored: the rent payment still waits.
        #expect(try await phone.ledger.payments().filter { $0.category == nil }.count == 2)
        #expect(try await phone.paymentCount(in: "rent") == 0)

        let picker = CategoryPickerModel(phone: phone) {}
        await picker.load()
        #expect(picker.count(of: "groceries") == 2 && picker.count(of: "rent") == 1 && picker.count(of: climbing) == 1)
        #expect(picker.count(of: "clothes") == nil && picker.showsCounts)
    }

    @Test func countedAgainAfterATick() async throws {
        let phone = try await PhoneTest.backend()
        _ = try await phone.importFiles([Self.bankFile], auth: none)
        let picker = CategoryPickerModel(phone: phone) {}
        await picker.load()
        // Nothing ticked: every number is what ticking would bring.
        #expect(picker.count(of: "groceries") == 2 && picker.count(of: "rent") == 1)
        let estimate = try #require(picker.count(of: "rent"))

        await picker.toggle("rent")
        #expect(await picker.flush())
        // Ticked, it holds what the estimate said, and the others still show theirs.
        #expect(try await phone.paymentCount(in: "rent") == estimate)
        #expect(picker.count(of: "rent") == estimate && picker.count(of: "groceries") == 2)
        #expect(phone.summary.unsorted == 4)

        await picker.toggle("groceries")
        #expect(await picker.flush())
        #expect(picker.count(of: "groceries") == 2 && phone.summary.unsorted == 2)
    }

    @Test func untickedCategoriesShareOnlyTheWaitingPayments() async throws {
        // A payment already in a ticked category is not counted again for an unticked one.
        let phone = try await PhoneTest.backend(chosen: ["groceries", "rent"])
        _ = try await phone.importFiles([Self.bankFile], auth: none)
        let counts = try await phone.categoryCounts()
        #expect(counts["groceries"] == 2 && counts["rent"] == 1)
        let catalog = try #require(phone.catalog)
        let unticked = catalog.defaults.map(\.id).filter { $0 != "groceries" && $0 != "rent" }
        let estimated = unticked.reduce(0) { $0 + (counts[$1] ?? 0) }
        #expect(estimated <= phone.summary.unsorted)
    }
}
