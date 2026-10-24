import SwiftUI
import UIKit

/// The Aresus app: the shared Empire login, then the two tabs. Logged in once in any Empire app means logged in here.
/// Links (`aresus://…`, later also notification taps) go through `AresusNavigation`.
/// DEBUG launch arguments: `-sampleData` (`-sampleAllGood`), `-tab aresus|aresync`, `-openProvince <slug>`,
/// `-openRun <id>`, and `-sampleLogin` / `-sampleLoading` for the login and loading screens.
struct ContentView: View {
    @State private var store: AresusStore
    @State private var navigation: AresusNavigation
    @State private var markImages: [String: UIImage] = [:]
    @Environment(\.scenePhase) private var scenePhase
    private let marks: ProvinceMarks
    private let restoresOnLaunch: Bool
    private var session: EmpireSession { store.session }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let samples = AresusSamples.launched(arguments: arguments)
        #if DEBUG
        // Tests (the app is their host), samples and the screenshot screens never touch the real login.
        let testing = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let quiet = samples != nil || testing
        var session = EmpireSession(app: .aresus, restoreOnLaunch: !quiet, installDefaults: quiet ? nil : EmpireShared.defaults)
        var restores = !quiet
        if arguments.contains("-sampleLogin") || arguments.contains("-sampleLoading") {
            // Loading: a restore that never runs keeps the loading screen up.
            session = EmpireSession(app: .aresus, storage: DebugTokens(), restoreOnLaunch: arguments.contains("-sampleLoading"))
            restores = false
        }
        let navigation = AresusNavigation.launched(arguments: arguments)
        #else
        let session = EmpireSession(app: .aresus, installDefaults: EmpireShared.defaults)
        let restores = true
        let navigation = AresusNavigation()
        #endif
        _store = State(initialValue: AresusStore(session: session, samples: samples))
        _navigation = State(initialValue: navigation)
        marks = ProvinceMarks(session: session, sample: samples != nil)
        restoresOnLaunch = restores
    }

    var body: some View {
        Group {
            if store.isSample || session.isSignedIn {
                AresusTabs(store: store, navigation: navigation, marks: markImages, logOut: logOut)
                    .task(id: logos) { await loadMarks() }
            } else if session.isRestoring {
                ProvinceLoading(name: "Aresus", bust: Image("Bust"), accent: .aresus)
            } else {
                ProvinceLogin(session: session, name: "Aresus", bust: Image("Bust"), accent: .aresus)
            }
        }
        .preferredColorScheme(.dark)
        .task { if restoresOnLaunch { await session.restore() } }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await session.followSharedLogin()        // another Empire app may have logged in or out
                await store.refreshOnForeground(visible: navigation.visibleParts)
            }
        }
        .onChange(of: session.generation) { _, _ in
            markImages = [:]
            if !session.isSignedIn { navigation.reset() }
        }
        .onOpenURL { url in navigation.open(url) }
    }

    private func logOut() {
        #if DEBUG
        if store.isSample {
            store.leaveSample()
            navigation.reset()
            return
        }
        #endif
        session.logOut()
    }

    /// The provinces on the watchtower, with their marks on the hub.
    private var logos: [String] {
        (store.overview?.provinces ?? []).compactMap { province in province.logo.map { province.slug + "=" + $0 } }
    }

    private func loadMarks() async {
        for province in store.overview?.provinces ?? [] where markImages[province.slug] == nil {
            guard let logo = province.logo, !logo.isEmpty else { continue }
            if let image = await marks.image(for: logo) { markImages[province.slug] = image }
        }
    }
}

#if DEBUG
/// The login of the screenshot screens: kept in memory, never in the shared Keychain.
private final class DebugTokens: TokenStorage {
    private var token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

#Preview { ContentView(arguments: ["-sampleData"]) }
#endif
