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
            return calendar.dateInterval(of: .month, for: now)!.end
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

    func save(_ snapshot: WidgetSnapshot) throws {
        try JSONEncoder().encode(snapshot).write(to: file("widget-snapshot.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func delete() throws {
        let url = try file("widget-snapshot.json")
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    var theme: AppTheme {
        guard let url = try? file("widget-theme.json"), let data = try? Data(contentsOf: url),
              let theme = try? JSONDecoder().decode(AppTheme.self, from: data) else { return .dark }
        return theme
    }

    func saveTheme(_ theme: AppTheme) throws {
        try JSONEncoder().encode(theme).write(to: file("widget-theme.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
