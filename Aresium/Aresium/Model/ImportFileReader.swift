import Foundation

nonisolated enum ImportFileSource: Sendable {
    /// Picked in the file picker: the person's own file, read where it is and never touched.
    case picker
    /// A copy made for Aresium, removed once read: iOS's copy of a file shared into Aresium (`inboxes`) or Aresium's
    /// copy of a dropped file (`FileDrop.folder`, brief 204).
    case shared
}

enum ImportFileError: LocalizedError {
    case noExports
    case noBankFiles
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .noExports: String(localized: "Pick a VR Bank or PayPal .csv (or CAMT .xml) export.")
        case .noBankFiles: String(localized: "Pick your bank's export: a .csv, CAMT .xml or MT940 file.")
        case let .tooLarge(name): String(localized: "\(name) is too large (max 25 MB before JSON encoding)")
        }
    }
}

enum ImportFileReader {
    nonisolated static let maximumBytes = 25 * 1024 * 1024
    /// Server mode: bank and PayPal CSVs and CAMT XML, as the server reads them.
    nonisolated static let serverExtensions: Set<String> = ["csv", "xml"]
    /// Phone mode: also MT940 (`.sta`, `.mt940`, `.txt`) and ZIP, which the engine refuses with "unzip it first".
    nonisolated static let phoneExtensions: Set<String> = ["csv", "xml", "sta", "mt940", "txt", "zip"]

    nonisolated static func read(_ urls: [URL], source: ImportFileSource = .picker,
                                 extensions: Set<String> = serverExtensions,
                                 container: URL = URL(fileURLWithPath: NSHomeDirectory())) throws -> [ImportFile] {
        defer {
            if source == .shared { urls.forEach { removeSharedCopy($0, container: container) } }
        }
        let files = try urls.filter {
            $0.isFileURL && extensions.contains($0.pathExtension.lowercased())
        }.map { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            // Read at most one byte beyond the limit, even if the file grows after it was picked.
            var data = Data()
            while let chunk = try handle.read(upToCount: min(64 * 1024, maximumBytes + 1 - data.count)), !chunk.isEmpty {
                data.append(chunk)
                guard data.count <= maximumBytes else { throw ImportFileError.tooLarge(url.lastPathComponent) }
            }
            return ImportFile(name: url.lastPathComponent, data: data)
        }
        guard !files.isEmpty else {
            throw extensions == serverExtensions ? ImportFileError.noExports : ImportFileError.noBankFiles
        }
        return files
    }
    /// Where iOS puts its copy of a file shared into Aresium (the share sheet, Files' Open With, AirDrop): since
    /// iOS 13, in an app with scenes, `tmp/<bundle id>-Inbox` (seen on the simulator, brief 204: the share sheet's
    /// copies were never removed, as only the older `Documents/Inbox` was looked at); `Documents/Inbox` as before.
    nonisolated static func inboxes(container: URL, bundleID: String? = Bundle.main.bundleIdentifier) -> [URL] {
        [container.appendingPathComponent("tmp/\(bundleID ?? "de.ares-empire.aresium")-Inbox", isDirectory: true),
         container.appendingPathComponent("Documents/Inbox", isDirectory: true)]
    }

    /// Removes a copy made for Aresium: a file in an Inbox, or a dropped file's own folder in `FileDrop.folder`.
    /// Anything else (a picked original, a file outside the app's container, a link pointing out of it) stays.
    nonisolated static func removeSharedCopy(_ url: URL, container: URL) {
        guard url.isFileURL else { return }
        let resolve = { (url: URL) in url.resolvingSymlinksInPath().standardizedFileURL.path }
        let path = resolve(url)
        guard path.hasPrefix(resolve(container) + "/") else { return }
        if inboxes(container: container).contains(where: { path.hasPrefix(resolve($0) + "/") }) {
            try? FileManager.default.removeItem(at: url)
            return
        }
        let dropped = resolve(FileDrop.folder(container: container))
        guard path.hasPrefix(dropped + "/") else { return }
        // The copy's own folder (`FileDrop.copy`): the first component under the drops' folder.
        guard let folder = path.dropFirst(dropped.count + 1).split(separator: "/").first, !folder.isEmpty else {
            return
        }
        try? FileManager.default.removeItem(at: FileDrop.folder(container: container)
            .appendingPathComponent(String(folder)))
    }

    /// At launch: copies left from an earlier launch go (shared files never read, drops held behind the lock when the
    /// app ended), except the files this launch was opened with.
    nonisolated static func clearInbox(container: URL = URL(fileURLWithPath: NSHomeDirectory()), excluding: [URL] = []) {
        let protected = Set(excluding.map { $0.resolvingSymlinksInPath().standardizedFileURL })
        for folder in inboxes(container: container) + [FileDrop.folder(container: container)] {
            let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))
                ?? []
            files.filter { !protected.contains($0.resolvingSymlinksInPath().standardizedFileURL) }
                .forEach { removeSharedCopy($0, container: container) }
        }
    }

}
