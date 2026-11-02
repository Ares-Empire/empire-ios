import Foundation
import Observation

@MainActor @Observable
final class DropRecentFolders {
    private(set) var targets: [Target] = []
    private(set) var lastBySource: [DropSource: Target] = [:]
    private let defaults: UserDefaults?
    private let key = "aresus.drop.recent-folders.v1"

    private struct Saved: Codable {
        var targets: [Target]
        var lastBySource: [DropSource: Target]
    }

    /// nil defaults keeps sample mode entirely in memory.
    init(defaults: UserDefaults?, legacyDefaults: UserDefaults? = nil) {
        self.defaults = defaults
        if let defaults, let legacyDefaults, !defaults.bool(forKey: key + ".migrated") {
            if defaults.data(forKey: key) == nil, let old = legacyDefaults.data(forKey: key) {
                defaults.set(old, forKey: key)
            }
            defaults.set(true, forKey: key + ".migrated")
        }
        reload()
    }

    func reload() {
        guard let defaults else { return }
        targets = []; lastBySource = [:]
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Saved.self, from: data) {
            targets = Array(saved.targets.prefix(8))
            lastBySource = saved.lastBySource
        }
    }

    func use(_ target: Target, source: DropSource) {
        reload()
        targets.removeAll { $0 == target }
        targets.insert(target, at: 0)
        targets = Array(targets.prefix(8))
        lastBySource[source] = target
        if let data = try? JSONEncoder().encode(Saved(targets: targets, lastBySource: lastBySource)) {
            defaults?.set(data, forKey: key)
        }
    }

    func clear() {
        targets = []
        lastBySource = [:]
        defaults?.removeObject(forKey: key)
    }
}
