import Darwin
import Foundation

/// A short filesystem lock protects read/change/write transactions across the app and extension. Separate operation
/// leases cover an asynchronous POST; a second process cannot create the same queued drop while that lease is held.
nonisolated final class DropLease {
    private let descriptor: Int32

    init(url: URL, wait: Bool) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        guard flock(descriptor, LOCK_EX | (wait ? 0 : LOCK_NB)) == 0 else {
            close(descriptor)
            throw CocoaError(.fileLocking)
        }
    }

    deinit { flock(descriptor, LOCK_UN); close(descriptor) }
}

nonisolated struct DropJournal {
    let directory: URL
    private var locks: URL { directory.deletingLastPathComponent().appendingPathComponent(directory.lastPathComponent + "-locks") }

    func locked<T>(_ body: () throws -> T) throws -> T {
        let lease = try DropLease(url: locks.appendingPathComponent("journal"), wait: true)
        return try withExtendedLifetime(lease, body)
    }

    func claim(_ id: UUID) -> DropLease? {
        try? DropLease(url: locks.appendingPathComponent(id.uuidString), wait: false)
    }

    func read(_ id: UUID) throws -> DropOutboxItem? {
        let url = record(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let item = try JSONDecoder().decode(DropOutboxItem.self, from: Data(contentsOf: url))
        guard item.id == id, item.localFile == id.uuidString + ".file" else { throw DropLocalError.unreadableFile }
        return item
    }

    func save(_ item: DropOutboxItem) throws {
        try JSONEncoder().encode(item).write(to: record(item.id), options: .atomic)
    }

    func record(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }

    /// Copy files before records, then retire the old folder only after every copy is durable. On interruption the
    /// next launch resumes. Existing group records win (they may have progressed since an earlier partial migration).
    /// No orphan cleanup runs during reload: another process may still be copying an item before saving its record.
    func migrate(from legacy: URL) throws {
        guard legacy.standardizedFileURL != directory.standardizedFileURL else { return }
        try locked {
            let fm = FileManager.default
            guard fm.fileExists(atPath: legacy.path) else { return }
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            let urls = try fm.contentsOfDirectory(at: legacy, includingPropertiesForKeys: nil)
            for source in urls.sorted(by: { ($0.pathExtension == "json" ? 1 : 0) < ($1.pathExtension == "json" ? 1 : 0) }) {
                let destination = directory.appendingPathComponent(source.lastPathComponent)
                if !fm.fileExists(atPath: destination.path) {
                    let staging = directory.appendingPathComponent(UUID().uuidString + ".migration")
                    if source.pathExtension == "json" {
                        try fm.moveItem(at: source, to: destination)
                    } else {
                        try fm.copyItem(at: source, to: staging)
                        try fm.moveItem(at: staging, to: destination)
                    }
                } else if source.pathExtension == "json" {
                    try fm.removeItem(at: source)
                }
            }
            try fm.removeItem(at: legacy)
        }
    }
}
