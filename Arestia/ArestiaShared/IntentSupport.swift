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
        if let gone = error as? ChosenDeviceGone {
            message = gone.message()
        } else {
            message = (error as? FlatdError ?? .unreachable).message()
        }
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

/// " Didn't answer: Fan 2." after a mode or scene whose devices did not all follow, by name (empty when all did).
nonisolated enum FailureLine {
    static func text(_ names: [String], language: AppLanguage = .current) -> String {
        guard !names.isEmpty else { return "" }
        let list = names.joined(separator: ", ")
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
/// an automation away from home still works). Each choice's id carries the pairing its name was kept for
/// (`SavedDevice`), taken from the same reading as the names (`FlatdConnection.known`).
nonisolated enum DeviceChoices {
    nonisolated struct Choice: Equatable, Sendable {
        let id: String
        let label: String
    }

    static func load(kind: Device.Kind, connection: FlatdConnection = .live,
                     reach: FlatdReach? = nil) async -> [Choice] {
        if let answer = try? await (reach ?? FlatdReach(connection: connection)).run({ client in
            (try await client.devices(), client)
        }) {
            connection.remember(answer.0, from: answer.1)
        }
        return choices(kind: kind, from: connection.known)
    }

    /// The choices of one reading of the names: each tagged with the pairing those names belong to.
    static func choices(kind: Device.Kind, from known: FlatdConnection.KnownDevices?) -> [Choice] {
        guard let known else { return [] }
        return known.devices.filter { $0.kind == kind.raw }
            .map { Choice(id: SavedDevice.id(for: $0.id, of: known.pairing), label: $0.label) }
    }
}
