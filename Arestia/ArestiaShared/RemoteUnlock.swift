import Foundation
import LocalAuthentication
import Security

nonisolated enum RemoteUnlock {
    private static let marker = Data("arestia-remote-unlock".utf8)

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "de.ares-empire.arestia.remote-unlock",
         kSecAttrAccount as String: "lock-marker",
         kSecAttrAccessGroup as String: ArestiaGroup.keychainAccessGroup,
         kSecAttrSynchronizable as String: false]
    }

    private static func read() -> (OSStatus, Data?) {
        var attributes = query
        attributes[kSecReturnData as String] = true
        attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(attributes as CFDictionary, &item)
        return (status, item as? Data)
    }

    static func allowsRemote() -> Bool {
        let (status, data) = read()
        return status == errSecSuccess && data == marker
    }

    static func needsPasscode() -> Bool {
        var reason: NSError?
        _ = LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &reason)
        return reason?.domain == LAError.errorDomain && reason?.code == LAError.passcodeNotSet.rawValue
    }

    /// Called from the app on activation.
    static func createIfMissing(_ hold: Hold) throws {
        guard read().0 == errSecItemNotFound else { return }
        var attributes = query
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
        attributes[kSecValueData as String] = marker
        try hold.commit {}
        SecItemAdd(attributes as CFDictionary, nil)
    }
}
