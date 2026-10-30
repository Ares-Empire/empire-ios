import Foundation
import Observation
import UserNotifications
import os

/// What PushCenter needs from iOS's notification center; a protocol so tests can stand in for the permission dialog.
protocol PushPermissions {
    func authorizationStatus() async -> UNAuthorizationStatus
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
    func setCategories(_ categories: Set<UNNotificationCategory>)
}

struct SystemPushPermissions: PushPermissions {
    func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        // iOS's question over the app: no app switcher cover behind it (brief 47).
        SystemPrompt.begin()
        defer { SystemPrompt.end() }
        return try await UNUserNotificationCenter.current().requestAuthorization(options: options)
    }

    func setCategories(_ categories: Set<UNNotificationCategory>) {
        UNUserNotificationCenter.current().setNotificationCategories(categories)
    }
}

/// Push notifications for one Empire app (ares-empire/docs/PUSH.md). One per app, owned by `PushAppDelegate`; the app
/// calls `start` once its `EmpireSession` exists and routes `openedURL`.
///
/// - While signed in (each new session, and at every launch and foreground via the delegate): asks for permission
///   once, then asks iOS for the device token; each token iOS hands over is sent to the push service, which also tells
///   it the device is alive.
/// - When this app deletes the saved login on a person's logout: removes every recorded app's device with the ended
///   login. Following a logout elsewhere, or losing this app's access, removes only this app's device.
/// - A refused login cannot remove devices. Removal failures are logged without tokens and dropped locally.
/// - A 401 from the push service is a rejected login (the session's normal failure path); a 403 stops the tries for
///   this session.
/// - A tapped notification's `url` (or the URL the app maps a chosen action to) becomes `openedURL`.
///
/// Nothing here touches `UIApplication`: Shared is also compiled into widget extensions. The delegate hands in
/// `registerForRemote`.
@MainActor @Observable
final class PushCenter {
    /// The URL to open after a notification was tapped. The app routes it and calls `takeOpenedURL()`.
    private(set) var openedURL: URL?
    /// The action that produced `openedURL`: `UNNotificationDefaultActionIdentifier` for a plain tap, otherwise the
    /// identifier of the chosen `UNNotificationAction`.
    private(set) var lastActionIdentifier: String?
    /// The APNs device token as lowercase hex, once iOS handed it over.
    private(set) var deviceToken: String?
    /// Why iOS gave no device token (on the simulator and without the Push capability it never does).
    private(set) var registrationError: String?

    /// Asks iOS for the device token (`UIApplication.registerForRemoteNotifications`); set by `PushAppDelegate`.
    @ObservationIgnored var registerForRemote: () -> Void = {}

    @ObservationIgnored private let api: PushAPI
    @ObservationIgnored private let permissions: any PushPermissions
    @ObservationIgnored private let environment: PushEnvironment
    @ObservationIgnored private let devices: PushDeviceStore
    @ObservationIgnored private var app: String?
    @ObservationIgnored private var session: EmpireSession?
    @ObservationIgnored private var actionURL: (String, URL?) -> URL? = { _, url in url }
    /// What the push service holds for this device (sent or being sent), so it can be removed after logout.
    @ObservationIgnored private var registered: (empireToken: String, deviceToken: String)?
    /// The session generation in which the push service answered 403.
    @ObservationIgnored private var refusedGeneration: Int?
    @ObservationIgnored private var askedPermission = false
    /// Every step runs after the previous one, so the server sees register / remove in the order they were asked for.
    @ObservationIgnored private var queue: Task<Void, Never>?

    static let permissionOptions: UNAuthorizationOptions = [.alert, .sound, .badge]
    private static let log = Logger(subsystem: "de.ares-empire.shared", category: "push")

    init(api: PushAPI = PushAPI(), permissions: any PushPermissions = SystemPushPermissions(),
         environment: PushEnvironment = .current, sharedDefaults: UserDefaults? = EmpireShared.defaults) {
        self.api = api
        self.permissions = permissions
        self.environment = environment
        devices = PushDeviceStore(defaults: sharedDefaults)
    }

    /// Apps without push notifications still remove the other apps' devices on a person's logout. The session owns
    /// this cleanup-only center through its handler; it never requests permission or registers a device.
    static func removeDevicesOnLogout(of session: EmpireSession, sharedDefaults: UserDefaults?) {
        guard let sharedDefaults else { return }       // samples and tests stay isolated
        let center = PushCenter(sharedDefaults: sharedDefaults)
        center.removeDevicesOnLogout(of: session)
    }

    func removeDevicesOnLogout(of session: EmpireSession) {
        session.onLogout { [self] ended in unregister(ended: ended) }
    }

