import Foundation

/// The account of the saved Empire login, readable after the first unlock even while the Keychain is locked.
/// Credentials stay in the Keychain; this is only the signal for whose saved data may be shown.
nonisolated enum LoginMarker {
    static let key = "empire.login.account"

    static func account(in defaults: UserDefaults?) -> String? {
        defaults?.string(forKey: key)
    }

    static func save(_ account: String, in defaults: UserDefaults?) {
        defaults?.set(account, forKey: key)
    }

    static func clear(in defaults: UserDefaults?) {
        defaults?.removeObject(forKey: key)
    }
}
