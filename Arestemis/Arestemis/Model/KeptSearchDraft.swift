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

    /// Keeps `draft` while it differs from what the form opens with (`fresh`); otherwise forgets it.
    private func keep<Draft: Codable & Equatable, Baseline: Codable>(_ draft: Draft, fresh: Draft, baseline: Baseline?,
                                                                       key: String) {
        guard draft != fresh else { defaults.removeObject(forKey: key); return }
        defaults.set(try? JSONEncoder().encode(Entry(baseline: baseline, draft: draft)), forKey: key)
    }

    /// The kept draft while the hunt's search is still the one it was edited from; else `fresh` (and the kept one goes).
    private func restore<Draft: Codable, Baseline: Codable & Equatable>(baseline: Baseline?, fresh: Draft,
                                                                         key: String) -> Draft {
        if let data = defaults.data(forKey: key),
           let entry = try? JSONDecoder().decode(Entry<Draft, Baseline>.self, from: data), entry.baseline == baseline {
            return entry.draft
        }
        defaults.removeObject(forKey: key)
        return fresh
    }

    func keep(_ draft: SearchDraft, baseline: Search?, account: String, huntID: Int? = nil) {
        keep(draft, fresh: baseline.map { SearchDraft($0) } ?? SearchDraft(), baseline: baseline,
             key: key(account: account, huntID: huntID, kind: .flat))
    }
    func restore(for search: Search?, account: String, huntID: Int? = nil) -> SearchDraft {
        restore(baseline: search, fresh: search.map { SearchDraft($0) } ?? SearchDraft(),
                key: key(account: account, huntID: huntID, kind: .flat))
    }
    func keep(_ draft: ItemSearchDraft, baseline: ItemSearch?, account: String, huntID: Int? = nil) {
        keep(draft, fresh: baseline.map { ItemSearchDraft($0) } ?? ItemSearchDraft(), baseline: baseline,
             key: key(account: account, huntID: huntID, kind: .item))
    }
    func restoreItem(for search: ItemSearch?, account: String, huntID: Int? = nil) -> ItemSearchDraft {
        restore(baseline: search, fresh: search.map { ItemSearchDraft($0) } ?? ItemSearchDraft(),
                key: key(account: account, huntID: huntID, kind: .item))
    }
    /// A watch's draft includes its name, so its baseline is the saved watch as a draft (search and name).
    func keep(_ draft: WatchSearchDraft, baseline: WatchSearchDraft?, account: String, huntID: Int? = nil) {
        keep(draft, fresh: baseline ?? WatchSearchDraft(), baseline: baseline,
             key: key(account: account, huntID: huntID, kind: .watch))
    }
    func restoreWatch(for saved: WatchSearchDraft?, account: String, huntID: Int? = nil) -> WatchSearchDraft {
        restore(baseline: saved, fresh: saved ?? WatchSearchDraft(), key: key(account: account, huntID: huntID, kind: .watch))
    }
    func drop(account: String, huntID: Int? = nil, kind: HuntKind = .flat) {
        defaults.removeObject(forKey: key(account: account, huntID: huntID, kind: kind))
    }
    func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) { defaults.removeObject(forKey: key) }
    }
}
