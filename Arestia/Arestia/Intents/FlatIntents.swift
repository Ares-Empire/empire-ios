import AppIntents
import Foundation

// Siri, Shortcuts and NFC personal automations (Shortcuts → Automation → NFC → run "Start cooking"). Every intent runs
// without opening the app: it reads the saved address and key (`FlatdConnection.live`) and calls flatd directly. Only
// in the app target (see `ArestiaShared/IntentSupport.swift` for why).

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

/// The dialogs say what flatd confirmed (the mode's state, and the devices that did not follow), never what the mode's
/// devices are assumed to do (Codex's review, round 5).
struct StartCookingIntent: AppIntent {
    static let title = LocalizedStringResource("Start cooking", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Turns on cooking: the fans run and its blind goes up, until you end it.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let change = try await performFlatIntent { try await FlatActions.live.setCooking(true) }
        return .result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(
            LocalizedStringResource("Cooking is on.", table: "ArestiaShared")) + FailureLine.text(change.failed)))
    }
}

struct EndCookingIntent: AppIntent {
    static let title = LocalizedStringResource("End cooking", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Ends cooking: the fans go off and its blind goes to its favourite spot.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let change = try await performFlatIntent { try await FlatActions.live.setCooking(false) }
        // Ending cooking that was not on sends nothing to any device (flatd's contract): say so, claim nothing.
        let line = change.wasActive
            ? LocalizedStringResource("Cooking ended.", table: "ArestiaShared")
            : LocalizedStringResource("Cooking wasn't on.", table: "ArestiaShared")
        return .result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(line)
            + FailureLine.text(change.failed)))
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
