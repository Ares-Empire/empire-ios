import Foundation

/// One unsaved draft per account and hunt, plus a new draft for each kind. Baselines detect edits on another device.
struct KeptSearchDraft {
    private struct Entry<Draft: Codable, Baseline: Codable>: Codable {
        let baseline: Baseline?
        let draft: Draft
    }
    private static let prefix = "arestemis.searchDraft."
    let defaults: UserDefaults

    private func key(account: String, huntID: Int?, kind: HuntKind) -> String {
        Self.prefix + account + "." + (huntID.map { "hunt.\($0)" } ?? "new.\(kind.rawValue)")
    }
    func keep(_ draft: SearchDraft, baseline: Search?, account: String, huntID: Int? = nil) {
        let key = key(account: account, huntID: huntID, kind: .flat)
        guard draft != baseline.map({ SearchDraft($0) }) ?? SearchDraft() else { defaults.removeObject(forKey: key); return }
        defaults.set(try? JSONEncoder().encode(Entry(baseline: baseline, draft: draft)), forKey: key)
    }
    func restore(for search: Search?, account: String, huntID: Int? = nil) -> SearchDraft {
        let key = key(account: account, huntID: huntID, kind: .flat)
        if let data = defaults.data(forKey: key),
           let entry = try? JSONDecoder().decode(Entry<SearchDraft, Search>.self, from: data), entry.baseline == search {
            return entry.draft
        }
        defaults.removeObject(forKey: key)
        return search.map { SearchDraft($0) } ?? SearchDraft()
    }
    func keep(_ draft: ItemSearchDraft, baseline: ItemSearch?, account: String, huntID: Int? = nil) {
        let key = key(account: account, huntID: huntID, kind: .item)
        guard draft != baseline.map({ ItemSearchDraft($0) }) ?? ItemSearchDraft() else { defaults.removeObject(forKey: key); return }
        defaults.set(try? JSONEncoder().encode(Entry(baseline: baseline, draft: draft)), forKey: key)
    }
    func restoreItem(for search: ItemSearch?, account: String, huntID: Int? = nil) -> ItemSearchDraft {
        let key = key(account: account, huntID: huntID, kind: .item)
        if let data = defaults.data(forKey: key),
           let entry = try? JSONDecoder().decode(Entry<ItemSearchDraft, ItemSearch>.self, from: data), entry.baseline == search {
            return entry.draft
        }
        defaults.removeObject(forKey: key)
        return search.map { ItemSearchDraft($0) } ?? ItemSearchDraft()
    }
    func drop(account: String, huntID: Int? = nil, kind: HuntKind = .flat) {
        defaults.removeObject(forKey: key(account: account, huntID: huntID, kind: kind))
    }
    func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) { defaults.removeObject(forKey: key) }
    }
}
