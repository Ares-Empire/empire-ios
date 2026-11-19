import AppIntents
import Foundation

// Siri, Shortcuts and NFC personal automations (Shortcuts → Automation → NFC → run "Start cooking"), and the actions of
// the Control Center controls. Every intent runs without opening the app: it reads the saved address and key
// (`FlatdConnection.live`) and calls flatd directly; the app need not be running.

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

nonisolated struct FanEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Fan", table: "ArestiaShared"))
    static let defaultQuery = FanQuery()
    let id: String
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

nonisolated struct FanQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [FanEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [FanEntity] {
        await DeviceChoices.load(kind: .fan).map { FanEntity(id: $0.id, name: $0.label) }
    }
}

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
        if let devices = try? await FlatdReach(connection: connection).run({ try await $0.devices() }) {
            connection.remember(devices)
        }
        return connection.knownDevices.filter { $0.kind == kind.raw }
    }
}

nonisolated enum RolloMove: String, AppEnum {
    case up, down, favourite, stop

    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: LocalizedStringResource("Move", table: "ArestiaShared"))
    static let caseDisplayRepresentations: [RolloMove: DisplayRepresentation] = [
        .up: DisplayRepresentation(title: LocalizedStringResource("Up", table: "ArestiaShared")),
        .down: DisplayRepresentation(title: LocalizedStringResource("Down", table: "ArestiaShared")),
        .favourite: DisplayRepresentation(title: LocalizedStringResource("To its favourite spot", table: "ArestiaShared")),
        .stop: DisplayRepresentation(title: LocalizedStringResource("Stop", table: "ArestiaShared")),
    ]

    var command: RolloCommand {
        switch self {
        case .up: .up
        case .down: .down
        case .favourite: .favourite
        case .stop: .stop
        }
    }
}

// MARK: - cooking

struct StartCookingIntent: AppIntent {
    static let title = LocalizedStringResource("Start cooking", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Turns on cooking: the fans run and its blind goes up, until you end it.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let failed = try await performFlatIntent { try await FlatActions.live.setCooking(true) }
        return .result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(
            LocalizedStringResource("Cooking. The fans are on and the blind is going up.", table: "ArestiaShared"))
            + FailureLine.text(failed)))
    }
}

struct EndCookingIntent: AppIntent {
    static let title = LocalizedStringResource("End cooking", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Ends cooking: the fans go off and its blind goes to its favourite spot.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let failed = try await performFlatIntent { try await FlatActions.live.setCooking(false) }
        return .result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(
            LocalizedStringResource("Done cooking. Fans off, the blind goes to its favourite spot.",
                                    table: "ArestiaShared")) + FailureLine.text(failed)))
    }
}

/// The Cooking control's action (Control Center): on starts cooking, off ends it.
struct SetCookingIntent: SetValueIntent {
    static let title = LocalizedStringResource("Cooking", table: "ArestiaShared")
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Cooking", table: "ArestiaShared"))
    var value: Bool

    func perform() async throws -> some IntentResult {
        let active = value
        _ = try await performFlatIntent { try await FlatActions.live.setCooking(active) }
        return .result()
    }
}

// MARK: - fans

struct FansOnIntent: AppIntent {
    static let title = LocalizedStringResource("Fans on", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Turns the fans on, for a while or until you turn them off. The timer runs in the plug, so it ends even when the Mac sleeps.",
        table: "ArestiaShared"))

    @Parameter(title: LocalizedStringResource("Minutes", table: "ArestiaShared"),
               description: LocalizedStringResource("Empty: until you turn them off.", table: "ArestiaShared"),
               inclusiveRange: (1, 720))
    var minutes: Int?

    @Parameter(title: LocalizedStringResource("Fan", table: "ArestiaShared"),
               description: LocalizedStringResource("Empty: every fan.", table: "ArestiaShared"))
    var fan: FanEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Turn \(\.$fan) on for \(\.$minutes) minutes")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let minutes = minutes, only = fan.map { [$0.id] }
        _ = try await performFlatIntent { try await FlatActions.live.setFans(on: true, minutes: minutes, only: only) }
        let line = minutes.map {
            AppLanguage.current.string(LocalizedStringResource("Fans on for \($0) min.", table: "ArestiaShared"))
        } ?? AppLanguage.current.string(LocalizedStringResource("Fans on.", table: "ArestiaShared"))
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

