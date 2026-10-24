import Foundation

nonisolated enum ImportFileSource: Sendable { case picker, shared }

enum ImportFileError: LocalizedError {
    case noExports
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .noExports: String(localized: "Pick a VR Bank or PayPal .csv (or CAMT .xml) export.")
        case let .tooLarge(name): String(localized: "\(name) is too large (max 25 MB before JSON encoding)")
        }
    }
}

enum ImportFileReader {
    nonisolated static let maximumBytes = 25 * 1024 * 1024

    nonisolated static func read(_ urls: [URL], source: ImportFileSource = .picker,
                                 container: URL = URL(fileURLWithPath: NSHomeDirectory())) throws -> [ImportFile] {
        defer {
            if source == .shared { urls.forEach { removeSharedCopy($0, container: container) } }
        }
        let files = try urls.filter {
            $0.isFileURL && ["csv", "xml"].contains($0.pathExtension.lowercased())
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
            return ImportFile(name: url.lastPathComponent, content: String(decoding: data, as: UTF8.self))
        }
        guard !files.isEmpty else { throw ImportFileError.noExports }
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
