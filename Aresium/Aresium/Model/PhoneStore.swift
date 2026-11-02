import Foundation
import os
import SwiftData

// Phone mode's storage: SwiftData, one store per iPhone in Application Support (`Aresium/local/`), with complete file
// protection (readable only while the iPhone is unlocked). The iPhone's own backup includes it.
//
// Migration: a schema version's models are never changed in place once a build with them may have made a store: a
// change adds the next version (copying the models it keeps) and a stage in `LedgerMigrationPlan`, and the typealiases
// below move to it. Version 1 (briefs 15–28) has the payments; version 2 (brief 31) adds the receipts, a lightweight
// stage (a new model only); version 3 (brief 33) gives receipts a direction, a kind, where cash was paid from and the
// shop as read, and adds the shop-name corrections, a lightweight stage too (a new model, attributes with defaults);
// version 4 (brief 36) gives one's own categories their icon and colour, a lightweight stage (attributes with defaults;
// the looks themselves are chosen when the store is opened); version 5 (brief 43) adds payment names and name rules,
// also lightweight; version 6 (brief 69) adds home sides and other-side offers, assigned once at opening. The older versions' models stay below, unchanged, so their stores are recognised and moved on
// version 7 (brief 202) adds optional payback link data on payments, also lightweight.
// (`ReceiptBookTests` opens one made by version 1's code,
// `ReceiptCorrectionTests` one made by version 2's, `OwnCategoryLookTests` one made by version 3's).

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

/// Version 2 (brief 31): version 1's models as they were, and the receipts.
nonisolated enum LedgerSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Account.self, Payment.self, Chosen.self, Rule.self, Layout.self, Receipt.self]
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

    /// A receipt the person scanned or picked as a photo and checked (brief 31): what was read and confirmed, never
    /// the image.
    @Model final class Receipt {
        @Attribute(.unique) var id: String
        /// The purchase day, `YYYY-MM-DD`, and its time (`HH:MM`) when the receipt printed one.
        var date: String
        var time: String?
        var shop: String?
        /// The amount paid as a decimal string ("27.65"), in `currency`.
        var total: String
        /// ISO 4217 ("EUR").
        var currency: String
        /// A cash receipt in another currency: what it cost in euros, as the person typed it (decimal string).
        var euroAmount: String?
        /// `ReceiptMethod`'s raw value: "card" or "cash".
        var method: String
        /// A category id, or nil: not sorted. Who set it: `CategorySource`'s raw value.
        var category: String?
        var categorySource: String
        /// The receipt's lines as the engine read them, top to bottom (what is kept instead of a photo).
        var rows: [String]
        /// "code" when the register's QR code was read, else "text".
        var from: String
        /// The bank payment it is joined to; nil while it waits (card) or for cash.
        var paymentID: String?
        /// Payments the person said are not this receipt's: never offered for it again.
        var declined: [String]
        var created: Date

        init(_ value: LedgerReceipt) {
            id = value.id
            date = value.date
            time = value.time
            shop = value.shop
            total = value.total
            currency = value.currency
            euroAmount = value.euroAmount
            method = value.method.rawValue
            category = value.category
            categorySource = value.categorySource.rawValue
            rows = value.rows
            from = value.from
            paymentID = value.paymentID
            declined = value.declined
            created = value.created
        }
    }
}

