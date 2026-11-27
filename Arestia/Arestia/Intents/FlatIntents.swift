import AppIntents
import Foundation

// Siri, Shortcuts and NFC personal automations (Shortcuts → Automation → NFC → run "Toggle cooking"). Every intent runs
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
        DeviceChoices.resolve(identifiers, among: await DeviceChoices.load(kind: .fan))
            .map { FanEntity(id: $0.id, name: $0.label) }
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

/// The dialogs say what flatd confirmed (the mode's state in its answer, the devices that did not follow), never what
/// the mode's devices are assumed to do (Codex's review, rounds 5 and 6).
nonisolated enum CookingDialog {
    static func text(_ change: CookingChange, language: AppLanguage = .current) -> String {
        language.string(change.isActive ? LocalizedStringResource("Cooking is on.", table: "ArestiaShared")
                        : LocalizedStringResource("Cooking is off.", table: "ArestiaShared"))
            + FailureLine.text(change.failed, language: language)
    }
}

struct StartCookingIntent: AppIntent {
    static let title = LocalizedStringResource("Start cooking", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Turns on cooking: the fans run and its blind goes up, until you end it.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self))
        return try await performFlatIntent(timing: timing, { try await FlatActions.live.setCooking(true) }) { change in
            IntentResultContainer.result(dialog: IntentDialog(stringLiteral: CookingDialog.text(change)))
        }
        #else
        let change = try await performFlatIntent { try await FlatActions.live.setCooking(true) }
        return .result(dialog: IntentDialog(stringLiteral: CookingDialog.text(change)))
        #endif
    }
}

struct EndCookingIntent: AppIntent {
    static let title = LocalizedStringResource("End cooking", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Ends cooking: the fans go off and its blind goes to its favourite spot.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self))
        return try await performFlatIntent(timing: timing, { try await FlatActions.live.setCooking(false) }) { change in
            IntentResultContainer.result(dialog: IntentDialog(stringLiteral: CookingDialog.text(change)))
        }
        #else
        let change = try await performFlatIntent { try await FlatActions.live.setCooking(false) }
        return .result(dialog: IntentDialog(stringLiteral: CookingDialog.text(change)))
        #endif
    }
}

struct ToggleCookingIntent: AppIntent {
    static let title = LocalizedStringResource("Toggle cooking", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Ends cooking if it is on, starts it if it is off.", table: "ArestiaShared"))

    private let actions: FlatActions?

    init() { actions = nil }
    init(actions: FlatActions) { self.actions = actions }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self))
        let actions = actions ?? .live
        return try await performFlatIntent(timing: timing, { try await actions.toggleCooking() }) { change in
            IntentResultContainer.result(dialog: IntentDialog(stringLiteral: CookingDialog.text(change)))
        }
        #else
        let actions = actions ?? .live
        let change = try await performFlatIntent { try await actions.toggleCooking() }
        return .result(dialog: IntentDialog(stringLiteral: CookingDialog.text(change)))
        #endif
    }
}

/// A scene's dialog: what it does only when every device followed; otherwise which did not.
nonisolated enum SceneDialog {
    static func text(done: LocalizedStringResource, failed: [String], language: AppLanguage = .current) -> String {
        failed.isEmpty ? language.string(done)
            : language.string(LocalizedStringResource("Not everything followed.", table: "ArestiaShared"))
                + FailureLine.text(failed, language: language)
    }
}

/// A blind's dialog from flatd's answer: its name and its state as flatd confirmed it ("Blind 1: Going up."), so a
/// Stop near an end that leaves it moving is never told as stopped.
nonisolated enum RolloDialog {
    static func text(_ device: Device, language: AppLanguage = .current) -> String {
        let status = FlatWords.rolloStatus(device.state, language: language)
        return language.string(LocalizedStringResource("\(device.label): \(status).", table: "ArestiaShared"))
    }
}

// MARK: - fans

