import Foundation
import Observation
import UserNotifications

/// Retains a cold-launch tap until ContentView can pass it through the widget/file URL route, behind the lock window.
@MainActor @Observable
final class MessageTapRouter {
    static let shared = MessageTapRouter()
    private(set) var openedURL: URL?

    func open(action: String, url: URL?) {
        guard action == UNNotificationDefaultActionIdentifier, let url, AresiumURL(url: url) != nil else { return }
        openedURL = url
    }

    func take() -> URL? {
        defer { openedURL = nil }
        return openedURL
    }
}

extension DashboardStore {
    func installMessages(lock: AppLock, active: Bool) {
        guard active, !isSample else { return }
        #if DEBUG
        guard !DebugLaunch.isTesting else { return }
        #endif
        let messages = AresiumMessages.live
        self.messages = messages
        messages.setContext(MessageContext(phone: backend?.mode == .phone, locked: lock.isOn || lock.unreadable))
        messages.setPhoneMode(backend?.mode == .phone, ledger: phone?.ledger)
        messages.dashboardBuilt(dashboard)
        lock.messagePrivacyChanged = { [weak messages] locked in messages?.setLocked(locked) }
        #if DEBUG
        // Live simulator verification, with no sample data and no push registration.
        if LaunchArguments.current.contains("-enableMessages") { messages.setEnabled(true) }
        #endif
    }
}
