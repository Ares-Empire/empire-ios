import Foundation

/// Atomic files in the App Group; widgets read them without ever contacting the server.
nonisolated struct WidgetSnapshotStore {
    private let directory: URL?

    init(directory: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: AppGroup.identifier)) {
        self.directory = directory
    }

    private func file(_ name: String) throws -> URL {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        return directory.appendingPathComponent(name)
    }

    enum ReadResult {
        case missing, failed, snapshot(WidgetSnapshot)
        var snapshot: WidgetSnapshot? {
            if case .snapshot(let snapshot) = self { return snapshot }
            return nil
        }
        func nextRefresh(after now: Date, calendar: Calendar = .current) -> Date {
            if case .failed = self { return now.addingTimeInterval(30 * 60) }
            return min(now.addingTimeInterval(60 * 60), calendar.dateInterval(of: .month, for: now)!.end)
        }
    }

    func read() -> ReadResult {
        do {
            let data = try Data(contentsOf: file("widget-snapshot.json"))
            return .snapshot(try JSONDecoder().decode(WidgetSnapshot.self, from: data))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch { return .failed }
    }

    func load() -> WidgetSnapshot? { read().snapshot }

    /// The snapshot the widgets may show; they check at every use, including quick snapshots and category pickers.
    /// Phone mode's numbers belong to the iPhone and are shown whoever is logged in. Server mode's are shown only while
    /// their account is the saved login's (the central logout); on a mismatch, or for an old file naming no account,
    /// the file is deleted. Nil must never match a missing marker.
    func readShown(in defaults: UserDefaults? = EmpireShared.defaults) -> ReadResult {
        let result = read()
        guard case .snapshot(let snapshot) = result, !snapshot.phone else { return result }
        guard let account = LoginMarker.account(in: defaults), snapshot.account == account else {
            try? delete()
            return .missing
        }
        return result
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try JSONEncoder().encode(snapshot).write(to: file("widget-snapshot.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete() throws {
        let url = try file("widget-snapshot.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// Whether the app is in red mode; the widgets then show red, otherwise the home screen's light or dark
    /// (`AresiumWidgetLook`). Off when nothing is saved.
    var redMode: Bool {
        guard let url = try? file("widget-red-mode.json"), let data = try? Data(contentsOf: url),
              let red = try? JSONDecoder().decode(Bool.self, from: data) else { return false }
        return red
    }

    func saveRedMode(_ red: Bool) throws {
        try JSONEncoder().encode(red).write(to: file("widget-red-mode.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Whether Aresium's lock is on: the widgets then show no numbers, only that Aresium is locked, and the app keeps
    /// none here (`WidgetSnapshotPublisher`). Off when nothing is saved.
    var isLocked: Bool {
        guard let url = try? file("widget-locked.json"), let data = try? Data(contentsOf: url),
              let locked = try? JSONDecoder().decode(Bool.self, from: data) else { return false }
        return locked
    }

    func saveLocked(_ locked: Bool) throws {
        try JSONEncoder().encode(locked).write(to: file("widget-locked.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
