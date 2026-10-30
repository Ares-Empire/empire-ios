import SwiftUI
import UserNotifications

@main
struct AresiumApp: App {
    @UIApplicationDelegateAdaptor(InboxLaunchDelegate.self) private var launchDelegate
    /// The lock and its window, one per launch: a language restart builds the screens again but keeps them (it is no
    /// new launch, so it does not lock).
    @State private var lockWindow: LockWindow

    init() {
        AppFont.register()
        _lockWindow = State(initialValue: LockWindow(lock: AppLock.forLaunch()))
    }

    var body: some Scene {
        WindowGroup { AppRoot(widget: .aresium) { ContentView(lockWindow: lockWindow) } }
    }
}

/// A fresh configuration lets SwiftUI wrap our delegate without wrapping its own delegate again.
final class InboxLaunchDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions { [.banner, .sound, .list] }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let url = PushCenter.url(from: response.notification.request.content.userInfo)
        await MessageTapRouter.shared.open(action: action, url: url)
    }

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = InboxSceneDelegate.self
        return configuration
    }
}

final class InboxSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        ImportFileReader.clearInbox(excluding: connectionOptions.urlContexts.map(\.url))
    }
}
