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
        let (devices, client) = try await reach.run { client in (try await client.devices(), client) }
        reach.connection.remember(devices, from: client)
        return devices
    }

    /// Switches the fans (all, or those in `only`) on (for `minutes`, nil: until switched off) or off, side by side.
    /// Returns the fans as flatd confirmed them; throws the first failure after every fan was tried. `only` holds
    /// saved choices (`SavedDevice`): one made for another flatd is `.unknown`, and nothing is switched.
    @discardableResult
    func setFans(on: Bool, minutes: Int? = nil, only saved: [String]? = nil) async throws -> [Device] {
        let command = DeviceCommand.power(on: on, seconds: minutes.map { max(1, $0) * 60 })
        let connection = reach.connection
        return try await reach.run { client in
            let ids = try saved?.map { try SavedDevice.device($0, of: client.pin) }
            let fans = try await client.devices().filter { $0.kind == .fan && (ids?.contains($0.id) ?? true) }
            guard !fans.isEmpty else { throw FlatdError.unknown }
            // The pairing may have changed while the list was read: then nothing is switched.
            guard connection.isCurrent(client) else { throw FlatdError.refused }
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

    /// `saved`: the blind as a Shortcut or a control remembers it (`SavedDevice`); one chosen for another flatd is
    /// `.unknown`, and nothing moves.
    @discardableResult
    func move(rollo saved: String, _ command: RolloCommand) async throws -> Device {
        try await reach.run { client in
            try await client.send(.rollo(command), to: try SavedDevice.device(saved, of: client.pin))
        }
    }

    /// The blind a control remembers, as flatd has it now; nil when flatd has none with that id (or the choice was
    /// made for another flatd).
    func rollo(_ saved: String) async throws -> Device? {
        let (devices, client) = try await reach.run { client in (try await client.devices(), client) }
        reach.connection.remember(devices, from: client)
        guard let id = try? SavedDevice.device(saved, of: client.pin) else { return nil }
        return devices.first { $0.kind == .rollo && $0.id == id }
    }

    // MARK: scenes

    /// Returns the devices that did not follow.
    @discardableResult
    func runScene(_ id: String) async throws -> [String] {
        try await reach.run { try await $0.runScene(id) }
    }
}

/// A device as a Shortcut or a Control Center control remembers it (an entity's id): flatd's device id together with
/// the start of that flatd's identity. flatd's ids are only names inside one flatd; after pairing with another flatd
/// the same id may be another device, so a choice made for one flatd is never used on another: it has to be made
/// again. It survives everything the pairing survives (a new address, a renewed certificate, a fresh code of the same
/// flatd).
nonisolated enum SavedDevice {
    static func id(for device: String, of pin: FlatdPin) -> String {
        pin.hex.prefix(16) + "/" + device
    }

    /// flatd's device id from a saved choice; throws `.unknown` when the choice was made for another flatd.
    static func device(_ saved: String, of pin: FlatdPin) throws -> String {
        let prefix = pin.hex.prefix(16) + "/"
        guard saved.hasPrefix(prefix), saved.count > prefix.count else { throw FlatdError.unknown }
        return String(saved.dropFirst(prefix.count))
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
