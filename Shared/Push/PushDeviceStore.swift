import Foundation

/// Devices accepted by the push service on this iPhone, including apps which are not running.
/// Only APNs device tokens go here; an Empire login token must never be saved in defaults.
struct PushDeviceStore {
    static let key = "empire.push.devices"
    let defaults: UserDefaults?

    var devices: [String: String] { defaults?.dictionary(forKey: Self.key) as? [String: String] ?? [:] }

    func save(_ device: String, app: String) {
        var devices = devices
        devices[app] = device
        defaults?.set(devices, forKey: Self.key)
    }

    /// A newer registration made while removal was in flight must stay recorded.
    func remove(_ device: String, app: String) {
        var devices = devices
        guard devices[app] == device else { return }
        devices.removeValue(forKey: app)
        defaults?.set(devices, forKey: Self.key)
    }
}
