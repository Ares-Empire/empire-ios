import Foundation

/// A search form's draft that is kept while it has unsaved edits: the flat form's (`SearchDraft`), the thing form's
/// (`ItemSearchDraft`), the monitor's (`PriceSearchDraft`) and the watch form's (`WatchSearchDraft`). Each carries the hunt's name with its search (brief
/// 135), so the saved hunt as a draft is the baseline that tells an edit made elsewhere (another device, renaming in
/// place) from the user's own.
protocol KeptDraft: Codable, Equatable {
    /// The kind of hunt this draft is for (the key of a new form's draft).
    static var kind: HuntKind { get }
    /// What a new form opens with.
    init()
    /// The saved hunt as the form shows it; nil for a hunt of another kind.
    init?(saved hunt: Hunt)
}

extension SearchDraft: @MainActor KeptDraft {
    static var kind: HuntKind { .flat }
    init?(saved hunt: Hunt) {
        guard let search = hunt.search.flat else { return nil }
        self.init(search, name: hunt.name)
    }
}

extension ItemSearchDraft: @MainActor KeptDraft {
    static var kind: HuntKind { .item }
    init?(saved hunt: Hunt) {
        guard let search = hunt.search.item else { return nil }
        self.init(search, name: hunt.name)
    }
}

extension WatchSearchDraft: @MainActor KeptDraft {
    static var kind: HuntKind { .watch }
    init?(saved hunt: Hunt) {
        guard let search = hunt.search.watch else { return nil }
        self.init(search, name: hunt.name)
    }
}

extension PriceSearchDraft: @MainActor KeptDraft {
    static var kind: HuntKind { .price }
    init?(saved hunt: Hunt) {
        guard let search = hunt.search.price else { return nil }
        self.init(search, name: hunt.name)
    }
}

/// One unsaved draft per account and hunt, plus a new draft for each kind. The saved hunt as a draft is the baseline:
/// once it changes (an edit on another device, a rename), the kept draft is dropped.
struct KeptSearchDraft {
    private struct Entry<Draft: Codable>: Codable {
        let baseline: Draft?
        let draft: Draft
    }
    private static let prefix = "arestemis.searchDraft."
    let defaults: UserDefaults

    private func key(account: String, huntID: Int?, kind: HuntKind) -> String {
        Self.prefix + account + "." + (huntID.map { "hunt.\($0)" } ?? "new.\(kind.rawValue)")
    }

    /// Keeps `draft` while it differs from what the form opens with (the saved hunt, or an empty form); otherwise
    /// forgets it.
    func keep<Draft: KeptDraft>(_ draft: Draft, saved: Draft?, account: String, huntID: Int? = nil) {
        let key = key(account: account, huntID: huntID, kind: Draft.kind)
        guard draft != (saved ?? Draft()) else { defaults.removeObject(forKey: key); return }
        defaults.set(try? JSONEncoder().encode(Entry(baseline: saved, draft: draft)), forKey: key)
    }

    /// The kept draft while the hunt is still as it was when the draft was edited; else the saved hunt, or an empty form
    /// (and the kept one goes). An edited flat or thing hunt's draft kept by a build from before brief 135 had the
    /// search alone as its baseline, and goes once.
    func restore<Draft: KeptDraft>(_ type: Draft.Type = Draft.self, saved: Draft?, account: String,
                                   huntID: Int? = nil) -> Draft {
        let key = key(account: account, huntID: huntID, kind: Draft.kind)
        if let data = defaults.data(forKey: key),
           let entry = try? JSONDecoder().decode(Entry<Draft>.self, from: data), entry.baseline == saved {
            return entry.draft
        }
        defaults.removeObject(forKey: key)
        return saved ?? Draft()
    }

    func drop(account: String, huntID: Int? = nil, kind: HuntKind = .flat) {
        defaults.removeObject(forKey: key(account: account, huntID: huntID, kind: kind))
    }
    func clear() {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) { defaults.removeObject(forKey: key) }
    }
}
