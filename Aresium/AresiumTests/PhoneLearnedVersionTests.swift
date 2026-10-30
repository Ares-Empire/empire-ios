import Foundation
import Testing
@testable import Aresium

@MainActor
struct PhoneLearnedVersionTests {
    private let auth = BackendAuth(token: nil)

    @Test func changedBundleRebuildsCurrentKeysAndNextImportUsesTheNewestCorrection() async throws {
        let defaults = PhoneTest.defaults()
        let engine = try PhonePickerBatchTests.countingEngine(paymentCount: 3)
        let old = try await PhoneCountingTests.backend(chosen: ["groceries", "hobbies"], engine: engine,
                                                       defaults: defaults, version: "old-bundle")
        _ = try await old.importFiles([PhoneTest.vrBank([
            ("02.10.2026", "Fictional Shop", "Old spelling", -2000),
            ("01.10.2026", "Fictional Shop", "Earlier payment imported later", -1000),
            ("02.10.2026", "Fictional Shop", "Same day, later sequence", -3000),
        ])], auth: auth)
        let payments = try await old.ledger.payments()
        for payment in payments {
            try await old.ledger.setCategory(payment.id, category: payment.amountValue == -30 ? "hobbies" : "groceries", source: .manual)
        }
        try await old.ledger.remember(["old shop key with card tail": "hobbies", "absent shop": "groceries"])
        let start = Int(try await engine.version())!
        let updated = PhoneBackend(ledger: old.ledger, engine: engine, defaults: defaults, engineVersion: { "new-bundle" })
        updated.today = { "2026-10-30" }
        try await updated.load()
        #expect(defaults.string(forKey: PhoneBackend.learnedVersionKey) == "new-bundle")
        #expect(Int(try await engine.version()) == start + 1)
        let key = try #require(try await engine.merchantKeys([payments[0].sorting(raw: false)]).first)
        let rules = try await updated.ledger.learned()
        #expect(rules[key] == "hobbies" && rules["old shop key with card tail"] == "hobbies" && rules["absent shop"] == "groceries")
        try await updated.load() // Same version: no migration sort.
        #expect(Int(try await engine.version()) == start + 1)
        _ = try await updated.importFiles([PhoneTest.vrBank([
            ("20.10.2026", "Fictional Shop", "Next purchase", -4000),
        ])], auth: auth)
        let next = try #require(try await updated.ledger.payments().last)
        #expect(next.category == "hobbies" && next.categorySource == .learned)
    }

    @Test func missingVersionMigratesButReceiptAndStructuralCategoriesDoNotTeach() async throws {
        let old = try await PhoneCountingTests.backend(chosen: ["groceries", "hobbies"])
        _ = try await old.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "Fictional Manual Shop", "Purchase", -1000),
            ("02.10.2026", "Fictional Receipt Shop", "Purchase", -2000),
            ("03.10.2026", "Fictional Transfer", "Transfer", -3000),
        ])], auth: auth)
        let payments = try await old.ledger.payments()
        for (payment, source) in zip(payments, [CategorySource.manual, .receipt, .structural]) {
            try await old.ledger.setCategory(payment.id, category: source == .structural ? "own-transfers" : "hobbies", source: source)
        }
        let defaults = PhoneTest.defaults()
        let updated = PhoneBackend(ledger: old.ledger, engine: old.engine, defaults: defaults, engineVersion: { "new-bundle" })
        try await updated.load()
        let keys = try await old.engine.merchantKeys(payments.map { $0.sorting(raw: false) })
        let learned = try await updated.ledger.learned()
        #expect(learned[keys[0]] == "hobbies" && learned[keys[1]] == nil && learned[keys[2]] == nil)
        #expect(defaults.string(forKey: PhoneBackend.learnedVersionKey) == "new-bundle")
    }

    @Test func restoringOlderKeysRebuildsEvenIfThisInstallAlreadySawTheVersion() async throws {
        let source = try await PhoneCountingTests.backend(chosen: ["hobbies"])
        _ = try await source.importFiles([PhoneTest.vrBank([("01.10.2026", "Fictional Shop", "Purchase", -1000)])], auth: auth)
        let id = try #require(try await source.ledger.payments().first?.id)
        try await source.ledger.setCategory(id, category: "hobbies", source: .manual)
        try await source.ledger.remember(["old key": "hobbies"])
        let data = try await source.export().encoded()
        let target = try await PhoneCountingTests.backend()
        try await target.restore(data)
        _ = try await target.importFiles([PhoneTest.vrBank([("20.10.2026", "Fictional Shop", "New purchase", -2000)])], auth: auth)
        #expect(try await target.ledger.payments().last?.categorySource == .learned)
    }
}