/// Version 3 (brief 33): version 2's models as they were, the receipts with `direction`, `kind`, `paidFrom` and
/// `shopAsRead` (each with a default, so version 2's receipts move on by themselves), and the shop-name corrections.
nonisolated enum LedgerSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Account.self, Payment.self, Chosen.self, Rule.self, Layout.self, Receipt.self, ShopName.self]
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

    /// A receipt the person scanned or picked as a photo and checked (brief 31): what was read and confirmed, never
    /// the image.
    @Model final class Receipt {
        @Attribute(.unique) var id: String
        /// The purchase day, `YYYY-MM-DD`, and its time (`HH:MM`) when the receipt printed one.
        var date: String
        var time: String?
        var shop: String?
        /// The amount paid as a decimal string ("27.65"), in `currency`.
        var total: String
        /// ISO 4217 ("EUR").
        var currency: String
        /// A cash receipt in another currency: what it cost in euros, as the person typed it (decimal string).
        var euroAmount: String?
        /// `ReceiptMethod`'s raw value: "card" or "cash".
        var method: String
        /// A category id, or nil: not sorted. Who set it: `CategorySource`'s raw value.
        var category: String?
        var categorySource: String
        /// The receipt's lines as the engine read them, top to bottom (what is kept instead of a photo).
        var rows: [String]
        /// "code" when the register's QR code was read, else "text".
        var from: String
        /// The bank payment it is joined to; nil while it waits (card) or for cash.
        var paymentID: String?
        /// Payments the person said are not this receipt's: never offered for it again.
        var declined: [String]
        var created: Date
        /// `ReceiptDirection`'s raw value: "out" (a purchase), or "in" (cash received, entered by hand).
        var direction: String = "out"
        /// `ReceiptKind`'s raw value: "receipt" (scanned or picked) or "manual" (typed by hand).
        var kind: String = "receipt"
        /// Cash out: the withdrawal payment or received-cash entry it was paid from; nil: automatic.
        var paidFrom: String? = nil
        /// The shop's name as the engine read it (a later change of the shop teaches the name, `ShopNames`).
        var shopAsRead: String? = nil

        init(_ value: LedgerReceipt) {
            id = value.id
            date = value.date
            time = value.time
            shop = value.shop
            total = value.total
            currency = value.currency
            euroAmount = value.euroAmount
            method = value.method.rawValue
            category = value.category
            categorySource = value.categorySource.rawValue
            rows = value.rows
            from = value.from
            paymentID = value.paymentID
            declined = value.declined
            created = value.created
            direction = value.direction.rawValue
            kind = value.kind.rawValue
            paidFrom = value.paidFrom
            shopAsRead = value.shopAsRead
        }
    }

    /// A shop's name as the person corrected it (brief 33): the shop as read, normalised (`ShopNames.key`), and the
    /// name they typed. The next receipt read the same way shows that name.
    @Model final class ShopName {
        @Attribute(.unique) var read: String
        var name: String
        var saved: Date

        init(read: String, name: String, saved: Date) {
            self.read = read
            self.name = name
            self.saved = saved
        }
    }
}

