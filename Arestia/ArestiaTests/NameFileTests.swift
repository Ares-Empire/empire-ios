import Foundation
import Testing
@testable import Arestia

// The devices' names kept for Shortcuts and the controls: one file in the App Group, one source of truth for the app
// and its extension (Codex's review of the renaming, round 2, findings 2 to 4; docs/ARESTIA-APP.md, "One file for the
// names").

private func named(_ object: [String: Any], _ label: String) -> [String: Any] {
    var object = object
    object["default_label"] = object["label"]
    object["label"] = label
    return object
}

/// The app and its extension as two connections that share nothing in memory: each its own lock object (its own
/// descriptor on the one lock file, as two processes have) on the same names file and the same saved pairing.
private struct TwoSides {
    let app: FlatdConnection
    let controls: FlatdConnection
    let lockPath: String
    let file: DeviceNameFile

    init() throws {
        file = Flat.nameFile()
        lockPath = file.url.deletingLastPathComponent().appending(path: "dispatch.lock").path(percentEncoded: false)
        let keys = MemoryKeys()
        app = FlatdConnection(defaults: nil, names: file, keychain: keys, lock: FlatdDispatchLock(path: lockPath))
        controls = FlatdConnection(defaults: nil, names: DeviceNameFile(url: file.url), keychain: keys,
                                   lock: FlatdDispatchLock(path: lockPath))
        try app.save(Flat.pairing())
    }
}

private func labels(_ connection: FlatdConnection) -> [String] { connection.knownDevices.map(\.label) }

struct NameFileTests {
    // MARK: finding 2: one file, read and written under the lock both sides share

