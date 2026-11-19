import AppIntents
import Foundation

// The Control Center controls' actions and configuration (only in the controls extension, see
// `ArestiaShared/IntentSupport.swift`). They run in the extension, with the key from Arestia's Keychain group.

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