/// Version 4 (brief 36): version 3's models as they were, and one's own categories with the icon and colour chosen
/// when each was made (`OwnCategoryLook`; nil for a default category, and until the store is opened once).
nonisolated enum LedgerSchemaV4: VersionedSchema {
    static let versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Account.self, Payment.self, Chosen.self, Rule.self, Layout.self, Receipt.self, ShopName.self]
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

    /// A category the person chose: a default one by id, or their own (`custom-…`, with its name and its look).
    @Model final class Chosen {
        @Attribute(.unique) var id: String
        var customName: String?
        var order: Int
        /// One's own category: its icon (an engine icon name, drawn by `CategorySymbol`) and colour (`#RRGGBB`), chosen
        /// when it was made and kept so it never changes. Nil for a default category (the engine's look).
        var icon: String? = nil
        var color: String? = nil

        init(id: String, customName: String?, order: Int, look: CategoryLook? = nil) {
            self.id = id
            self.customName = customName
            self.order = order
            icon = look?.icon
            color = look?.color
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

    /// A receipt the person scanned or picked as a photo and checked (brief 31): what was read and confirmed, never
    /// the image.
    @Model final class Receipt {
        @Attribute(.unique) var id: String
        /// The purchase day, `YYYY-MM-DD`, and its time (`HH:MM`) when the receipt printed one.
        var date: String
        var time: String?
        var shop: String?
        /// The amount paid as a decimal string ("27.65"), in `currency`.
        var total: String
        /// ISO 4217 ("EUR").
        var currency: String
        /// A cash receipt in another currency: what it cost in euros, as the person typed it (decimal string).
        var euroAmount: String?
        /// `ReceiptMethod`'s raw value: "card" or "cash".
        var method: String
        /// A category id, or nil: not sorted. Who set it: `CategorySource`'s raw value.
        var category: String?
        var categorySource: String
        /// The receipt's lines as the engine read them, top to bottom (what is kept instead of a photo).
        var rows: [String]
        /// "code" when the register's QR code was read, else "text".
        var from: String
        /// The bank payment it is joined to; nil while it waits (card) or for cash.
        var paymentID: String?
        /// Payments the person said are not this receipt's: never offered for it again.
        var declined: [String]
        var created: Date
        /// `ReceiptDirection`'s raw value: "out" (a purchase), or "in" (cash received, entered by hand).
        var direction: String = "out"
        /// `ReceiptKind`'s raw value: "receipt" (scanned or picked) or "manual" (typed by hand).
        var kind: String = "receipt"
        /// Cash out: the withdrawal payment or received-cash entry it was paid from; nil: automatic.
        var paidFrom: String? = nil
        /// The shop's name as the engine read it (a later change of the shop teaches the name, `ShopNames`).
        var shopAsRead: String? = nil

        init(_ value: LedgerReceipt) {
            id = value.id
            date = value.date
            time = value.time
            shop = value.shop
            total = value.total
            currency = value.currency
            euroAmount = value.euroAmount
            method = value.method.rawValue
            category = value.category
            categorySource = value.categorySource.rawValue
            rows = value.rows
            from = value.from
            paymentID = value.paymentID
            declined = value.declined
            created = value.created
            direction = value.direction.rawValue
            kind = value.kind.rawValue
            paidFrom = value.paidFrom
            shopAsRead = value.shopAsRead
        }
    }

    /// A shop's name as the person corrected it (brief 33): the shop as read, normalised (`ShopNames.key`), and the
    /// name they typed. The next receipt read the same way shows that name.
    @Model final class ShopName {
        @Attribute(.unique) var read: String
        var name: String
        var saved: Date

        init(read: String, name: String, saved: Date) {
            self.read = read
            self.name = name
            self.saved = saved
        }
    }
}

/// Version 5 (brief 43): payment names and merchant name rules; earlier models stay unchanged.
nonisolated enum LedgerSchemaV5: VersionedSchema {
    static let versionIdentifier = Schema.Version(5, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Account.self, Payment.self, Chosen.self, Rule.self, Layout.self, Receipt.self, ShopName.self, PaymentName.self]
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
        /// The name for this payment alone; nil lets the shop rule apply.
        var ownName: String? = nil

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
            ownName = value.ownName
        }
    }

    /// A category the person chose: a default one by id, or their own (`custom-…`, with its name and its look).
    @Model final class Chosen {
        @Attribute(.unique) var id: String
        var customName: String?
        var order: Int
        /// One's own category: its icon (an engine icon name, drawn by `CategorySymbol`) and colour (`#RRGGBB`), chosen
        /// when it was made and kept so it never changes. Nil for a default category (the engine's look).
        var icon: String? = nil
        var color: String? = nil

        init(id: String, customName: String?, order: Int, look: CategoryLook? = nil) {
            self.id = id
            self.customName = customName
            self.order = order
            icon = look?.icon
            color = look?.color
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

    /// A receipt the person scanned or picked as a photo and checked (brief 31): what was read and confirmed, never
    /// the image.
    @Model final class Receipt {
        @Attribute(.unique) var id: String
        /// The purchase day, `YYYY-MM-DD`, and its time (`HH:MM`) when the receipt printed one.
        var date: String
        var time: String?
        var shop: String?
        /// The amount paid as a decimal string ("27.65"), in `currency`.
        var total: String
        /// ISO 4217 ("EUR").
        var currency: String
        /// A cash receipt in another currency: what it cost in euros, as the person typed it (decimal string).
        var euroAmount: String?
        /// `ReceiptMethod`'s raw value: "card" or "cash".
        var method: String
        /// A category id, or nil: not sorted. Who set it: `CategorySource`'s raw value.
        var category: String?
        var categorySource: String
        /// The receipt's lines as the engine read them, top to bottom (what is kept instead of a photo).
        var rows: [String]
        /// "code" when the register's QR code was read, else "text".
        var from: String
        /// The bank payment it is joined to; nil while it waits (card) or for cash.
        var paymentID: String?
        /// Payments the person said are not this receipt's: never offered for it again.
        var declined: [String]
        var created: Date
        /// `ReceiptDirection`'s raw value: "out" (a purchase), or "in" (cash received, entered by hand).
        var direction: String = "out"
        /// `ReceiptKind`'s raw value: "receipt" (scanned or picked) or "manual" (typed by hand).
        var kind: String = "receipt"
        /// Cash out: the withdrawal payment or received-cash entry it was paid from; nil: automatic.
        var paidFrom: String? = nil
        /// The shop's name as the engine read it (a later change of the shop teaches the name, `ShopNames`).
        var shopAsRead: String? = nil

        init(_ value: LedgerReceipt) {
            id = value.id
            date = value.date
            time = value.time
            shop = value.shop
            total = value.total
            currency = value.currency
            euroAmount = value.euroAmount
            method = value.method.rawValue
            category = value.category
            categorySource = value.categorySource.rawValue
            rows = value.rows
            from = value.from
            paymentID = value.paymentID
            declined = value.declined
            created = value.created
            direction = value.direction.rawValue
            kind = value.kind.rawValue
            paidFrom = value.paidFrom
            shopAsRead = value.shopAsRead
        }
    }

    /// A shop's name as the person corrected it (brief 33): the shop as read, normalised (`ShopNames.key`), and the
    /// name they typed. The next receipt read the same way shows that name.
    @Model final class ShopName {
        @Attribute(.unique) var read: String
        var name: String
        var saved: Date

        init(read: String, name: String, saved: Date) {
            self.read = read
            self.name = name
            self.saved = saved
        }
    }
    /// A payment name for every bank payment with the engine's merchant key.
    @Model final class PaymentName {
        @Attribute(.unique) var merchant: String
        var name: String

        init(merchant: String, name: String) {
            self.merchant = merchant
            self.name = name
        }
    }

}

/// Version 6 (brief 69): categories keep their home side and whether the other side offers them.
nonisolated enum LedgerSchemaV6: VersionedSchema {
    static let versionIdentifier = Schema.Version(6, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Account.self, Payment.self, Chosen.self, Rule.self, Layout.self, Receipt.self, ShopName.self, PaymentName.self]
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
        /// The name for this payment alone; nil lets the shop rule apply.
        var ownName: String? = nil

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
            ownName = value.ownName
        }
    }

    /// A category the person chose: a default one by id, or their own (`custom-…`, with its name and its look).
    @Model final class Chosen {
        @Attribute(.unique) var id: String
        var customName: String?
        var order: Int
        /// One's own category: its icon (an engine icon name, drawn by `CategorySymbol`) and colour (`#RRGGBB`), chosen
        /// when it was made and kept so it never changes. Nil for a default category (the engine's look).
        var icon: String? = nil
        var color: String? = nil

        /// Only one's own category stores a home side; defaults use the engine's catalog.
        var side: String? = nil
        var otherSide: Bool = false
        /// Internal, once-only migration marker: removing otherSide must survive reopening an older store.
        var sidesAssigned: Bool = false

        init(id: String, customName: String?, order: Int, look: CategoryLook? = nil, side: String? = nil, otherSide: Bool = false,
             sidesAssigned: Bool = true) {
            self.id = id
            self.customName = customName
            self.order = order
            icon = look?.icon
            color = look?.color
            self.side = side
            self.otherSide = otherSide
            self.sidesAssigned = sidesAssigned
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

    /// A receipt the person scanned or picked as a photo and checked (brief 31): what was read and confirmed, never
    /// the image.
    @Model final class Receipt {
        @Attribute(.unique) var id: String
        /// The purchase day, `YYYY-MM-DD`, and its time (`HH:MM`) when the receipt printed one.
        var date: String
        var time: String?
        var shop: String?
        /// The amount paid as a decimal string ("27.65"), in `currency`.
        var total: String
        /// ISO 4217 ("EUR").
        var currency: String
        /// A cash receipt in another currency: what it cost in euros, as the person typed it (decimal string).
        var euroAmount: String?
        /// `ReceiptMethod`'s raw value: "card" or "cash".
        var method: String
        /// A category id, or nil: not sorted. Who set it: `CategorySource`'s raw value.
        var category: String?
        var categorySource: String
        /// The receipt's lines as the engine read them, top to bottom (what is kept instead of a photo).
        var rows: [String]
        /// "code" when the register's QR code was read, else "text".
        var from: String
        /// The bank payment it is joined to; nil while it waits (card) or for cash.
        var paymentID: String?
        /// Payments the person said are not this receipt's: never offered for it again.
        var declined: [String]
        var created: Date
        /// `ReceiptDirection`'s raw value: "out" (a purchase), or "in" (cash received, entered by hand).
        var direction: String = "out"
        /// `ReceiptKind`'s raw value: "receipt" (scanned or picked) or "manual" (typed by hand).
        var kind: String = "receipt"
        /// Cash out: the withdrawal payment or received-cash entry it was paid from; nil: automatic.
        var paidFrom: String? = nil
        /// The shop's name as the engine read it (a later change of the shop teaches the name, `ShopNames`).
        var shopAsRead: String? = nil

        init(_ value: LedgerReceipt) {
            id = value.id
            date = value.date
            time = value.time
            shop = value.shop
            total = value.total
            currency = value.currency
            euroAmount = value.euroAmount
            method = value.method.rawValue
            category = value.category
            categorySource = value.categorySource.rawValue
            rows = value.rows
            from = value.from
            paymentID = value.paymentID
            declined = value.declined
            created = value.created
            direction = value.direction.rawValue
            kind = value.kind.rawValue
            paidFrom = value.paidFrom
            shopAsRead = value.shopAsRead
        }
    }

    /// A shop's name as the person corrected it (brief 33): the shop as read, normalised (`ShopNames.key`), and the
    /// name they typed. The next receipt read the same way shows that name.
    @Model final class ShopName {
        @Attribute(.unique) var read: String
        var name: String
        var saved: Date

        init(read: String, name: String, saved: Date) {
            self.read = read
            self.name = name
            self.saved = saved
        }
    }
    /// A payment name for every bank payment with the engine's merchant key.
    @Model final class PaymentName {
        @Attribute(.unique) var merchant: String
        var name: String

        init(merchant: String, name: String) {
            self.merchant = merchant
            self.name = name
        }
    }

}

/// Version 7 (brief 202): payments keep their hand-made payback links.
nonisolated enum LedgerSchemaV7: VersionedSchema {
    static let versionIdentifier = Schema.Version(7, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Account.self, Payment.self, Chosen.self, Rule.self, Layout.self, Receipt.self, ShopName.self, PaymentName.self]
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
        /// The name for this payment alone; nil lets the shop rule apply.
        var ownName: String? = nil
        /// Schema 7: positive decimal euros, on the incoming payment only.
        var paybackData: Data? = nil

        var paysBack: [LedgerPayback]? {
            get { paybackData.flatMap { try? JSONDecoder().decode([LedgerPayback].self, from: $0) } }
            set { paybackData = newValue.flatMap { try? JSONEncoder().encode($0) } }
        }

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
            ownName = value.ownName
            paysBack = value.paysBack
        }
    }

    /// A category the person chose: a default one by id, or their own (`custom-…`, with its name and its look).
    @Model final class Chosen {
        @Attribute(.unique) var id: String
        var customName: String?
        var order: Int
        /// One's own category: its icon (an engine icon name, drawn by `CategorySymbol`) and colour (`#RRGGBB`), chosen
        /// when it was made and kept so it never changes. Nil for a default category (the engine's look).
        var icon: String? = nil
        var color: String? = nil

        /// Only one's own category stores a home side; defaults use the engine's catalog.
        var side: String? = nil
        var otherSide: Bool = false
        /// Internal, once-only migration marker: removing otherSide must survive reopening an older store.
        var sidesAssigned: Bool = false

        init(id: String, customName: String?, order: Int, look: CategoryLook? = nil, side: String? = nil, otherSide: Bool = false,
             sidesAssigned: Bool = true) {
            self.id = id
            self.customName = customName
            self.order = order
            icon = look?.icon
            color = look?.color
            self.side = side
            self.otherSide = otherSide
            self.sidesAssigned = sidesAssigned
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

    /// A receipt the person scanned or picked as a photo and checked (brief 31): what was read and confirmed, never
    /// the image.
    @Model final class Receipt {
        @Attribute(.unique) var id: String
        /// The purchase day, `YYYY-MM-DD`, and its time (`HH:MM`) when the receipt printed one.
        var date: String
        var time: String?
        var shop: String?
        /// The amount paid as a decimal string ("27.65"), in `currency`.
        var total: String
        /// ISO 4217 ("EUR").
        var currency: String
        /// A cash receipt in another currency: what it cost in euros, as the person typed it (decimal string).
        var euroAmount: String?
        /// `ReceiptMethod`'s raw value: "card" or "cash".
        var method: String
        /// A category id, or nil: not sorted. Who set it: `CategorySource`'s raw value.
        var category: String?
        var categorySource: String
        /// The receipt's lines as the engine read them, top to bottom (what is kept instead of a photo).
        var rows: [String]
        /// "code" when the register's QR code was read, else "text".
        var from: String
        /// The bank payment it is joined to; nil while it waits (card) or for cash.
        var paymentID: String?
        /// Payments the person said are not this receipt's: never offered for it again.
        var declined: [String]
        var created: Date
        /// `ReceiptDirection`'s raw value: "out" (a purchase), or "in" (cash received, entered by hand).
        var direction: String = "out"
        /// `ReceiptKind`'s raw value: "receipt" (scanned or picked) or "manual" (typed by hand).
        var kind: String = "receipt"
        /// Cash out: the withdrawal payment or received-cash entry it was paid from; nil: automatic.
        var paidFrom: String? = nil
        /// The shop's name as the engine read it (a later change of the shop teaches the name, `ShopNames`).
        var shopAsRead: String? = nil

        init(_ value: LedgerReceipt) {
            id = value.id
            date = value.date
            time = value.time
            shop = value.shop
            total = value.total
            currency = value.currency
            euroAmount = value.euroAmount
            method = value.method.rawValue
            category = value.category
            categorySource = value.categorySource.rawValue
            rows = value.rows
            from = value.from
            paymentID = value.paymentID
            declined = value.declined
            created = value.created
            direction = value.direction.rawValue
            kind = value.kind.rawValue
            paidFrom = value.paidFrom
            shopAsRead = value.shopAsRead
        }
    }

    /// A shop's name as the person corrected it (brief 33): the shop as read, normalised (`ShopNames.key`), and the
    /// name they typed. The next receipt read the same way shows that name.
    @Model final class ShopName {
        @Attribute(.unique) var read: String
        var name: String
        var saved: Date

        init(read: String, name: String, saved: Date) {
            self.read = read
            self.name = name
            self.saved = saved
        }
    }
    /// A payment name for every bank payment with the engine's merchant key.
    @Model final class PaymentName {
        @Attribute(.unique) var merchant: String
        var name: String

        init(merchant: String, name: String) {
            self.merchant = merchant
            self.name = name
        }
    }

}

nonisolated enum LedgerMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LedgerSchemaV1.self, LedgerSchemaV2.self, LedgerSchemaV3.self, LedgerSchemaV4.self, LedgerSchemaV5.self, LedgerSchemaV6.self, LedgerSchemaV7.self]
    }
    /// Version 2 only adds a model; versions 3–7 add attributes with defaults (3 and 5 also a model): SwiftData moves the
    /// store on by itself, one stage after the other. Version 4's looks are chosen when the store is opened
    /// (`PhoneLedger.giveOwnCategoriesLooks`), since a lightweight stage cannot compute them.
    static var stages: [MigrationStage] {
        [.lightweight(fromVersion: LedgerSchemaV1.self, toVersion: LedgerSchemaV2.self),
         .lightweight(fromVersion: LedgerSchemaV2.self, toVersion: LedgerSchemaV3.self),
         .lightweight(fromVersion: LedgerSchemaV3.self, toVersion: LedgerSchemaV4.self),
         .lightweight(fromVersion: LedgerSchemaV4.self, toVersion: LedgerSchemaV5.self),
         .lightweight(fromVersion: LedgerSchemaV5.self, toVersion: LedgerSchemaV6.self),
         .lightweight(fromVersion: LedgerSchemaV6.self, toVersion: LedgerSchemaV7.self)]
    }
}

/// The version the app opens its store with; tests that make a store use it too, so a new version needs no change there.
typealias LedgerSchemaCurrent = LedgerSchemaV7
typealias StoredAccount = LedgerSchemaV7.Account
typealias StoredPayment = LedgerSchemaV7.Payment
typealias StoredChosen = LedgerSchemaV7.Chosen
typealias StoredRule = LedgerSchemaV7.Rule
typealias StoredLayout = LedgerSchemaV7.Layout
typealias StoredReceipt = LedgerSchemaV7.Receipt
typealias StoredShopName = LedgerSchemaV7.ShopName
typealias StoredPaymentName = LedgerSchemaV7.PaymentName

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
        let schema = Schema(versionedSchema: LedgerSchemaCurrent.self)
        let configuration = ModelConfiguration("Aresium", schema: schema, url: storeURL,
                                               allowsSave: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, migrationPlan: LedgerMigrationPlan.self,
                                           configurations: configuration)
        // One's own categories made before version 4 get their looks now, in the order they were made.
        let opening = ModelContext(container)
        try PhoneLedger.giveOwnCategoriesLooks(in: opening)
        try PhoneLedger.giveCategoriesSides(in: opening)
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
