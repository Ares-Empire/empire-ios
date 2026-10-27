import Foundation
import SwiftData

// Phone mode's storage: SwiftData, one store per Ares account in Application Support (`Aresium/<account id>/`), with
// complete file protection (readable only while the iPhone is unlocked). The iPhone's own backup includes it.
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

/// Where each account's store lives, and opening and deleting it.
nonisolated struct PhoneStorage: Sendable {
    let root: URL

    /// `Application Support/Aresium/`.
    static var standard: PhoneStorage {
        PhoneStorage(root: URL.applicationSupportDirectory.appending(path: "Aresium", directoryHint: .isDirectory))
    }

    /// A store's folder: `<root>/<account id>/`. Ares account ids are letters and digits; anything else is escaped, so
    /// an id can never name another folder.
    func directory(for account: String) -> URL {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        let name = account.addingPercentEncoding(withAllowedCharacters: allowed) ?? "account"
        return root.appending(path: name.isEmpty || name.hasPrefix(".") ? "account" : name, directoryHint: .isDirectory)
    }

    func storeURL(for account: String) -> URL { directory(for: account).appending(path: "ledger.store") }

    func hasStore(for account: String) -> Bool {
        FileManager.default.fileExists(atPath: storeURL(for: account).path)
    }

    /// Opens (or creates) the account's store. Call off the main actor: the ledger then works on its own.
    func open(account: String) throws -> PhoneLedger {
        let directory = directory(for: account)
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            try manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        } else {
            try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                        attributes: [.protectionKey: FileProtectionType.complete])
        }
        let schema = Schema(versionedSchema: LedgerSchemaV1.self)
        let configuration = ModelConfiguration("Aresium", schema: schema, url: storeURL(for: account),
                                               allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: LedgerMigrationPlan.self,
                                           configurations: configuration)
        // New files inherit the folder's protection; the ones SQLite made before (or an older store's) get it here.
        for file in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? manager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        }
        return PhoneLedger(modelContainer: container)
    }

    /// Deletes the account's store and its folder. Only three paths call this: Leave Aresium, Delete Ares account (each
    /// after the server said yes) and Settings → "Delete Aresium data on this iPhone".
    func delete(account: String) throws {
        let directory = directory(for: account)
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }
}
