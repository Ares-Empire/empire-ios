import SwiftUI
import UIKit

/// The Empire app: the shared login, then the throne room (the approved phone hub, ares-empire web/app/mobile.jsx).
/// Logged in once in any Empire app means logged in here. `-sampleData` (`-sampleUser`) shows the bundled samples.
struct ContentView: View {
    @State private var store: EmpireStore
    @State private var markImages: [String: UIImage] = [:]
    @State private var showsSettings = false
    @Environment(\.scenePhase) private var scenePhase
    // State, like the store: SwiftUI may build this view again (a new session each time); the marks must keep using
    // the store's session, or they see a logged-out one and load nothing.
    @State private var marks: ProvinceMarks
    private let restoresOnLaunch: Bool
    #if DEBUG
    /// Screenshots: `-openSheet support` opens the contact form (Shared/Support) over the home.
    @State private var showsSupport: Bool
    #endif
    private var session: EmpireSession { store.session }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
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
        if let account = SampleAccount.session(app: .empire, arguments: arguments) {
            session = account.session
            restores = account.restores
        } else {
            session = EmpireSession(app: .empire, restoreOnLaunch: !quiet, installDefaults: quiet ? nil : EmpireShared.defaults)
        }
        #else
        session = EmpireSession(app: .empire, restoreOnLaunch: !quiet, installDefaults: quiet ? nil : EmpireShared.defaults)
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
                    EmpireHome(data: data, marks: markImages, status: status, actions: actions)
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
        .task { if restoresOnLaunch { await session.restore() } }
        #if DEBUG
        .sheet(isPresented: $showsSupport) { SupportSheet(session: session, sample: store.isSample) }
        #endif
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task {
                    await session.followSharedLogin()        // another Empire app may have logged in or out
                    await store.refreshOnForeground()
                }
            }
        }
        .onChange(of: session.generation) { _, _ in markImages = [:] }
        .sheet(isPresented: $showsSettings) {
            SettingsScreen(app: SettingsApp(name: "Empire"), session: session, sample: store.isSample,
                           logOut: { store.session.logOut() })
        }
    }

    private var status: EmpireHomeStatus {
        EmpireHomeStatus(ringBusy: store.isRingBusy, ringError: store.ringError, approvals: store.approvals,
                         approvalsLoading: store.isLoadingApprovals, approvalsError: store.approvalsError,
                         deciding: store.isDeciding, loadError: store.error)
    }

    private var actions: EmpireHomeActions {
        let store = store
        return EmpireHomeActions(
            open: { province in Task { await ProvinceOpener().open(province) } },
            add: { slug in await store.ring(add: slug); return store.ringError == nil },
            remove: { slug in await store.ring(remove: slug); return store.ringError == nil },
            loadApprovals: { await store.loadApprovals() },
            decide: { id, approve in await store.decide(id: id, approve: approve); return store.approvalsError == nil },
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
