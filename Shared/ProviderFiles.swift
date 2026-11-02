import Foundation
import os
import UniformTypeIdentifiers

/// Short-lived files offered by NSItemProvider, copied into caller-owned folders before the provider's callback
/// returns. Apps supply their own acceptance and naming policies; the copy and hover state are shared.
nonisolated enum ProviderFiles {
    /// The folder of the drops' copies, in the app's own `tmp` (one folder per file inside, so each keeps its name).
    static func folder(container: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        container.appendingPathComponent("tmp/Dropped", isDirectory: true)
    }

    /// One dragged item as its provider describes it while it hovers: its types (the provider's order, the file's own
    /// first) and the name the source suggests, if any.
    struct Item: Equatable, Sendable {
        let types: [String]
        let name: String?
    }

    /// What the screen says while files the import takes hover: how many, and the file's name when it is one that
    /// names itself.
    struct Hover: Equatable, Sendable {
        let count: Int
        let name: String?
    }

    static func hover(_ items: [Item]) -> Hover? {
        guard !items.isEmpty else { return nil }
        let name = items.count == 1 ? items[0].name?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return Hover(count: items.count, name: name?.isEmpty == false ? name : nil)
    }

    /// Copies a handed-over file into its own new folder in `folder` (so names never collide) and returns the copy.
    static func copy(_ url: URL, name: String, into folder: URL = folder()) throws -> URL {
        guard !name.isEmpty, !name.contains("/"), name != ".", name != ".." else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = folder.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let copy = directory.appendingPathComponent(name)
        do {
            try FileManager.default.copyItem(at: url, to: copy)
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
        return copy
    }

    /// Copies the items of a drop the import takes out of their providers, all started at once while the drop is handed
    /// over (call it from `performDrop`), and hands the copies (in the drop's order) and the number that failed to
    /// `done` on the main actor. The system's file lasts only while its handler runs, so each is copied there.
    @MainActor
    static func copyTaken(_ providers: [NSItemProvider], into folder: URL = folder(),
                          type: (Item) -> String?,
                          name: @escaping @Sendable (String?, String?, String) -> String,
                          done: @escaping @MainActor ([URL], Int) -> Void) {
        let taken = providers.compactMap { provider -> (NSItemProvider, String, String?)? in
            let item = Item(types: provider.registeredTypeIdentifiers, name: provider.suggestedName)
            return type(item).map { (provider, $0, item.name) }
        }
        let copies = OSAllocatedUnfairLock(initialState: [URL?](repeating: nil, count: taken.count))
        let group = DispatchGroup()
        for (index, (provider, type, suggested)) in taken.enumerated() {
            group.enter()
            load(provider, as: type, suggested: suggested, into: folder, name: name) { copy in
                copies.withLock { $0[index] = copy }
                group.leave()
            }
        }
        let count = taken.count
        group.notify(queue: .main) {
            let made = copies.withLock { $0.compactMap { $0 } }
            MainActor.assumeIsolated { done(made, count - made.count) }
        }
    }

    /// One item's file, copied inside the provider's handler (on a queue of the system's). Nonisolated, so the handler
    /// is not taken for the main actor's (Swift would stop the app when the system calls it elsewhere).
    private nonisolated static func load(_ provider: NSItemProvider, as type: String, suggested: String?, into folder: URL,
                                         name: @escaping @Sendable (String?, String?, String) -> String,
                                         finished: @escaping @Sendable (URL?) -> Void) {
        _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
            guard let url else {
                log.error("a dropped file could not be loaded: \(String(describing: error))")
                finished(nil)
                return
            }
            do {
                let name = name(url.lastPathComponent, suggested, type)
                finished(try copy(url, name: name, into: folder))
            } catch {
                log.error("a dropped file could not be copied: \(String(describing: error))")
                finished(nil)
            }
        }
    }

    private static let log = Logger(subsystem: "de.ares-empire.shared", category: "drop")

}
