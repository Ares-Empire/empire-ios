import Foundation
import WidgetKit

/// What Siri, Shortcuts (and so NFC tags) and the Control Center controls can do, on flatd. One place for the app's
/// intents and its controls, so both mean the same by "the fans" or "a blind open". The app's own screens go through
/// `FlatStore`, which shows each step as it happens.
nonisolated struct FlatActions: Sendable {
    let reach: FlatdReach

    static var live: FlatActions { FlatActions(reach: FlatdReach(connection: .live)) }

    // MARK: cooking (a mode on flatd: fans on and its blind up; ended: fans off, that blind to its favourite spot)

    /// Returns the devices that did not follow (flatd changes the mode anyway).
    func setCooking(_ active: Bool) async throws -> [String] {
        try await reach.run { try await $0.setMode(FlatMode.cookingID, active: active).failed }
    }

    func isCooking() async throws -> Bool {
        try await reach.run { client in
            try await client.modes().first { $0.id == FlatMode.cookingID }?.active ?? false
        }
    }

    // MARK: fans (every device of kind `fan`, or the ones named)

    func fans() async throws -> [Device] {
        try await devices().filter { $0.kind == .fan }
    }

    /// flatd's devices, remembered for Shortcuts' pickers while their pairing is still the saved one.
    func devices() async throws -> [Device] {
        let (devices, token) = try await reach.run { client in (try await client.devices(), client.token) }
        reach.connection.remember(devices, keyedBy: token)
        return devices
    }

    /// Switches the fans (all, or those in `only`) on (for `minutes`, nil: until switched off) or off, side by side.
    /// Returns the fans as flatd confirmed them; throws the first failure after every fan was tried.
    @discardableResult
    func setFans(on: Bool, minutes: Int? = nil, only ids: [String]? = nil) async throws -> [Device] {
        let command = DeviceCommand.power(on: on, seconds: minutes.map { max(1, $0) * 60 })
        let connection = reach.connection
        return try await reach.run { client in
            let fans = try await client.devices().filter { $0.kind == .fan && (ids?.contains($0.id) ?? true) }
            guard !fans.isEmpty else { throw FlatdError.unknown }
            // The pairing may have changed while the list was read: then nothing is switched.
            guard connection.token == client.token else { throw FlatdError.refused }
            return try await withThrowingTaskGroup(of: Result<Device, FlatdError>.self) { group in
                for fan in fans {
                    group.addTask {
                        do { return .success(try await client.send(command, to: fan.id)) }
                        catch let error as FlatdError { return .failure(error) }
                        catch { return .failure(.unreachable) }
                    }
                }
                var done: [Device] = [], firstError: FlatdError?
                for try await result in group {
                    switch result {
                    case let .success(device): done.append(device)
                    case let .failure(error): firstError = firstError ?? error
                    }
                }
                if let firstError { throw firstError }
                return done
            }
        }
    }

    func fansRunning() async throws -> Bool {
        try await fans().contains { $0.state.on == true }
    }

    // MARK: blinds (Rollos)

    func rollos() async throws -> [Device] {
        try await devices().filter { $0.kind == .rollo }
    }

    @discardableResult
    func move(rollo id: String, _ command: RolloCommand) async throws -> Device {
        try await reach.run { try await $0.send(.rollo(command), to: id) }
    }

    func rollo(_ id: String) async throws -> Device? {
        try await rollos().first { $0.id == id }
    }

    // MARK: scenes

    /// Returns the devices that did not follow.
    @discardableResult
    func runScene(_ id: String) async throws -> [String] {
        try await reach.run { try await $0.runScene(id) }
    }
}

/// A blind counts as open while it is more up than down (the Control Center control's on state).
nonisolated enum RolloOpenness {
    static func isOpen(_ state: DeviceState) -> Bool {
        if let target = state.target, state.moving != nil { return target < 50 }
        return (state.position ?? 0) < 50
    }
}

/// The Control Center controls' kinds, and asking iOS to read them again after something changed.
nonisolated enum ArestiaControlKind {
    static let cooking = "de.ares-empire.arestia.cooking"
    static let fans = "de.ares-empire.arestia.fans"
    static let rollo = "de.ares-empire.arestia.rollo"

    static func reloadAll() {
        ControlCenter.shared.reloadAllControls()
    }
}
