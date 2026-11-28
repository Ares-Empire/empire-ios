import AppIntents
import Foundation

// The Control Center controls' actions and configuration (only in the controls extension, see
// `ArestiaShared/IntentSupport.swift`). They run in the extension, with the key from Arestia's Keychain group.

/// The Cooking control's action (Control Center): on starts cooking, off ends it, on the flat paired now. Devices that
/// did not follow are kept with the mode's state (`FlatActions.setCooking`): the control shows "not all followed", and
/// the app says which, once.
struct SetCookingIntent: SetValueIntent {
    static let title = LocalizedStringResource("Cooking", table: "ArestiaShared")
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Cooking", table: "ArestiaShared"))
    var value: Bool

    func perform() async throws -> some IntentResult {
        let deadline = FlatdReach.intentDeadline()
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self))
        let active = value
        return try await performFlatIntent(deadline: deadline, timing: timing, { try await FlatActions.live.setCooking(active) }) { _ in
            IntentResultContainer.result()
        }
        #else
        let active = value
        _ = try await performFlatIntent(deadline: deadline) { try await FlatActions.live.setCooking(active) }
        return .result()
        #endif
    }
}

/// The Fans control's action: on turns every fan on (until turned off), off turns them all off.
struct SetFansIntent: SetValueIntent {
    static let title = LocalizedStringResource("Fans", table: "ArestiaShared")
    static let isDiscoverable = false

    @Parameter(title: LocalizedStringResource("Fans", table: "ArestiaShared"))
    var value: Bool

    func perform() async throws -> some IntentResult {
        let deadline = FlatdReach.intentDeadline()
        #if DEBUG && ARESTIA_GATE
        let timing = GateAction(String(describing: Self.self), isFanBatch: true)
        let on = value
        return try await performFlatIntent(deadline: deadline, timing: timing, { try await FlatActions.live.setFans(on: on) }) { _ in
            IntentResultContainer.result()
        }
        #else
        let on = value
        _ = try await performFlatIntent(deadline: deadline) { try await FlatActions.live.setFans(on: on) }
        return .result()
        #endif
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

/// The Blind control's action: on (open) sends it up, off sends it down. A blind the flat does not have (any more)
/// moves nothing and says so (`ChosenDeviceGone`).
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
        let deadline = FlatdReach.intentDeadline()
        guard let id = rollo?.id else { throw FlatIntentError(ChosenDeviceGone.blind) }
        let open = value
        _ = try await performFlatIntent(deadline: deadline) { try await FlatActions.live.move(rollo: id, open ? .up : .down) }
        return .result()
    }
}