    /// Call when the app's session exists: at launch, and again with the new session after the app restarted in
    /// another language (`AppRoot`). Then the categories' action titles are set in the new language and, once
    /// the new session is signed in, the device registers again with the new language. The handlers of a replaced
    /// session do nothing any more.
    /// - Parameters:
    ///   - app: the app's bundle id, the `app` the push service knows (e.g. "de.ares-empire.arestemis").
    ///   - categories: the app's notification categories and their actions.
    ///   - actionURL: the URL to open for a chosen action (not for a plain tap), given the notification's `url`;
    ///     nil opens nothing. By default every action opens the notification's `url`.
    func start(app: String, session: EmpireSession, categories: [UNNotificationCategory] = [],
               actionURL: @escaping (_ action: String, _ url: URL?) -> URL? = { _, url in url }) {
        guard self.session !== session else { return }
        self.app = app
        self.session = session
        self.actionURL = actionURL
        refusedGeneration = nil
        permissions.setCategories(Set(categories))
        session.onSignIn { [weak self, weak session] in
            if let self, self.session === session { self.refresh() }
        }
        session.onLogout { [weak self, weak session] ended in
            if let self, self.session === session { self.unregister(ended: ended) }
        }
        session.onAppDataReset { [weak self, weak session] in
            // Logout is handled above.
            if let self, let session, self.session === session, session.isDenied { self.unregister() }
        }
        refresh()
    }

    /// While signed in: permission (asked once), then a fresh device token from iOS. At every launch and foreground.
    func refresh() {
        enqueue { [weak self] in await self?.requestDeviceToken() }
    }

    /// iOS handed over the device token (`application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`).
    func didRegister(deviceToken data: Data) {
        let token = Self.hex(data)
        deviceToken = token
        registrationError = nil
        enqueue { [weak self] in await self?.register(token) }
    }

    func didFailToRegister(_ error: Error) {
        registrationError = error.localizedDescription
    }

    /// The user tapped a notification or chose one of its actions.
    func open(action: String, url payloadURL: URL?) {
        guard action != UNNotificationDismissActionIdentifier else { return }
        let url = action == UNNotificationDefaultActionIdentifier ? payloadURL : actionURL(action, payloadURL)
        guard let url else { return }
        lastActionIdentifier = action
        openedURL = url
    }

    /// The URL to route now, once (a second tap on the same URL is a change again).
    func takeOpenedURL() -> URL? {
        defer { openedURL = nil }
        return openedURL
    }

    /// Waits for the steps asked for so far (tests).
    func idle() async {
        await queue?.value
    }

    /// The notification's `url` (docs/PUSH.md: the payload's custom key), if it is a URL with a scheme.
    nonisolated static func url(from userInfo: [AnyHashable: Any]) -> URL? {
        guard let text = userInfo["url"] as? String, let url = URL(string: text), url.scheme != nil else { return nil }
        return url
    }

    nonisolated static func hex(_ token: Data) -> String {
        token.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Steps

    private func enqueue(_ step: @escaping @MainActor () async -> Void) {
        let previous = queue
        queue = Task { @MainActor in
            await previous?.value
            await step()
        }
    }

    private var mayRegister: Bool {
        guard let session, session.isSignedIn, session.token != nil else { return false }
        return refusedGeneration != session.generation
    }

    private func requestDeviceToken() async {
        guard mayRegister else { return }
        var status = await permissions.authorizationStatus()
        if status == .notDetermined, !askedPermission {
            askedPermission = true
            _ = try? await permissions.requestAuthorization(options: Self.permissionOptions)
            status = await permissions.authorizationStatus()
        }
        guard mayRegister, [.authorized, .provisional, .ephemeral].contains(status) else { return }
        registerForRemote()
    }

    private func register(_ device: String) async {
        guard mayRegister, let app, let session, let empireToken = session.token else { return }
        let generation = session.generation
        registered = (empireToken, device)
        do {
            try await api.register(app: app, deviceToken: device, environment: environment, token: empireToken)
            devices.save(device, app: app)
        } catch HTTPError.unauthorized {
            if registered?.empireToken == empireToken { registered = nil }   // that token cannot remove it either
            session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: empireToken)
        } catch HTTPError.server(403, _) {
            refusedGeneration = generation
        } catch {
            // Offline or the service is down: the next launch or foreground tries again.
        }
    }

    private func unregister(ended: EmpireSession.EndedLogin? = nil) {
        let app = app
        let registered = registered
        self.registered = nil
        // A refused login cannot remove devices. In particular, never turn a refusal into another request/logout.
        guard ended?.wasRefused != true,
              let token = ended?.token ?? registered?.empireToken ?? session?.token else { return }
        let allApps = ended?.deletedSavedLogin == true
        enqueue { [api, devices] in
            // Read after any in-flight registration finished, so a 204 arriving after logout is removed as well.
            var removals = allApps ? devices.devices : [:]
            if let app, removals[app] == nil, let device = registered?.deviceToken ?? devices.devices[app] {
                removals[app] = device
            }
            for app in removals.keys.sorted() {
                guard let device = removals[app] else { continue }
                do {
                    try await api.unregister(app: app, deviceToken: device, token: token)
                } catch {
                    // No credentials, device tokens or server error bodies in the log. Offline logout is best effort.
                    Self.log.error("\(app, privacy: .public): push device removal failed; dropping its local record")
                }
                devices.remove(device, app: app)
            }
        }
    }
}
