import Foundation
import WidgetKit

/// What Siri, Shortcuts (and so NFC tags) and the Control Center controls can do, on flatd. One place for the app's
/// intents and its controls, so both mean the same by "the fans" or "a blind open". They always act on the flat paired
/// when they run (one flat per install, docs/ARESTIA-APP.md): a control is "my flat's cooking", not one flat's. The
/// app's own screens go through `FlatStore`, which shows each step as it happens.
nonisolated struct FlatActions: Sendable {
    let reach: FlatdReach

    #if DEBUG
    @TaskLocal static var liveFactory: (@Sendable () -> FlatActions)?
    #endif

    static var live: FlatActions {
        get async throws {
            let deadline = FlatdReach.intentBudget ?? FlatdReach.intentDeadline()
            #if DEBUG
            let factory = liveFactory ?? { FlatActions(reach: FlatdReach(connection: .live)) }
            #else
            let factory: @Sendable () -> FlatActions = { FlatActions(reach: FlatdReach(connection: .live)) }
            #endif
            return try await deadline.blocking { _ in factory() }
        }
    }

    // MARK: cooking (a mode on flatd: fans on and its blind up; ended: fans off, that blind to its favourite spot)

    /// Starts or ends cooking. What flatd confirmed comes back: whether cooking is on now, and the devices that did not
    /// follow, by name (flatd changes the mode anyway). Those are also kept for the Cooking control and the app
    /// (`ModeTrouble`), since this runs outside the app; a change where all followed clears them.
    func setCooking(_ active: Bool) async throws -> CookingChange {
        try await setCooking { _ in active }
    }

    /// Both requests use the same pairing, so Forget between the read and write stops the change.
    func toggleCooking() async throws -> CookingChange {
        try await setCooking { client in try await !client.cookingActive() }
    }

    private func setCooking(resolving active: @Sendable (FlatdClient) async throws -> Bool) async throws -> CookingChange {
        let connection = reach.connection
        let deadline = FlatdReach.intentBudget ?? FlatdReach.intentDeadline()
        let (change, pairing) = try await reach.run(deadline: deadline) { client in
            let active = try await active(client)
            let (mode, failed) = try await client.setMode(FlatMode.cookingID, active: active)
            let names = await deadline.bestEffort(default: failed) { _ in
                connection.names(failed, pairing: client.pairingID)
            }
            try Task.checkCancellation()
            return (CookingChange(isActive: mode.active, failed: names), client.pairingID)
        }
        if let pairing {
            let at = Date.now
            await deadline.bestEffort(default: ()) { hold in
                if change.failed.isEmpty {
                    try connection.clearTrouble(mode: FlatMode.cookingID, pairing: pairing, now: change.isActive,
                                                through: at, hold: hold)
                } else {
                    try connection.note(ModeTrouble(pairing: pairing, mode: FlatMode.cookingID, active: change.isActive,
                                                   names: change.failed, at: at), hold: hold)
                }
            }
        }
        try Task.checkCancellation()
        return change
    }

    /// The Cooking control's state: cooking as flatd has it now, and the devices that did not follow when it last
    /// changed outside the app, while that still describes it.
    func cookingState() async throws -> CookingState {
        let (active, pairing) = try await reach.run { client in
            (try await client.cookingActive(), client.pairingID)
        }
        let trouble = pairing.flatMap { reach.connection.trouble(mode: FlatMode.cookingID, active: active, pairing: $0) }
        return CookingState(active: active, notFollowed: trouble?.names ?? [])
    }

    // MARK: fans (every device of kind `fan`, or the ones named)

    func fans() async throws -> [Device] {
        try await devices().filter { $0.kind == .fan }
    }

    /// flatd's devices, remembered for Shortcuts' pickers while their pairing is still the saved one.
    func devices() async throws -> [Device] {
        try await read().devices
    }

    /// flatd's devices as read now (their state), each under the latest name accepted for the paired flat. The list is
    /// offered to the names kept, which refuse it when newer names came in while flatd answered (a rename heard
    /// meanwhile). Either way the names shown are the ones kept after that: a name this very list brought and the names
    /// refused are never shown (Codex's review of the renaming, round 2, finding 4: the Blind control showed the older
    /// name its own request brought). This happens inside `reach.run` (`FlatdConnection.named`), so its last check of
    /// the pairing covers the result: a flat forgotten before that shows nothing, never its devices (round 3, finding
    /// 2). Only where no names can be kept at all does a device keep the name flatd just sent.
    private func read() async throws -> (devices: [Device], client: FlatdClient) {
        let connection = reach.connection
        let deadline = FlatdReach.intentBudget ?? FlatdReach.intentDeadline()
        let version = await deadline.bestEffort(default: nil) { _ in connection.devicesVersion }
        try Task.checkCancellation()
        return try await reach.run(deadline: deadline) { client in
            let devices = try await client.devices()
            let named = await deadline.bestEffort(default: devices) { hold in
                try connection.named(devices, from: client, readSince: version, hold: hold)
            }
            try Task.checkCancellation()
            return (named, client)
        }
    }

    /// Switches the fans (all, or those in `only`) on (for `minutes`, nil: until switched off) or off, side by side.
    /// Returns the fans as flatd confirmed them; reports an unanswered write before other failures. `only` holds
    /// saved choices (`SavedDevice`): one the paired flat does not have (any more), or one chosen before the flat was
    /// forgotten, throws `ChosenDeviceGone.fan`, and nothing is switched.
    @discardableResult
    func setFans(on: Bool, minutes: Int? = nil, only saved: [String]? = nil) async throws -> [Device] {
        let command = DeviceCommand.power(on: on, seconds: minutes.map { max(1, $0) * 60 })
        let deadline = FlatdReach.intentBudget ?? FlatdReach.intentDeadline()
        return try await reach.run(deadline: deadline) { client in
            let ids = try saved?.map { choice in
                do { return try SavedDevice.device(choice, of: client) } catch { throw ChosenDeviceGone.fan }
            }
            let fans = try await client.devices().filter { $0.kind == .fan && (ids?.contains($0.id) ?? true) }
            if let ids, Set(fans.map(\.id)) != Set(ids) { throw ChosenDeviceGone.fan }
            guard !fans.isEmpty else { throw FlatdError.unknown }
            return try await withThrowingTaskGroup(of: Result<Device, Error>.self) { group in
                for fan in fans {
                    group.addTask {
                        do { return .success(try await client.send(command, to: fan.id)) }
                        catch is CancellationError { throw CancellationError() }
                        catch { return .failure(error) }
                    }
                }
                var done: [Device] = [], firstError: Error?
                for try await result in group {
                    switch result {
                    case let .success(device): done.append(device)
                    case let .failure(error):
                        // Preserve a lock refusal if the whole batch can still retry at home.
                        if (error as? FlatdError) == .noAnswer {
                            firstError = error
                        } else if error is FlatdGate.RemoteDenied, (firstError as? FlatdError) != .noAnswer {
                            firstError = error
                        } else {
                            firstError = firstError ?? error
                        }
                    }
                }
                if !done.isEmpty, let error = firstError, (error as? FlatdError) != .noAnswer {
                    firstError = FlatdError.partialFans(needsUnlock: error is FlatdGate.RemoteDenied)
                }
                #if DEBUG && ARESTIA_GATE
                GateAction.current?.fansSettled(firstError.map(GateOutcome.init) ?? .ok)
                #endif
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

    /// `saved`: the blind as a Shortcut or a control remembers it (`SavedDevice`). One the paired flat does not have
    /// (any more: flatd answers 404), or one chosen before the flat was forgotten, throws `ChosenDeviceGone.blind`, and
    /// nothing moves.
    @discardableResult
    func move(rollo saved: String, _ command: RolloCommand) async throws -> Device {
        try await reach.run { client in
            let id: String
            do { id = try SavedDevice.device(saved, of: client) } catch { throw ChosenDeviceGone.blind }
            do {
                return try await client.send(.rollo(command), to: id)
            } catch FlatdError.unknown {
                throw ChosenDeviceGone.blind
            }
        }
    }

    /// The blind a control remembers, as flatd has it now; nil when the paired flat has none with that id (or the
    /// choice was made before the flat was forgotten).
    func rollo(_ saved: String) async throws -> Device? {
        let (devices, client) = try await read()
        guard let id = try? SavedDevice.device(saved, of: client) else { return nil }
        return devices.first { $0.kind == .rollo && $0.id == id }
    }

    /// What the Blind control shows: nothing chosen yet, a blind the flat does not have (any more), one flatd has no
    /// position for (offline, or before the board's first reading), or the blind as flatd has it now. Never the
    /// preview's state as if it were live, never a position nobody read, and never a name kept for a gone choice.
    func rolloControl(_ saved: String?) async throws -> RolloControlState {
        guard let saved else { return .notChosen }
        guard let device = try await rollo(saved) else { return .gone }
        guard let isOpen = RolloOpenness.isOpen(device.state) else { return .unknown(name: device.label) }
        return .blind(name: device.label, isOpen: isOpen)
    }

    // MARK: scenes

    /// Returns the devices that did not follow, by name.
    @discardableResult
    func runScene(_ id: String) async throws -> [String] {
        let connection = reach.connection
        let deadline = FlatdReach.intentBudget ?? FlatdReach.intentDeadline()
        return try await reach.run(deadline: deadline) { client in
            let failed = try await client.runScene(id)
            let names = await deadline.bestEffort(default: failed) { _ in
                connection.names(failed, pairing: client.pairingID)
            }
            try Task.checkCancellation()
            return names
        }
    }
}

/// What starting or ending cooking did, as flatd confirmed it.
nonisolated struct CookingChange: Equatable, Sendable {
    let isActive: Bool
    /// The devices that did not follow, by name.
    let failed: [String]
}

/// The Cooking control's state (`FlatActions.cookingState`).
nonisolated struct CookingState: Equatable, Sendable {
    let active: Bool
    /// The devices that did not follow its last change outside the app, by name; empty when all did, or that change
    /// no longer describes cooking.
    let notFollowed: [String]
}

/// The Blind control's state (`FlatActions.rolloControl`).
nonisolated enum RolloControlState: Equatable, Sendable {
    case notChosen
    case gone
    /// The blind is there, but flatd has no position for it now (offline, or not read yet).
    case unknown(name: String)
    case blind(name: String, isOpen: Bool)
}

/// A blind or fan chosen in a Shortcut or a control that the paired flat does not have (any more), or that was chosen
/// before the flat was forgotten: nothing is sent; it is chosen again.
nonisolated enum ChosenDeviceGone: Error, Equatable, Sendable {
    case blind, fan

    func message(language: AppLanguage = .current) -> String {
        switch self {
        case .blind:
            language.string(LocalizedStringResource("This blind isn't in your flat anymore. Choose it again.",
                                                    table: "ArestiaShared"))
        case .fan:
            language.string(LocalizedStringResource("This fan isn't in your flat anymore. Choose it again.",
                                                    table: "ArestiaShared"))
        }
    }
}

/// A device as a Shortcut or a Control Center control remembers it (an entity's id): flatd's device id together with
/// the identity of the pairing it was chosen in (`FlatdPairing.id`). iOS keeps those choices itself and the app cannot
/// delete them; tagging them is how Forget wipes them: flatd's ids are only names inside one flatd, so after Forget and
/// a new pairing the same id may be another device, and a choice made before acts on nothing (`ChosenDeviceGone`). It
/// survives what the pairing survives: a new address, a renewed certificate, a fresh code (a new key) of the same flatd.
nonisolated enum SavedDevice {
    static func id(for device: String, of pairing: UUID) -> String {
        pairing.uuidString.lowercased() + "/" + device
    }

    /// flatd's device id from a saved choice; throws `.unknown` when the choice was made in another pairing.
    static func device(_ saved: String, of pairing: UUID) throws -> String {
        let prefix = pairing.uuidString.lowercased() + "/"
        guard saved.hasPrefix(prefix), saved.count > prefix.count else { throw FlatdError.unknown }
        return String(saved.dropFirst(prefix.count))
    }

    /// The same for the pairing a client speaks for; a client of no pairing has no choices.
    static func device(_ saved: String, of client: FlatdClient) throws -> String {
        guard let pairing = client.pairingID else { throw FlatdError.unknown }
        return try device(saved, of: pairing)
    }
}

/// A blind counts as open while it is more up than down (the Control Center control's on state); nil while flatd has
/// no position for it (offline, or before the board's first reading): unknown, never taken as open.
nonisolated enum RolloOpenness {
    static func isOpen(_ state: DeviceState) -> Bool? {
        guard state.online else { return nil }
        if let target = state.target, state.moving != nil { return target < 50 }
        return state.position.map { $0 < 50 }
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
