import Foundation

/// Account-scoped edits in the app's own defaults. The baseline detects edits made on another device.
struct KeptSearchDraft {
    private struct Entry: Codable {
        let baseline: Search?
        let draft: SearchDraft
    }

    private static let prefix = "arestemis.searchDraft."
    let defaults: UserDefaults

    func keep(_ draft: SearchDraft, baseline: Search?, account: String) {
        let key = Self.prefix + account
        guard draft != (baseline.map({ SearchDraft($0) }) ?? SearchDraft()) else {
            defaults.removeObject(forKey: key)
            return
        }
        if let data = try? JSONEncoder().encode(Entry(baseline: baseline, draft: draft)) {
            defaults.set(data, forKey: key)
        }
    }

    func restore(for search: Search?, account: String) -> SearchDraft {
        let key = Self.prefix + account
        if let data = defaults.data(forKey: key),
           let entry = try? JSONDecoder().decode(Entry.self, from: data), entry.baseline == search {
            return entry.draft
        }
        drop(account: account)
        return search.map { SearchDraft($0) } ?? SearchDraft()
    }

    func drop(account: String) { defaults.removeObject(forKey: Self.prefix + account) }

    /// The session has already forgotten its account id when it calls the app's reset hook.
    func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
