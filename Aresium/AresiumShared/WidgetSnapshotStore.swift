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

    func load() -> WidgetSnapshot? {
        guard let url = try? file("widget-snapshot.json"), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: WidgetSnapshot) throws {
        try JSONEncoder().encode(snapshot).write(to: file("widget-snapshot.json"), options: .atomic)
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
        try JSONEncoder().encode(theme).write(to: file("widget-theme.json"), options: .atomic)
    }
}
