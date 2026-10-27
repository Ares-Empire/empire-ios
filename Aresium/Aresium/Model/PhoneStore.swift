import Foundation
import os
import SwiftData

// Phone mode's storage: SwiftData, one store per iPhone in Application Support (`Aresium/local/`), with complete file
// protection (readable only while the iPhone is unlocked). The iPhone's own backup includes it.
//
// Migration: these are the models of schema version 1 (`LedgerSchemaV1`). Once a build with them has reached a phone,
// they are never changed in place: a change adds `LedgerSchemaV2` (copying the models it keeps) and a stage in
// `LedgerMigrationPlan`, and the typealiases below move to the new version.

nonisolated enum LedgerSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Account.self, Payment.self, Chosen.self, Rule.self, Layout.self]
    }

    /// A bank account, card or PayPal account the person imported from.
    @Model final class Account {
        /// The account's key (`AccountKey`): "iban:DE…", "paypal", "bank:<profile>…", "layout:<header>".
        @Attribute(.unique) var id: String
        var name: String
        var iban: String?
        var bank: String?
        var currency: String?

        init(id: String, name: String, iban: String?, bank: String?, currency: String?) {
            self.id = id
            self.name = name
            self.iban = iban
            self.bank = bank
            self.currency = currency
        }
    }

    /// One payment. Unique by (account, source, `externalId`), kept as `key`.
    @Model final class Payment {
        @Attribute(.unique) var id: String
        @Attribute(.unique) var key: String
        var account: String
        /// "bank" or "paypal".
        var source: String
        var externalId: String
        /// `YYYY-MM-DD`.
        var bookingDate: String
        var valueDate: String?
        /// The bank's amount as a decimal string ("-12.30"); negative = money out.
        var amount: String
        var currency: String
        var text: String
        var counterparty: String?
        /// The other party's IBAN, where the file has one (the own-transfer proof).
        var counterpartyIban: String?
        var balance: String?
        /// The bank's original row, as JSON.
        var raw: Data
        /// A category id (a default one, a built-in, or "custom-…"), or nil: not sorted.
        var category: String?
        /// Who set the category: `CategorySource`'s raw value.
        var categorySource: String
        /// Extra ("Add") categories it is also listed under.
        var extraCategories: [String]
        /// The order it was added in, so payments of one day keep their order.
        var sequence: Int

        init(_ value: LedgerPayment) {
            id = value.id
            key = LedgerPayment.key(account: value.account, source: value.source, externalId: value.externalId)
            account = value.account
            source = value.source
            externalId = value.externalId
            bookingDate = value.bookingDate
            valueDate = value.valueDate
            amount = value.amount
            currency = value.currency
            text = value.text
            counterparty = value.counterparty
            counterpartyIban = value.counterpartyIban
            balance = value.balance
            raw = (try? JSONEncoder().encode(value.raw ?? .null)) ?? Data("null".utf8)
            category = value.category
            categorySource = value.categorySource.rawValue
            extraCategories = value.extraCategories
            sequence = value.sequence
        }
    }

    /// A category the person chose: a default one by id, or their own (`custom-…`, with its name).
    @Model final class Chosen {
        @Attribute(.unique) var id: String
        var customName: String?
        var order: Int

        init(id: String, customName: String?, order: Int) {
            self.id = id
            self.customName = customName
            self.order = order
        }
    }

    /// A learned rule: payments of this merchant (the engine's `merchantKey`) go to this category.
    @Model final class Rule {
        @Attribute(.unique) var merchant: String
        var category: String

        init(merchant: String, category: String) {
            self.merchant = merchant
            self.category = category
        }
    }

    /// A CSV layout the person confirmed from a guess (never a known bank's layout, which would freeze it).
    @Model final class Layout {
        /// The separator and header row it is recognised by: a newer confirmation of the same table replaces it.
        @Attribute(.unique) var id: String
        var layout: Data
        var savedAt: Date

        init(id: String, layout: Data, savedAt: Date) {
            self.id = id
            self.layout = layout
            self.savedAt = savedAt
        }
    }
}

