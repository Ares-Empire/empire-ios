import Foundation

// The flat service's data, as flatd sends it (contract: flatd's API.md, v1.3). Everything here is read leniently: a
// field the app does not know is kept and ignored, a missing optional field is nil, and an unknown device kind or event
// type is carried along instead of failing the whole answer ("Unknown fields are ignored by clients, so new fields can
// be added without breaking anything"). No device, room or flat name is ever written into the app: they all come from
// flatd at runtime.

/// Any JSON value. A device's `state` is an open object that the app merges key by key, as the 3D viewer does
/// (`{...dev.state, ...state}`), so a state event that carries only some fields never drops the others.
nonisolated enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case let .bool(value): try container.encode(value)
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        case let .array(value): try container.encode(value)
        case let .object(value): try container.encode(value)
        }
    }
}

/// flatd's times: ISO 8601 as Python writes them ("2026-11-19T18:42:05Z", "…05.123456+00:00", "…05+01:00").
nonisolated enum FlatdDate {
    static func parse(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        if let date = plain.date(from: text) { return date }
        // Fractional seconds: Foundation reads up to three digits reliably; Python sends six. Cut to three.
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = text[text.index(after: dot)...].dropFirst(digits.count)
        let trimmed = text[..<dot] + "." + digits.prefix(3).padding(toLength: 3, withPad: "0", startingAt: 0) + rest
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: String(trimmed))
    }

    static func string(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// Which way a Rollo is moving (its state's `moving`).
nonisolated enum RolloMotion: String, Equatable, Sendable {
    case up, down
}

/// One device's state: the fields flatd sends, merged as they arrive, read through typed accessors.
/// Switches (fans, plugs, lights): `on`, `online`, `power_w`, `energy_wh`, `updated_at`, and `off_at` while a timer runs.
/// Rollos: `position` (percent closed: 0 fully up and open, 100 fully down), `moving`, `target`, `favourite`, `online`.
nonisolated struct DeviceState: Equatable, Sendable, Codable {
    var fields: [String: JSONValue]

    init(fields: [String: JSONValue] = [:]) { self.fields = fields }

    init(from decoder: Decoder) throws {
        fields = try [String: JSONValue](from: decoder)
    }

    func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }

    /// This state with the fields of `patch` laid over it (a state event may carry only what changed).
    func merging(_ patch: DeviceState) -> DeviceState {
        DeviceState(fields: fields.merging(patch.fields) { _, new in new })
    }

    var on: Bool? { if case let .bool(value)? = fields["on"] { value } else { nil } }
    /// Offline only when flatd says so; a device without the field counts as online.
    var online: Bool { if case let .bool(value)? = fields["online"] { value } else { true } }
    var powerW: Double? { number("power_w") }
    /// When a running fan switches itself off (its `for_s` timer, done by the plug); nil without a timer.
    var offAt: Date? { date("off_at") }
    var updatedAt: Date? { date("updated_at") }
    /// Percent closed, 0…100.
    var position: Int? { percent("position") }
    var target: Int? { percent("target") }
    /// The motor's stored "my" spot, percent closed; nil when the Rollo has none.
    var favourite: Int? { percent("favourite") }
    var moving: RolloMotion? {
        if case let .string(value)? = fields["moving"] { RolloMotion(rawValue: value) } else { nil }
    }

    private func number(_ key: String) -> Double? {
        if case let .number(value)? = fields[key] { value } else { nil }
    }

    private func percent(_ key: String) -> Int? {
        number(key).map { Int(min(100, max(0, $0.rounded()))) }
    }

    private func date(_ key: String) -> Date? {
        if case let .string(value)? = fields[key] { FlatdDate.parse(value) } else { nil }
    }
}