    /// The extension reads flatd's list; the app keeps a rename before that list's answer comes. The extension's
    /// write sees the app's version the moment it holds the lock, and keeps nothing.
    @Test func theOtherSidesNewerNameIsSeenAtOnce() throws {
        let sides = try TwoSides()
        sides.app.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id)
        let begun = sides.controls.devicesVersion
        #expect(begun != nil)
        sides.app.rememberName(of: try Flat.decode(Device.self, named(Flat.fan(1), "Desk fan")), for: Flat.id)
        let taken = sides.controls.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id,
                                            readSince: begun)
        #expect(!taken)
        #expect(labels(sides.controls) == ["Desk fan", "Blind 1"])
        #expect(labels(sides.app) == ["Desk fan", "Blind 1"])
        // A list read after it is kept, and the app sees that at once too.
        let next = sides.controls.devicesVersion
        #expect(sides.controls.remember(try Flat.devices([named(Flat.fan(1), "Desk fan"), named(Flat.rollo(1), "Shade")]),
                                        for: Flat.id, readSince: next))
        #expect(labels(sides.app) == ["Desk fan", "Shade"])
    }

    /// Both sides rename at once, many times over: every name is in the file at the end (no write is made from a
    /// reading older than the other side's last write).
    @Test func noNameIsLostBetweenTheTwoSides() async throws {
        let sides = try TwoSides()
        let count = 40
        sides.app.remember(try Flat.devices((1...count).map { Flat.fan($0) }), for: Flat.id)
        let pairing = Flat.id
        await withTaskGroup(of: Void.self) { group in
            for number in 1...count {
                let side = number.isMultiple(of: 2) ? sides.app : sides.controls
                let device = Device(id: "fan:fan_\(number)", kind: .fan, label: "Renamed \(number)")
                group.addTask { @concurrent in side.rememberName(of: device, for: pairing) }
            }
        }
        #expect(labels(sides.app) == (1...count).map { "Renamed \($0)" })
        #expect(labels(sides.controls) == labels(sides.app))
    }

    /// A real second process (the simulator runs the Mac's programs): it takes the lock file with `flock`, holds it,
    /// replaces the names file with a rename and lets go. This process waits for the lock, reads what the other one
    /// wrote, lays its own rename over it, and refuses a list read before either.
    @Test func aSecondProcessesWriteIsReadUnderTheLock() async throws {
        #if targetEnvironment(simulator)
        let sides = try TwoSides()
        sides.app.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id)
        let begun = sides.controls.devicesVersion
        let marker = sides.file.url.deletingLastPathComponent().appending(path: "locked")
        let said = sides.file.url.deletingLastPathComponent().appending(path: "said")
        let script = """
        import fcntl, json, os, sys, time, uuid
        lock_path, names_path, marker = sys.argv[1:4]
        with open(lock_path, "a+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            open(marker, "w").close()
            time.sleep(0.5)
            with open(names_path) as file:
                names = json.load(file)
            names["devices"][0]["label"] = "Desk fan"
            names["version"] = str(uuid.uuid4())
            with open(names_path + ".new", "w") as file:
                json.dump(names, file)
            os.replace(names_path + ".new", names_path)
            fcntl.flock(lock, fcntl.LOCK_UN)
        """
        let process = try OtherProcess(["/usr/bin/python3", "-c", script, sides.lockPath,
                                        sides.file.url.path(percentEncoded: false), marker.path(percentEncoded: false)],
                                       output: said.path(percentEncoded: false))
        let locked = await eventually({ FileManager.default.fileExists(atPath: marker.path(percentEncoded: false)) },
                                      timeout: .seconds(10))
        guard locked else {
            Issue.record("the other process did not start: exit \(process.wait()), \((try? String(contentsOf: said, encoding: .utf8)) ?? "")")
            return
        }
        #expect(labels(sides.controls) == ["Fan 1", "Blind 1"])            // the other process holds the lock, unwritten
        // Waits for the other process to let go, then lays the blind's name over what that one wrote.
        sides.controls.rememberName(of: try Flat.decode(Device.self, named(Flat.rollo(1), "Shade")), for: Flat.id)
        #expect(labels(sides.controls) == ["Desk fan", "Shade"])
        #expect(process.wait() == 0)
        #expect(!sides.controls.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id, readSince: begun))
        #expect(labels(sides.app) == ["Desk fan", "Shade"])
        #endif
    }

    // MARK: finding 3: one device's name is laid over that device alone

    @Test func aConfirmedNameChangesItsDeviceAlone() throws {
        let connection = Flat.connection()
        let desk = try Flat.decode(Device.self, named(Flat.fan(1), "Desk fan"))
        connection.rememberName(of: desk, for: Flat.id)
        #expect(connection.known == nil)                                    // one name is no list
        connection.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id)
        let before = connection.devicesVersion
        connection.rememberName(of: desk, for: Flat.id)
        #expect(labels(connection) == ["Desk fan", "Blind 1"])
        #expect(connection.devicesVersion != before)                        // a list read before it is older
        connection.rememberName(of: Device(id: "light:lamp", kind: .light, label: "Lamp"), for: Flat.id)
        #expect(connection.knownDevices.map(\.id) == ["fan:fan_1", "rollo:blind_1", "light:lamp"])
        connection.rememberName(of: desk, for: UUID())                      // another pairing's: nothing
        try connection.forget()
        connection.rememberName(of: desk, for: Flat.id)                     // late, after Forget: nothing
        #expect(connection.known == nil && connection.devicesVersion == nil)
        #expect(!FileManager.default.fileExists(atPath: try #require(connection.names).url.path(percentEncoded: false)))
    }

    /// The app's stream is down; a picker reads flatd's list and keeps the blind's new name. A rename of a fan then
    /// succeeds in the app, whose own list still has the blind's old name: only the fan's name is written.
    @MainActor @Test func aRenameInTheAppKeepsANameAPickerReadMeanwhile() async throws {
        let (store, transport, events, _) = Flat.store()
        transport.answer("GET /api/scenes", body: ["scenes": []])
        store.start()
        #expect(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        #expect(await eventually { store.link == .live })
        let connection = store.connection
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        transport.answer("GET /api/devices", body: ["devices": [
            Flat.fan(1), Flat.fan(2), named(Flat.rollo(1), "Kitchen blind"), Flat.rollo(2)]])
        let choices = await DeviceChoices.load(kind: .rollo, connection: connection, reach: reach)
        #expect(choices.map(\.label) == ["Kitchen blind", "Blind 2"])
        #expect(store.device("rollo:blind_1")?.label == "Blind 1")          // the app has not heard of it
        // By the rename's answer:
        transport.answer("PATCH /api/devices/fan:fan_1", body: named(Flat.fan(1), "Desk fan"))
        store.rename("fan:fan_1", to: "Desk fan")
        #expect(await eventually { store.device("fan:fan_1")?.label == "Desk fan" })
        #expect(labels(connection) == ["Desk fan", "Fan 2", "Kitchen blind", "Blind 2"])
        // By the stream's event:
        events.send(.device(try Flat.decode(Device.self, named(Flat.fan(2), "Bath fan")), source: "mcp"))
        #expect(await eventually { store.device("fan:fan_2")?.label == "Bath fan" })
        #expect(labels(connection) == ["Desk fan", "Bath fan", "Kitchen blind", "Blind 2"])
        // A snapshot is flatd's whole list, in the stream's order: it replaces the names.
        events.send(try Flat.snapshot())
        #expect(await eventually { labels(connection) == ["Fan 1", "Fan 2", "Blind 1", "Blind 2"] })
        store.stop()
    }

    // MARK: finding 4: what is shown is the latest name accepted, never a list the names refused

    /// The Blind control reads flatd's list; a rename is kept before the answer comes. The control shows the answer's
    /// position under the name kept, and so do the fans read the same way.
    @Test func theBlindControlShowsTheNameKeptNotItsOwnOlderAnswer() async throws {
        let connection = Flat.connection()
        let transport = FakeTransport()
        connection.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id)
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.rollo(1, position: 100)]],
                         delay: .milliseconds(300))
        let actions = FlatActions(reach: FlatdReach(connection: connection, transport: transport, rediscover: { [] }))
        let chosen = SavedDevice.id(for: "rollo:blind_1", of: Flat.id)
        let control = Task { try await actions.rolloControl(chosen) }
        let fans = Task { try await actions.fans() }
        try await Task.sleep(for: .milliseconds(100))
        connection.rememberName(of: try Flat.decode(Device.self, named(Flat.rollo(1), "Kitchen blind")), for: Flat.id)
        connection.rememberName(of: try Flat.decode(Device.self, named(Flat.fan(1), "Desk fan")), for: Flat.id)
        #expect(try await control.value == .blind(name: "Kitchen blind", isOpen: false))
        #expect(try await fans.value.map(\.label) == ["Desk fan"])
        #expect(labels(connection) == ["Desk fan", "Kitchen blind"])
        // A list the names take is shown as flatd sent it.
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), named(Flat.rollo(1), "Shade")]])
        #expect(try await actions.rolloControl(chosen) == .blind(name: "Shade", isOpen: true))
        // No names can be kept at all (no App Group folder): the name flatd just sent.
        let bare = FlatdConnection(defaults: nil, names: nil, keychain: MemoryKeys(), lock: .processOnly)
        try bare.save(Flat.pairing())
        let plain = FlatActions(reach: FlatdReach(connection: bare, transport: transport, rediscover: { [] }))
        #expect(try await plain.rolloControl(chosen) == .blind(name: "Shade", isOpen: true))
    }

    // MARK: the pairing's scope, and build 2's names

    @Test func forgetRemovesTheNamesAndNothingReadsBuild2s() throws {
        let defaults = try #require(UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString))
        let connection = FlatdConnection(defaults: defaults, names: Flat.nameFile(), keychain: MemoryKeys(),
                                         lock: .processOnly)
        try connection.save(Flat.pairing())
        // Build 2 kept the names in the App Group's defaults: never read again, removed with the next snapshot.
        let old = #"{"pairing":"\#(Flat.id.uuidString)","devices":[{"id":"fan:fan_1","kind":"fan","label":"Old"}]}"#
        defaults.set(Data(old.utf8), forKey: FlatdConnection.namesKeyOfBuild2)
        #expect(connection.known == nil)
        connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id)
        #expect(labels(connection) == ["Fan 1"])
        #expect(defaults.object(forKey: FlatdConnection.namesKeyOfBuild2) == nil)
        defaults.set(Data(old.utf8), forKey: FlatdConnection.namesKeyOfBuild2)
        try connection.forget()
        #expect(connection.devicesVersion == nil)
        #expect(defaults.object(forKey: FlatdConnection.namesKeyOfBuild2) == nil)
        // Names kept for one pairing are never another's, even when the file stayed.
        try connection.save(Flat.pairing())
        connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id)
        try connection.save(Flat.pairing(id: UUID()))
        #expect(connection.known == nil)
    }
}

#if targetEnvironment(simulator)
/// A program of the Mac started from the test (only the simulator can).
private struct OtherProcess {
    struct NotStarted: Error { let code: Int32 }
    let pid: pid_t

    /// `output`: where what it prints goes (its errors too), to say why it failed.
    init(_ arguments: [String], output: String) throws {
        var pid: pid_t = 0
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, output, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
        var argv: [UnsafeMutablePointer<CChar>?] = arguments.map { strdup($0) } + [nil]
        defer { argv.forEach { free($0) } }
        // Not this process's environment: the simulator's (`DYLD_ROOT_PATH` …) would load iOS libraries into it.
        var environment: [UnsafeMutablePointer<CChar>?] = [strdup("PATH=/usr/bin:/bin"), nil]
        defer { environment.forEach { free($0) } }
        let code = posix_spawn(&pid, arguments[0], &actions, nil, &argv, &environment)
        guard code == 0 else { throw NotStarted(code: code) }
        self.pid = pid
    }

    /// Its exit code, once it ended.
    func wait() -> Int32 {
        var status: Int32 = 0
        while waitpid(pid, &status, 0) == -1, errno == EINTR {}
        return (status & 0x7f) == 0 ? (status >> 8) & 0xff : -1
    }
}
#endif
