import Foundation

/// What every Empire app on the device shares (entitlements in each app: the App Group and the Keychain group).
enum EmpireShared {
    /// App Group of all Empire apps. iOS deletes its data only when the LAST app of the group is removed, which is
    /// what the first-launch check needs (the Keychain survives every uninstall).
    nonisolated static let appGroup = "group.de.ares-empire.shared"
    /// Keychain access group of all Empire apps, without the team prefix (entitlement: $(AppIdentifierPrefix) + this).
    static let keychainGroup = "de.ares-empire.shared"
    /// Defaults shared by the Empire apps; nil only if the App Group entitlement is missing.
    nonisolated static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }
    /// "$(AppIdentifierPrefix)" from the app's Info.plist ("TEAMID." on a device, may be empty on the simulator).
    static var keychainAccessGroup: String {
        let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String ?? ""
        return prefix + keychainGroup
    }
}