/// A device flatd controls. Its id is the 3D viewer's id (`fan:<id>`, `rollo:<opening id>`), so the app, the viewer
/// and flatd name things the same way.
nonisolated struct Device: Identifiable, Equatable, Sendable, Codable {
    nonisolated enum Kind: Equatable, Sendable {
        case fan, light, rollo, plug
        case other(String)

        init(raw: String) {
            switch raw {
            case "fan": self = .fan
            case "light": self = .light
            case "rollo": self = .rollo
            case "plug": self = .plug
            default: self = .other(raw)
            }
        }
    }

    let id: String
    let kind: Kind
    /// The name to show everywhere: the one given in a rename (flatd keeps it), else flatd's config name.
    private(set) var label: String
    /// flatd's config name, which `label` goes back to when the own name is cleared (contract v1.3); nil from a flatd
    /// before v1.3, which cannot rename.
    private(set) var defaultLabel: String?
    let room: String?
    /// What a POST may change: `on`, `for_s` for switches; `command`, `position` for Rollos.
    let controls: [String]
    var state: DeviceState

    init(id: String, kind: Kind, label: String, defaultLabel: String? = nil, room: String? = nil,
         controls: [String] = [], state: DeviceState = DeviceState()) {
        self.id = id
        self.kind = kind
        self.label = label
        self.defaultLabel = defaultLabel
        self.room = room
        self.controls = controls
        self.state = state
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, label, room, controls, state
        case defaultLabel = "default_label"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        kind = Kind(raw: (try? container.decodeIfPresent(String.self, forKey: .kind)) ?? "")
        let label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? nil
        self.label = label.flatMap { $0.isEmpty ? nil : $0 } ?? id
        let defaultLabel = (try? container.decodeIfPresent(String.self, forKey: .defaultLabel)) ?? nil
        self.defaultLabel = defaultLabel.flatMap { $0.isEmpty ? nil : $0 }
        room = try? container.decodeIfPresent(String.self, forKey: .room)
        controls = (try? container.decodeIfPresent([String].self, forKey: .controls)) ?? []
        state = (try? container.decodeIfPresent(DeviceState.self, forKey: .state)) ?? DeviceState()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(kind.raw, forKey: .kind)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(defaultLabel, forKey: .defaultLabel)
        try container.encodeIfPresent(room, forKey: .room)
        try container.encode(controls, forKey: .controls)
        try container.encode(state, forKey: .state)
    }

    /// A Rollo that can go to its stored favourite spot.
    var hasFavourite: Bool { kind == .rollo && state.favourite != nil }

    /// Renamed: its name is not flatd's config name (false from a flatd that cannot rename).
    var hasOwnName: Bool { defaultLabel.map { $0 != label } ?? false }

    /// This device with the names `other` (the same device, as flatd sent it in a rename's answer or event) carries;
    /// its state stays as it is (state events follow it).
    func named(like other: Device) -> Device {
        var device = self
        device.label = other.label
        device.defaultLabel = other.defaultLabel ?? defaultLabel
        return device
    }
}

/// A stateful mode (v1.1: `cooking`). Persisted by flatd, so it survives a restart of the service.
nonisolated struct FlatMode: Identifiable, Equatable, Sendable, Codable {
    let id: String
    let label: String
    var active: Bool
    var since: Date?
    /// The devices it touches (for the app's "what it did" line).
    var devices: [String]

    init(id: String, label: String, active: Bool, since: Date? = nil, devices: [String] = []) {
        self.id = id
        self.label = label
        self.active = active
        self.since = since
        self.devices = devices
    }

    private enum CodingKeys: String, CodingKey { case id, label, active, since, devices }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? id
        active = (try? container.decodeIfPresent(Bool.self, forKey: .active)) ?? false
        since = ((try? container.decodeIfPresent(String.self, forKey: .since)) ?? nil).flatMap(FlatdDate.parse)
        devices = (try? container.decodeIfPresent([String].self, forKey: .devices)) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(label, forKey: .label)
        try container.encode(active, forKey: .active)
        try container.encode(since.map(FlatdDate.string), forKey: .since)
        try container.encode(devices, forKey: .devices)
    }

    static let cookingID = "cooking"
}

/// A one-shot scene (v1.1: `air_out`, `all_down`): no state, it just runs.
nonisolated struct FlatScene: Identifiable, Equatable, Sendable, Decodable {
    let id: String
    let label: String
    var devices: [String]

    init(id: String, label: String, devices: [String] = []) {
        self.id = id
        self.label = label
        self.devices = devices
    }

    private enum CodingKeys: String, CodingKey { case id, label, devices }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = (try? container.decodeIfPresent(String.self, forKey: .label)) ?? id
        devices = (try? container.decodeIfPresent([String].self, forKey: .devices)) ?? []
    }

    static let airOutID = "air_out"
    static let allDownID = "all_down"
}

