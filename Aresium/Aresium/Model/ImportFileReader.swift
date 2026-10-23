import Foundation

enum ImportFileError: LocalizedError {
    case noExports
    case tooLarge(String)

    var errorDescription: String? {
        switch self {
        case .noExports: "Pick a VR Bank or PayPal .csv (or CAMT .xml) export."
        case let .tooLarge(name): "\(name) is too large (max 20 MB)"
        }
    }
}

enum ImportFileReader {
    nonisolated static let maximumBytes = 20 * 1024 * 1024

    nonisolated static func read(_ urls: [URL]) throws -> [ImportFile] {
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
}
