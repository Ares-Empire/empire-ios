import Foundation
import UIKit
import UserNotifications

/// The app delegate an Empire app adopts for push: `@UIApplicationDelegateAdaptor(PushAppDelegate.self) var delegate`
/// in its `App`, then `delegate.push.start(app:session:categories:)` once the session exists, and it routes
/// `delegate.push.openedURL`.
///
/// The delegate owns the app's `PushCenter` (no singleton): UIKit creates the delegate before the first scene, and the
/// app reaches the center through the adaptor. It forwards what only the application object gets: the device token,
/// the registration failure, taps on notifications, and becoming active (each foreground refreshes the registration).
/// It uses only the `application` UIKit hands it, never `UIApplication.shared`, because Shared is also compiled into
/// widget extensions.
class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let push = PushCenter()
    private var activeObserver: NSObjectProtocol?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Must be set before launching ends, or a tap that launched the app is lost.
        UNUserNotificationCenter.current().delegate = self
        push.registerForRemote = { [weak application] in application?.registerForRemoteNotifications() }
        activeObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification, object: application, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.push.refresh() }
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        push.didFailToRegister(error)
    }

    /// Banners also while the app is open.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let url = PushCenter.url(from: response.notification.request.content.userInfo)
        await push.open(action: action, url: url)
    }
}
