import Foundation
import os
import UniformTypeIdentifiers

/// Files dropped on the main screen (brief 204): which items a drop takes, what their copies are called and where they
/// go. A drop comes in the way a shared file does (ContentView's `receiveFromOutside`, then
/// `ImportStore.receive(_:source: .shared)`, held while the lock is on): Aresium copies each file out of the drop at
/// once (the system's own copy lasts only while it is handed over), and the reading removes the copies
/// (`ImportFileReader.removeSharedCopy`); copies a launch left behind go at the next one (`clearInbox`).
nonisolated enum FileDrop {
    /// The folder of the drops' copies, in the app's own `tmp` (one folder per file inside, so each keeps its name).
    static func folder(container: URL = URL(fileURLWithPath: NSHomeDirectory())) -> URL {
        container.appendingPathComponent("tmp/Dropped", isDirectory: true)
    }

    /// Whether the main screen takes drops now: phone mode's first screen and dashboard pages, not the tour, the store
    /// while it opens or did not open, server mode, or behind the lock. (Sheets and the lock screen are views of their
    /// own, which take no drops.)
    static func targetOn(screen: MainScreen, phoneMode: Bool, locked: Bool) -> Bool {
        phoneMode && !locked && (screen == .firstScreen || screen == .dashboard)
    }

    /// One dragged item as its provider describes it while it hovers: its types (the provider's order, the file's own
    /// first) and the name the source suggests, if any.
    struct Item: Equatable, Sendable {
        let types: [String]
        let name: String?
    }

    /// The type to read an item as, when the import takes it: the first of its types whose own file extensions are one
    /// the import reads (`ImportFileReader.phoneExtensions`, the file picker's `PhoneImportTypes.all`; a drop is chosen
    /// by hand, as a pick is, so `.txt` too), as the reader goes by extension. So a CSV, CAMT XML, MT940, `.txt` or
    /// `.zip` file fits, while a type that merely conforms to text or XML (Markdown, a property list, an SVG) does not,
    /// nor does an export's `.json` (restoring stays in Settings). Plain text only with a name: a piece of text dragged
    /// from a page or a note is plain text too, but no file. An item whose name ends in an extension the import reads
    /// fits as well, read as its own (first) type.
    static func importType(of item: Item) -> String? {
        let named = item.name.map { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? false
        if let type = item.types.first(where: { type in
            let extensions = importExtensions(of: type)
            return !extensions.isEmpty && (named || extensions.contains { $0 != "txt" && $0 != "text" })
        }) { return type }
        if let name = item.name, ImportFileReader.phoneExtensions.contains(fileExtension(name)) { return item.types.first }
        return nil
    }

    /// The items of a drop the import takes (the others are left out, as the file picker leaves out what it cannot read).
    static func taken(_ items: [Item]) -> [Item] { items.filter { importType(of: $0) != nil } }

    /// What hovering shows: letting go imports (some items fit) or the system's "not allowed" (none does).
    static func accepts(_ items: [Item]) -> Bool { !taken(items).isEmpty }

    /// What the screen says while files the import takes hover: how many, and the file's name when it is one that
    /// names itself.
    struct Hover: Equatable, Sendable {
        let count: Int
        let name: String?
    }

    /// The hover's words for these items; nil when the import takes none of them (the system's "not allowed").
    static func hover(_ items: [Item]) -> Hover? {
        let taken = taken(items)
        guard !taken.isEmpty else { return nil }
        let name = taken.count == 1 ? taken[0].name?.trimmingCharacters(in: .whitespacesAndNewlines) : nil
        return Hover(count: taken.count, name: name?.isEmpty == false ? name : nil)
    }

    /// The copy's file name: the name the source suggests (the file's own name; Files suggests it with its extension) or
    /// else the handed-over file's (the system names its copy of a CSV "comma-separated values.csv"), with an extension the import reads added when it has none: the handed-over file's,
    /// or the type's. "Dropped file" when nothing names it.
    static func copyName(loaded: String?, suggested: String?, type: String) -> String {
        func clean(_ name: String?) -> String? {
            let name = name?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "/", with: "-")
            return name?.isEmpty == false ? name : nil
        }
        let base = clean(suggested) ?? clean(loaded) ?? String(localized: "Dropped file")
        if ImportFileReader.phoneExtensions.contains(fileExtension(base)) { return base }
        let loadedExtension = loaded.map(fileExtension).flatMap { ImportFileReader.phoneExtensions.contains($0) ? $0 : nil }
        guard let ext = loadedExtension ?? importExtensions(of: type).first else { return base }
        return base + "." + ext
    }

    /// Copies a handed-over file into its own new folder in `folder` (so names never collide) and returns the copy.
    static func copy(_ url: URL, name: String, into folder: URL = folder()) throws -> URL {
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
                          done: @escaping @MainActor ([URL], Int) -> Void) {
        let taken = providers.compactMap { provider -> (NSItemProvider, String, String?)? in
            let item = Item(types: provider.registeredTypeIdentifiers, name: provider.suggestedName)
            return importType(of: item).map { (provider, $0, item.name) }
        }
        let copies = OSAllocatedUnfairLock(initialState: [URL?](repeating: nil, count: taken.count))
        let group = DispatchGroup()
        for (index, (provider, type, suggested)) in taken.enumerated() {
            group.enter()
            load(provider, as: type, suggested: suggested, into: folder) { copy in
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
                                         finished: @escaping @Sendable (URL?) -> Void) {
        _ = provider.loadFileRepresentation(forTypeIdentifier: type) { url, error in
            guard let url else {
                log.error("a dropped file could not be loaded: \(String(describing: error))")
                finished(nil)
                return
            }
            do {
                let name = copyName(loaded: url.lastPathComponent, suggested: suggested, type: type)
                finished(try copy(url, name: name, into: folder))
            } catch {
                log.error("a dropped file could not be copied: \(String(describing: error))")
                finished(nil)
            }
        }
    }

    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "drop")

    /// The extensions of a type the import reads (`.csv` for CSV, `.sta`/`.mt940` for MT940, `.txt` for plain text).
    private static func importExtensions(of identifier: String) -> [String] {
        (UTType(identifier)?.tags[.filenameExtension] ?? []).map { $0.lowercased() }
            .filter { ImportFileReader.phoneExtensions.contains($0) }
    }

    private static func fileExtension(_ name: String) -> String { (name as NSString).pathExtension.lowercased() }
}
