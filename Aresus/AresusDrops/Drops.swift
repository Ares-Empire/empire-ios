import Foundation

// Drops version 1, aresus/docs/API.md. Day-only receipt dates stay strings; timestamps use AresusJSON.
nonisolated enum DropRoot: String, Codable, CaseIterable, Sendable { case documents, downloads }
nonisolated enum DropKind: String, Codable, Sendable { case file, receipt }
nonisolated enum DropState: String, Codable, CaseIterable, Sendable { case uploading, waiting, landed, failed, cancelled }

nonisolated struct Target: Codable, Hashable, Sendable {
    var root: DropRoot
    var folder: String
    var newFolder: String?
    enum CodingKeys: String, CodingKey { case root, folder; case newFolder = "new_folder" }
    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(root, forKey: .root)
        try box.encode(folder, forKey: .folder)
        try box.encode(newFolder, forKey: .newFolder)
    }
}

nonisolated struct Receipt: Codable, Equatable, Sendable {
    var date: String
    var shop: String
    var item: String
    var totalCents: Int
    var tax: Bool
    var flat: Bool
    var keep: Bool
    var warrantyUntil: String?
    enum CodingKeys: String, CodingKey {
        case date, shop, item, tax, flat, keep
        case totalCents = "total_cents", warrantyUntil = "warranty_until"
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(date, forKey: .date)
        try box.encode(shop, forKey: .shop)
        try box.encode(item, forKey: .item)
        try box.encode(totalCents, forKey: .totalCents)
        try box.encode(tax, forKey: .tax)
        try box.encode(flat, forKey: .flat)
        try box.encode(keep, forKey: .keep)
        try box.encode(warrantyUntil, forKey: .warrantyUntil)
    }
}

nonisolated struct NewDrop: Codable, Equatable, Sendable {
    var kind: DropKind
    var name: String
    var size: Int64
    var sha256: String
    var target: Target?
    var receipt: Receipt?

    enum CodingKeys: String, CodingKey { case kind, name, size, sha256, target, receipt }
    // The contract sends explicit nulls, including file drops' receipt and a fallback target.
    func encode(to encoder: Encoder) throws {
        var box = encoder.container(keyedBy: CodingKeys.self)
        try box.encode(kind, forKey: .kind)
        try box.encode(name, forKey: .name)
        try box.encode(size, forKey: .size)
        try box.encode(sha256, forKey: .sha256)
        try box.encode(target, forKey: .target)
        try box.encode(receipt, forKey: .receipt)
    }
}

nonisolated struct Drop: Codable, Equatable, Identifiable, Sendable {
    var id: Int
    var kind: DropKind
    var name: String
    var size: Int64
    var target: Target?
    var state: DropState
    var landed: String?
    var fallback: Bool
    var note: String?
    var created: Date
    var updated: Date
}

nonisolated struct FolderList: Codable, Equatable, Sendable {
    var updated: Date?
    var documents: [String]
    var downloads: [String]
    var fallback: String
    var fallbackCount: Int
    var receipts: String?
    enum CodingKeys: String, CodingKey {
        case updated, documents, downloads, fallback, receipts
        case fallbackCount = "fallback_count"
    }
}

nonisolated struct DropsAnswer: Codable, Sendable { var drops: [Drop] }