struct FansOnIntent: AppIntent {
    static let title = LocalizedStringResource("Fans on", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "Turns the fans on, for a while or until you turn them off. The timer runs in the plug, so it ends even when flatd is offline.",
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
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self), isFanBatch: true)
        let minutes = minutes, only = fan.map { [$0.id] }
        return try await performFlatIntent(timing: timing, {
            try await FlatActions.live.setFans(on: true, minutes: minutes, only: only)
        }) { _ in
            let line = minutes.map {
                AppLanguage.current.string(LocalizedStringResource("Fans on for \($0) min.", table: "ArestiaShared"))
            } ?? AppLanguage.current.string(LocalizedStringResource("Fans on.", table: "ArestiaShared"))
            return IntentResultContainer.result(dialog: IntentDialog(stringLiteral: line))
        }
        #else
        let minutes = minutes, only = fan.map { [$0.id] }
        _ = try await performFlatIntent { try await FlatActions.live.setFans(on: true, minutes: minutes, only: only) }
        let line = minutes.map {
            AppLanguage.current.string(LocalizedStringResource("Fans on for \($0) min.", table: "ArestiaShared"))
        } ?? AppLanguage.current.string(LocalizedStringResource("Fans on.", table: "ArestiaShared"))
        return .result(dialog: IntentDialog(stringLiteral: line))
        #endif
    }
}

struct FansOffIntent: AppIntent {
    static let title = LocalizedStringResource("Fans off", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource("Turns the fans off.", table: "ArestiaShared"))

    @Parameter(title: LocalizedStringResource("Fan", table: "ArestiaShared"),
               description: LocalizedStringResource("Empty: every fan.", table: "ArestiaShared"))
    var fan: FanEntity?

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self), isFanBatch: true)
        let only = fan.map { [$0.id] }
        return try await performFlatIntent(timing: timing, {
            try await FlatActions.live.setFans(on: false, only: only)
        }) { _ in
            IntentResultContainer.result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(
                LocalizedStringResource("Fans off.", table: "ArestiaShared"))))
        }
        #else
        let only = fan.map { [$0.id] }
        _ = try await performFlatIntent { try await FlatActions.live.setFans(on: false, only: only) }
        return .result(dialog: IntentDialog(stringLiteral: AppLanguage.current.string(
            LocalizedStringResource("Fans off.", table: "ArestiaShared"))))
        #endif
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
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self))
        let id = rollo.id, command = move.command
        return try await performFlatIntent(timing: timing, { try await FlatActions.live.move(rollo: id, command) }) {
            IntentResultContainer.result(dialog: IntentDialog(stringLiteral: RolloDialog.text($0)))
        }
        #else
        let id = rollo.id, command = move.command
        let device = try await performFlatIntent { try await FlatActions.live.move(rollo: id, command) }
        return .result(dialog: IntentDialog(stringLiteral: RolloDialog.text(device)))
        #endif
    }
}

// MARK: - scenes

struct AirOutIntent: AppIntent {
    static let title = LocalizedStringResource("Air out", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource(
        "The fans run for 30 minutes and a blind goes up.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self))
        return try await performFlatIntent(timing: timing, { try await FlatActions.live.runScene(FlatScene.airOutID) }) {
            IntentResultContainer.result(dialog: IntentDialog(stringLiteral: SceneDialog.text(
                done: LocalizedStringResource("Airing out for 30 minutes.", table: "ArestiaShared"), failed: $0)))
        }
        #else
        let failed = try await performFlatIntent { try await FlatActions.live.runScene(FlatScene.airOutID) }
        return .result(dialog: IntentDialog(stringLiteral: SceneDialog.text(
            done: LocalizedStringResource("Airing out for 30 minutes.", table: "ArestiaShared"), failed: failed)))
        #endif
    }
}

struct AllDownIntent: AppIntent {
    static let title = LocalizedStringResource("All blinds down", table: "ArestiaShared")
    static let description = IntentDescription(LocalizedStringResource("Sends every blind down.", table: "ArestiaShared"))

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self))
        return try await performFlatIntent(timing: timing, { try await FlatActions.live.runScene(FlatScene.allDownID) }) {
            IntentResultContainer.result(dialog: IntentDialog(stringLiteral: SceneDialog.text(
                done: LocalizedStringResource("All blinds are going down.", table: "ArestiaShared"), failed: $0)))
        }
        #else
        let failed = try await performFlatIntent { try await FlatActions.live.runScene(FlatScene.allDownID) }
        return .result(dialog: IntentDialog(stringLiteral: SceneDialog.text(
            done: LocalizedStringResource("All blinds are going down.", table: "ArestiaShared"), failed: failed)))
        #endif
    }
}
