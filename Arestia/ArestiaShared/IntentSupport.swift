import AppIntents
import Foundation

// What the app's intents (Siri, Shortcuts, NFC automations: `Arestia/Intents/FlatIntents.swift`) and the Control
// Center controls' intents (`ArestiaControls/ControlIntents.swift`) share. The intents themselves live in one target
// each: an intent compiled into both is run by iOS in the extension, which has no `AppShortcutsProvider`, and the App
// Shortcut then fails with "Couldn't find shortcut" (seen on the simulator, 2026-11-19).

extension WidgetLanguage {
    /// Arestia's language choice, which its intents and controls follow (they run in their own process).
    nonisolated static var arestia: WidgetLanguage {
        WidgetLanguage(defaults: ArestiaGroup.defaults, app: "de.ares-empire.arestia")
    }
}

/// A failure an intent reports to Siri or Shortcuts, in the app's words.
nonisolated struct FlatIntentError: Error, CustomLocalizedStringResourceConvertible {
    let message: String
    var localizedStringResource: LocalizedStringResource { LocalizedStringResource(stringLiteral: message) }

    init(_ error: Error) {
        message = (error as? FlatdError ?? .unreachable).message()
    }
}

/// Runs an intent's work in the app's language, turns failures into the app's words and asks Control Center to read
/// its controls again.
nonisolated func performFlatIntent<T: Sendable>(_ work: @Sendable () async throws -> T) async throws -> T {
    WidgetLanguage.arestia.follow()
    do {
        let result = try await work()
        ArestiaControlKind.reloadAll()
        return result
    } catch {
        ArestiaControlKind.reloadAll()
        throw FlatIntentError(error)
    }
}

/// "Didn't answer: Fan 2." after a mode or scene whose devices did not all follow (empty when all did).
nonisolated enum FailureLine {
    static func text(_ ids: [String], connection: FlatdConnection = .live, language: AppLanguage = .current) -> String {
        guard !ids.isEmpty else { return "" }
        let names = connection.knownDevices
        let list = ids.map { id in names.first { $0.id == id }?.label ?? id }.joined(separator: ", ")
        return " " + language.string(LocalizedStringResource("Didn't answer: \(list).", table: "ArestiaShared"))
    }
}

// MARK: - entities: the fans and blinds flatd has

nonisolated struct RolloEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Blind", table: "ArestiaShared"))
    static let defaultQuery = RolloQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct RolloQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [RolloEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RolloEntity] {
        await DeviceChoices.load(kind: .rollo).map { RolloEntity(id: $0.id, name: $0.label) }
    }
}

/// The devices to choose from in Shortcuts: flatd's list, or the one seen last when flatd is out of reach (setting up
/// an automation away from home still works).
nonisolated enum DeviceChoices {
    static func load(kind: Device.Kind, connection: FlatdConnection = .live) async -> [FlatdConnection.KnownDevice] {
        if let answer = try? await FlatdReach(connection: connection).run({ client in
            (try await client.devices(), client.token)
        }) {
            connection.remember(answer.0, keyedBy: answer.1)
        }
        return connection.knownDevices.filter { $0.kind == kind.raw }
    }
}
