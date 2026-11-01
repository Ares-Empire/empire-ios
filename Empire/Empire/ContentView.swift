import SwiftUI
import UIKit
import UserNotifications

/// The Empire app: the shared login, then the throne room (the approved phone hub, ares-empire web/app/mobile.jsx).
/// Logged in once in any Empire app means logged in here. `-sampleData` (`-sampleUser`, `-sampleCatalog`) shows the
/// bundled samples. Notifications (Shared/Push): "<App> is ready" (a request was approved) shows the ring, refreshed.
struct ContentView: View {
    @State private var store: EmpireStore
    @State private var navigation = EmpireNavigation()
    @State private var markImages: [String: UIImage] = [:]
    @State private var showsSettings = false
    // State, like the store: SwiftUI may build this view again (a new session each time); the marks must keep using
    // the store's session, or they see a logged-out one and load nothing.
    @State private var marks: ProvinceMarks
    private let restoresOnLaunch: Bool
    private let push: PushCenter?
    #if DEBUG
    /// `-samplePush`: the sample with push routing, to try a notification tap on the simulator. The sample never signs
    /// in, so no device is registered with the push service.
    private let samplePush: Bool
    /// Screenshots: `-openSheet support` opens the contact form (Shared/Support) over the home.
    @State private var showsSupport: Bool
    #endif
    private var session: EmpireSession { store.session }

    init(push: PushCenter? = nil, arguments: [String] = LaunchArguments.current) {
        let sample = EmpireSamples.enabled(arguments: arguments)
        #if DEBUG
        // Tests (the app is their host) and samples never touch the real login.
        let testing = NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let quiet = sample || testing
        #else
        let quiet = false
        #endif
        var session: EmpireSession
        var restores = !quiet
        #if DEBUG
        // Screenshots of the login and the no-access screen (`SampleAccount`): a made-up account, no server.
        let account = SampleAccount.session(app: .empire, arguments: arguments)
        if let account {
            session = account.session
            restores = account.restores
        } else {
            session = EmpireSession(app: .empire, restoreOnLaunch: !quiet, sharedDefaults: quiet ? nil : EmpireShared.defaults)
        }
        // Samples, tests and the screenshot screens never register for push (`-samplePush` routes taps only).
        samplePush = sample && arguments.contains("-samplePush")
        self.push = (quiet || account != nil) && !samplePush ? nil : push
        #else
        session = EmpireSession(app: .empire, restoreOnLaunch: !quiet, sharedDefaults: quiet ? nil : EmpireShared.defaults)
        self.push = push
        #endif
        _store = State(initialValue: EmpireStore(session: session, sample: sample))
        _marks = State(initialValue: ProvinceMarks(session: session, sample: sample))
        restoresOnLaunch = restores
        #if DEBUG
        let sheet = arguments.firstIndex(of: "-openSheet").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        _showsSupport = State(initialValue: sheet == "support")
        #endif
    }

    var body: some View {
        Group {
            if store.isSample || session.isSignedIn {
                if let data = store.data {
                    EmpireHome(data: data, marks: markImages, status: status, actions: actions, navigation: navigation)
                        .task(id: logos(data)) { await loadMarks(data) }
                } else {
                    EmpireLoading(message: store.isLoading ? nil : store.error,
                                  retry: { Task { await store.reload() } },
                                  logOut: { session.logOut() })
                        .task { if store.data == nil { await store.reload() } }
                }
            } else if session.isRestoring {
                EmpireLoading()
            } else {
                EmpireLogin(session: session)
            }
        }
        .task {
            push?.start(app: "de.ares-empire.empire", session: session)
            #if DEBUG
            if samplePush {     // the simulator shows a test push only to an app allowed to notify
                _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: PushCenter.permissionOptions)
            }
            #endif
            if restoresOnLaunch { await session.restore() }
        }
        // `initial`: a tap that launched the app may be handed over before this view first appears.
        .onChange(of: push?.openedURL, initial: true) { _, url in
            guard url != nil, let url = push?.takeOpenedURL() else { return }
            showsSettings = false
            Task { await navigation.open(url, store: store) }
        }
        #if DEBUG
        .sheet(isPresented: $showsSupport) { SupportSheet(session: session, sample: store.isSample) }
        #endif
        .onEmpireForeground(session: session) {
            await session.followSharedLogin()        // another Empire app may have logged in or out
            await store.refreshOnForeground()
        }
        .onChange(of: session.generation) { _, _ in
            markImages = [:]
            if !session.isSignedIn { navigation.reset() }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsScreen(app: SettingsApp(name: "Empire", sendsNotifications: true), session: session,
                           sample: store.isSample,
                           logOut: { store.session.logOut() })
        }
    }

    private var status: EmpireHomeStatus {
        EmpireHomeStatus(requesting: store.requesting, requestError: store.requestError, approvals: store.approvals,
                         approvalsLoading: store.isLoadingApprovals, approvalsError: store.approvalsError,
                         deciding: store.isDeciding, loadError: store.error)
    }

    private var actions: EmpireHomeActions {
        let store = store
        return EmpireHomeActions(
            open: { province in await ProvinceOpener().open(province) != .notOpened },
            request: { slug in await store.request(slug) },
            loadApprovals: { await store.loadApprovals() },
            decide: { account, approve in
                await store.decide(id: account.id, approve: approve, requested: account.requested)
            },
            openSettings: { showsSettings = true },
            refresh: { await store.reload() })
    }

    /// Every province this account can see, with its mark on the hub.
    private func logos(_ data: EmpireData) -> [String] {
        (data.projects + data.addable).map { $0.slug + "=" + $0.logo }
    }

    private func loadMarks(_ data: EmpireData) async {
        for province in data.projects + data.addable where markImages[province.slug] == nil && !province.logo.isEmpty {
            if let image = await marks.image(for: province.logo) { markImages[province.slug] = image }
        }
    }
}