/// One message of flatd's event stream (`/api/events`): a snapshot on connect, then one message per change, whoever
/// made it (the app, Claude, a wall button, a timer).
nonisolated enum FlatEvent: Equatable, Sendable {
    case snapshot(devices: [Device], modes: [FlatMode]?)
    case state(id: String, state: DeviceState, source: String?)
    case mode(FlatMode)
    /// A device's own details changed (v1.3: it was renamed), whoever did it: its new `label` and `default_label`.
    case device(Device)
    /// A message type this app does not know (newer flatd): ignored.
    case other

    /// The event as flatd sends it, for the 3D page (`flat3d.receive`, BRIDGE.md: "flatd's … as is").
    var json: Data? {
        let encoder = JSONEncoder()
        switch self {
        case let .snapshot(devices, modes):
            return try? encoder.encode(SnapshotOut(devices: devices, modes: modes ?? []))
        case let .state(id, state, source):
            return try? encoder.encode(StateOut(id: id, state: state, source: source))
        case let .mode(mode):
            return try? encoder.encode(ModeOut(mode: mode))
        case let .device(device):
            return try? encoder.encode(DeviceOut(device: device))
        case .other:
            return nil
        }
    }

    private struct SnapshotOut: Encodable { var type = "snapshot"; let devices: [Device]; let modes: [FlatMode] }
    private struct StateOut: Encodable { var type = "state"; let id: String; let state: DeviceState; let source: String? }
    private struct ModeOut: Encodable { var type = "mode"; let mode: FlatMode }
    private struct DeviceOut: Encodable { var type = "device"; let device: Device }

    static func decode(_ data: Data) -> FlatEvent? {
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { return nil }
        switch envelope.type {
        case "snapshot":
            guard let devices = envelope.devices else { return nil }
            return .snapshot(devices: devices, modes: envelope.modes)
        case "state":
            guard let id = envelope.id, let state = envelope.state else { return nil }
            return .state(id: id, state: state, source: envelope.source)
        case "mode":
            return envelope.mode.map(FlatEvent.mode)
        case "device":
            return envelope.device.map(FlatEvent.device)
        default:
            return .other
        }
    }

    private struct Envelope: Decodable {
        let type: String
        let devices: [Device]?
        let modes: [FlatMode]?
        let id: String?
        let state: DeviceState?
        let source: String?
        let mode: FlatMode?
        let device: Device?

        private enum CodingKeys: String, CodingKey { case type, devices, modes, id, state, source, mode, device }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            devices = try? container.decodeIfPresent([Device].self, forKey: .devices)
            modes = try? container.decodeIfPresent([FlatMode].self, forKey: .modes)
            id = try? container.decodeIfPresent(String.self, forKey: .id)
            state = try? container.decodeIfPresent(DeviceState.self, forKey: .state)
            source = try? container.decodeIfPresent(String.self, forKey: .source)
            mode = try? container.decodeIfPresent(FlatMode.self, forKey: .mode)
            device = try? container.decodeIfPresent(Device.self, forKey: .device)
        }
    }
}

/// The devices a mode or scene could not reach (`"failed": {"<device id>": "<reason>"}` in flatd's answer): the mode
/// still changes, so the app says which devices did not follow.
nonisolated struct CommandFailures: Decodable, Equatable, Sendable {
    let failed: [String: String]

    private enum CodingKeys: String, CodingKey { case failed }

    init(failed: [String: String] = [:]) { self.failed = failed }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // flatd's answer is a map; a list of ids (the history's form) is read too.
        if let map = try? container.decodeIfPresent([String: String].self, forKey: .failed) {
            failed = map
        } else if let ids = try? container.decodeIfPresent([String].self, forKey: .failed) {
            failed = Dictionary(ids.map { ($0, "") }, uniquingKeysWith: { first, _ in first })
        } else {
            failed = [:]
        }
    }

    var ids: [String] { failed.keys.sorted() }
}

/// What the app asks a device to do (POST /api/devices/{id}).
nonisolated enum DeviceCommand: Equatable, Sendable {
    /// A switch: on (optionally for a while: the plug switches itself back after `seconds`) or off.
    case power(on: Bool, seconds: Int? = nil)
    case rollo(RolloCommand)
    /// A Rollo to a position, percent closed.
    case position(Int)

    var body: [String: JSONValue] {
        switch self {
        case let .power(on, seconds):
            var body: [String: JSONValue] = ["on": .bool(on)]
            if on, let seconds { body["for_s"] = .number(Double(seconds)) }
            return body
        case let .rollo(command):
            return ["command": .string(command.rawValue)]
        case let .position(percent):
            return ["position": .number(Double(min(100, max(0, percent))))]
        }
    }
}

nonisolated enum RolloCommand: String, Equatable, Sendable, CaseIterable {
    case up, down, favourite, stop
}
