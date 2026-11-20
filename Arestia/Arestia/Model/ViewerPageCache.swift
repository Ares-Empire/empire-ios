import CryptoKit
import Foundation
import os

/// The one copy of flatd's private page in the app container. The serial queue orders reads, writes and Forget.
nonisolated final class ViewerPageCache: Sendable {
    struct Kept: Sendable {
        let html: Data
        let etag: String?
        let sha256: String
    }

    private struct Metadata: Codable {
        let pairing: UUID
        let pin: FlatdPin
        let etag: String?
        let sha256: String
        let byteCount: Int
        let savedAt: Date

        enum CodingKeys: String, CodingKey { case pairing, pin, etag, sha256, byteCount, savedAt }

        func encode(to encoder: Encoder) throws {
            var values = encoder.container(keyedBy: CodingKeys.self)
            try values.encode(pairing, forKey: .pairing)
            try values.encode(pin, forKey: .pin)
            try values.encode(etag, forKey: .etag)
            try values.encode(sha256, forKey: .sha256)
            try values.encode(byteCount, forKey: .byteCount)
            try values.encode(savedAt, forKey: .savedAt)
        }
    }

    static let live = ViewerPageCache(folder: URL.applicationSupportDirectory.appending(path: "ArestiaViewer"))
    static let maxBytes = 32 * 1024 * 1024
    private static let writingOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "viewer")

    private let folder: URL
    private let queue = DispatchQueue(label: "de.ares-empire.arestia.viewer-cache", qos: .userInitiated)
    private let write: @Sendable (Data, URL, Data.WritingOptions) throws -> Void

    init(folder: URL, write: @escaping @Sendable (Data, URL, Data.WritingOptions) throws -> Void = {
        try $0.write(to: $1, options: $2)
    }) {
        self.folder = folder
        self.write = write
    }

    nonisolated(nonsending) func page(pairing: UUID, pin: FlatdPin) async -> Kept? {
        await work { [self] in
            let htmlURL = file(pairing, "html"), metaURL = file(pairing, "json")
            let kept = read(htmlURL, metaURL, pairing: pairing, pin: pin)
            let names = kept == nil ? [] : [htmlURL.lastPathComponent, metaURL.lastPathComponent]
            return purge(except: names) ? kept : nil
        }
    }

    /// Returns the hash for the coordinator's comparison even if writing failed. An oversized page cannot match a copy.
    @discardableResult
    nonisolated(nonsending) func save(_ html: Data, etag: String?, pairing: UUID, pin: FlatdPin) async -> String? {
        await work { [self] in
            guard html.count <= Self.maxBytes else {
                _ = purge(except: [])
                return nil
            }
            let sha256 = Self.hash(html)
            let htmlURL = file(pairing, "html"), metaURL = file(pairing, "json")
            var names: [String] = []
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                var directory = folder
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try directory.setResourceValues(values)
                let meta = Metadata(pairing: pairing, pin: pin, etag: etag, sha256: sha256,
                                    byteCount: html.count, savedAt: Date())
                try write(html, htmlURL, Self.writingOptions)
                try write(JSONEncoder().encode(meta), metaURL, Self.writingOptions)
                names = [htmlURL.lastPathComponent, metaURL.lastPathComponent]
            } catch {
                Self.log.error("could not keep the 3D page")
            }
            _ = purge(except: names)
            return sha256
        }
    }

    /// Submit the deletion before returning to Forget, so a later pairing's work queues behind it.
    func removeAll() {
        queue.async { [folder] in
            do {
                try FileManager.default.removeItem(at: folder)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                // Already gone.
            } catch {
                Self.log.error("could not remove the kept 3D page folder")
            }
        }
    }

    /// Submission stays on the caller's actor until the work is queued. Cancelled work waiting in the queue is skipped;
    /// work already writing its two files finishes before the next operation.
    private nonisolated(nonsending) func work<Value: Sendable>(
        _ operation: @escaping @Sendable () -> Value?
    ) async -> Value? {
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                queue.async {
                    continuation.resume(returning: cancelled.withLock { $0 } ? nil : operation())
                }
            }
        } onCancel: {
            cancelled.withLock { $0 = true }
        }
    }

    private func file(_ pairing: UUID, _ ext: String) -> URL {
        folder.appending(path: pairing.uuidString).appendingPathExtension(ext)
    }

    private func read(_ htmlURL: URL, _ metaURL: URL, pairing: UUID, pin: FlatdPin) -> Kept? {
        let files = FileManager.default
        guard files.fileExists(atPath: metaURL.path) || files.fileExists(atPath: htmlURL.path) else { return nil }
        do {
            let meta = try JSONDecoder().decode(Metadata.self, from: Data(contentsOf: metaURL))
            guard meta.pairing == pairing, meta.pin == pin else { return nil }
            let size = try htmlURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard size == meta.byteCount, meta.byteCount <= Self.maxBytes else {
                Self.log.error("the kept 3D page has the wrong size")
                return nil
            }
            let html = try Data(contentsOf: htmlURL)
            guard html.count == meta.byteCount, Self.hash(html) == meta.sha256 else {
                Self.log.error("the kept 3D page failed its integrity check")
                return nil
            }
            return Kept(html: html, etag: meta.etag, sha256: meta.sha256)
        } catch {
            Self.log.error("could not read the kept 3D page")
            return nil
        }
    }

    private func purge(except names: [String]) -> Bool {
        let files = FileManager.default
        guard files.fileExists(atPath: folder.path) else { return true }
        do {
            let contents = try files.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            var purged = true
            for entry in contents where !names.contains(entry.lastPathComponent) {
                do {
                    try files.removeItem(at: entry)
                } catch {
                    Self.log.error("could not remove a kept 3D page file")
                    purged = false
                }
            }
            return purged
        } catch {
            Self.log.error("could not list kept 3D page files")
            return false
        }
    }

    private static func hash(_ html: Data) -> String {
        SHA256.hash(data: html).map { String(format: "%02x", $0) }.joined()
    }
}
