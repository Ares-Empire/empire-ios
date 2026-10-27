import Foundation

nonisolated enum ImportFileSource: Sendable { case picker, shared }

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
    nonisolated static func removeSharedCopy(_ url: URL, container: URL) {
        guard url.isFileURL else { return }
        let inbox = container.appendingPathComponent("Documents/Inbox").resolvingSymlinksInPath().standardizedFileURL
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let root = container.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        guard path.hasPrefix(root), path.hasPrefix(inbox.path + "/") else { return }
        try? FileManager.default.removeItem(at: url)
    }

    nonisolated static func clearInbox(container: URL = URL(fileURLWithPath: NSHomeDirectory()), excluding: [URL] = []) {
        let inbox = container.appendingPathComponent("Documents/Inbox")
        let files = (try? FileManager.default.contentsOfDirectory(at: inbox, includingPropertiesForKeys: nil)) ?? []
        let protected = Set(excluding.map { $0.resolvingSymlinksInPath().standardizedFileURL })
        files.filter { !protected.contains($0.resolvingSymlinksInPath().standardizedFileURL) }
            .forEach { removeSharedCopy($0, container: container) }
    }

}