struct FansOffIntent: AppIntent {
    static let title = LocalizedStringResource("Fans off", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource("Turns the fans off.", table: "ArestiaShared"))

    @Parameter(title: LocalizedStringResource("Fan", table: "ArestiaShared"),
               description: LocalizedStringResource("Empty: every fan.", table: "ArestiaShared"))
    var fan: FanEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let only = fan.map { [$0.id] }
        _ = try await performFlatIntent { try await FlatActions.live.setFans(on: false, only: only) }
        return .result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(
            LocalizedStringResource("Fans off.", table: "ArestiaShared"))))
    }
}

/// The Fans control's action: on turns every fan on (until turned off), off turns them all off.
struct SetFansIntent: SetValueIntent {
    static let title = LocalizedStringResource("Fans", table: "ArestiaShared")
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Fans", table: "ArestiaShared"))
    var value: Bool

    func perform() async throws -> some IntentResult {
        let on = value
        _ = try await performFlatIntent { try await FlatActions.live.setFans(on: on) }
        return .result()
    }
}

// MARK: - blinds

struct MoveRolloIntent: AppIntent {
    static let title = LocalizedStringResource("Move a blind", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Sends a blind up, down, to its favourite spot, or stops it.", table: "ArestiaShared"))

    @Parameter(title: LocalizedStringResource("Blind", table: "ArestiaShared"))
    var rollo: RolloEntity

    @Parameter(title: LocalizedStringResource("Move", table: "ArestiaShared"), default: .up)
    var move: RolloMove

    static var parameterSummary: some ParameterSummary {
        Summary("Move \(\.$rollo) \(\.$move)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let id = rollo.id, command = move.command, name = rollo.name
        _ = try await performFlatIntent { try await FlatActions.live.move(rollo: id, command) }
        let line: String = switch command {
        case .up: AppLanguage.current.string(LocalizedStringResource("\(name) is going up.", table: "ArestiaShared"))
        case .down: AppLanguage.current.string(LocalizedStringResource("\(name) is going down.", table: "ArestiaShared"))
        case .favourite: AppLanguage.current.string(LocalizedStringResource("\(name) is going to its favourite spot.",
                                                                            table: "ArestiaShared"))
        case .stop: AppLanguage.current.string(LocalizedStringResource("\(name) stopped.", table: "ArestiaShared"))
        }
        return .result(dialog: IntentDialog(stringLiteral: line))
    }
}

/// The Blind control's configuration: which blind it moves.
struct RolloControlConfiguration: ControlConfigurationIntent {
    static let title = LocalizedStringResource("Blind", table: "ArestiaShared")
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Blind", table: "ArestiaShared"))
    var rollo: RolloEntity?

    init() {}
    init(rollo: RolloEntity?) { self.rollo = rollo }
}

/// The Blind control's action: on (open) sends it up, off sends it down.
struct SetRolloOpenIntent: SetValueIntent {
    static let title = LocalizedStringResource("Blind up or down", table: "ArestiaShared")
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Blind", table: "ArestiaShared"))
    var rollo: RolloEntity?

    @Parameter(title: LocalizedStringResource("Open", table: "ArestiaShared"))
    var value: Bool

    init() {}
    init(rollo: RolloEntity?) { self.rollo = rollo }

    func perform() async throws -> some IntentResult {
        guard let id = rollo?.id else { throw FlatIntentError(FlatdError.unknown) }
        let open = value
        _ = try await performFlatIntent { try await FlatActions.live.move(rollo: id, open ? .up : .down) }
        return .result()
    }
}

// MARK: - scenes

struct AirOutIntent: AppIntent {
    static let title = LocalizedStringResource("Air out", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "The fans run for 30 minutes and a blind goes up.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let failed = try await performFlatIntent { try await FlatActions.live.runScene(FlatScene.airOutID) }
        return .result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(
            LocalizedStringResource("Airing out for 30 minutes.", table: "ArestiaShared")) + FailureLine.text(failed)))
    }
}

struct AllDownIntent: AppIntent {
    static let title = LocalizedStringResource("All blinds down", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource("Sends every blind down.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let failed = try await performFlatIntent { try await FlatActions.live.runScene(FlatScene.allDownID) }
        return .result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(
            LocalizedStringResource("All blinds are going down.", table: "ArestiaShared")) + FailureLine.text(failed)))
    }
}
