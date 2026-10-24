import Foundation

/// The widget's last status, as one atomic file in the App Group every Empire app shares (Aresium's snapshot store,
/// `Aresium/AresiumShared/WidgetSnapshotStore.swift`). The app and the widget both write it; the file name says whose
/// it is, because the group is shared with the other Empire apps.
nonisolated struct WidgetStatusStore: Sendable {
    static let fileName = "aresus-widget-status.json"
    private let directory: URL?

    /// `directory` nil: no App Group (the entitlement is missing); reading finds nothing, saving fails.
    init(directory: URL?) {
        self.directory = directory
    }

    enum ReadResult: Equatable, Sendable {
        case missing, failed, status(WidgetStatus)

        var status: WidgetStatus? {
            if case .status(let status) = self { status } else { nil }
        }
    }

    func read() -> ReadResult {
        guard directory != nil else { return .missing }
        do {
            let data = try Data(contentsOf: file())
            return .status(try JSONDecoder().decode(WidgetStatus.self, from: data))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .failed            // unreadable or from an older version: treated as nothing saved
        }
    }

    /// Readable once the phone has been unlocked after a restart, so the widget can show it on the lock screen.
    func save(_ status: WidgetStatus) throws {
        try JSONEncoder().encode(status).write(to: file(), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete() throws {
        let url = try file()
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    private func file() throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        return directory.appendingPathComponent(Self.fileName)
    }
}

extension WidgetStatusStore {
    /// The real file in the shared App Group.
    @MainActor static var appGroup: WidgetStatusStore {
        WidgetStatusStore(directory: FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: EmpireShared.appGroup))
    }
}