nonisolated enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [LedgerSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

typealias StoredAccount = LedgerSchemaV1.Account
typealias StoredPayment = LedgerSchemaV1.Payment
typealias StoredChosen = LedgerSchemaV1.Chosen
typealias StoredRule = LedgerSchemaV1.Rule
typealias StoredLayout = LedgerSchemaV1.Layout

/// Where the phone's one store lives (`Application Support/Aresium/local/`), opening and deleting it, and moving an
/// older per-account store over. Aresium's data belongs to the iPhone, not to an account (Patrik, 2026-10-27): until
/// then each Ares account had its own store in `Application Support/Aresium/<account id>/`.
nonisolated struct PhoneStorage: Sendable {
    let root: URL

    /// `Application Support/Aresium/`.
    static var standard: PhoneStorage {
        PhoneStorage(root: URL.applicationSupportDirectory.appending(path: "Aresium", directoryHint: .isDirectory))
    }

    static let storeName = "ledger.store"
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "storage")

    /// The store's folder: `<root>/local/`. (Ares account ids, the old folders' names, are 15 letters and digits, so
    /// "local" is never one of them.)
    var directory: URL { root.appending(path: "local", directoryHint: .isDirectory) }

    var storeURL: URL { directory.appending(path: Self.storeName) }

    var hasStore: Bool { FileManager.default.fileExists(atPath: storeURL.path) }

    /// `<root>/bank-outbox.json`: the bank formats and bank requests waiting to be sent to us, and the format layouts
    /// already asked about (`BankOutbox`). Outside `local/`, so the moving over never meets it; deleted with the store.
    /// (Brief 23's build called it `bank-formats.json`; no such build reached a phone, so nothing is moved over.)
    var bankOutboxURL: URL { root.appending(path: "bank-outbox.json") }

    /// Opens (or creates) the phone's store, after moving an older per-account store over (`moveOldStore`). Call off the
    /// main actor: the ledger then works on its own.
    func open() throws -> PhoneLedger {
        try moveOldStore()
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.complete])
        }
        let schema = Schema(versionedSchema: LedgerSchemaV1.self)
        let configuration = ModelConfiguration("Aresium", schema: schema, url: storeURL,
                                               allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: LedgerMigrationPlan.self,
                                           configurations: configuration)
        // New files inherit the folder's protection; the ones SQLite made before (or an older store's) get it here.
        for file in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        }
        return PhoneLedger(modelContainer: container)
    }

    /// Deletes the phone's store and its folder, and any older per-account store left behind by the moving over, so
    /// nothing of Aresium's payments stays on the iPhone (the privacy policy promises that for this action). Only
    /// Settings → "Delete Aresium data on this iPhone" and the lock's "Forgot the code?" call this; logging out,
    /// leaving Aresium and deleting the Ares account never do.
    func delete() throws {
        let manager = FileManager.default
        for old in oldStores() { try manager.removeItem(at: old.folder) }
        // A bank format or a bank's name not sent yet names the person's bank: it goes with the rest.
        if manager.fileExists(atPath: bankOutboxURL.path) { try manager.removeItem(at: bankOutboxURL) }
        guard manager.fileExists(atPath: directory.path) else { return }
        try manager.removeItem(at: directory)
    }

    // MARK: moving an older store over

    /// What `moveOldStore` did.
    enum Move: Equatable {
        /// The phone's store exists already, or there is no older one: nothing moved.
        case nothing
        /// The older store in this folder became the phone's store; `leftBehind` older stores stay as they are.
        case moved(from: String, leftBehind: Int)
    }

    /// Before the phone's store exists: an older per-account store (`<root>/<account id>/ledger.store`) becomes it, by
    /// moving its folder (never a copy, so the data is never twice on the phone). With several, the most recently
    /// changed one moves (its newest file decides) and the others stay untouched, where an update could still reach them.
    @discardableResult
    func moveOldStore() throws -> Move {
        guard !hasStore else { return .nothing }
        let candidates = oldStores()
        guard let newest = candidates.max(by: { $0.changed < $1.changed }) else { return .nothing }
        let manager = FileManager.default
        // A folder without a store file holds nothing that opens (left from a store deleted half-way): it makes room.
        if manager.fileExists(atPath: directory.path) { try manager.removeItem(at: directory) }
        try manager.moveItem(at: newest.folder, to: directory)
        let others = candidates.count - 1
        Self.log.notice("an older per-account store became this iPhone's store; \(others, privacy: .public) other per-account stores stay untouched")
        return .moved(from: newest.folder.lastPathComponent, leftBehind: others)
    }

    /// Every older per-account store: a folder in `root` other than `local` with a store file, and when its newest file
    /// last changed.
    func oldStores() -> [(folder: URL, changed: Date)] {
        let manager = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        guard let folders = try? manager.contentsOfDirectory(at: root, includingPropertiesForKeys: keys,
                                                             options: [.skipsHiddenFiles]) else { return [] }
        return folders.compactMap { folder in
            guard folder.lastPathComponent != directory.lastPathComponent,
                  (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                  manager.fileExists(atPath: folder.appending(path: Self.storeName).path) else { return nil }
            let files = (try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
            let changed = files.compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
                .max() ?? .distantPast
            return (folder, changed)
        }
    }
}
