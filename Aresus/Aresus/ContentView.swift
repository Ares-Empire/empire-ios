import SwiftUI
import UIKit

/// The Aresus app: the shared Empire login, then the two tabs. Logged in once in any Empire app means logged in here.
/// Links (`aresus://…`) and notification taps go through `AresusNavigation`.
/// DEBUG launch arguments: `-sampleData` (`-sampleAllGood`), `-tab aresus|aresync`, `-openProvince <slug>`,
/// `-openRun <id>`, `-sampleLogin` / `-sampleLoading` for the login and loading screens, and
/// `-widgetGallery good|issues|loggedout` for the widget's views.
struct ContentView: View {
    @State private var store: AresusStore
    @State private var navigation: AresusNavigation
    @State private var markImages: [String: UIImage] = [:]
    @Environment(\.scenePhase) private var scenePhase
    // State, like the store: SwiftUI may build this view again (a new session each time); the marks must keep using
    // the store's session, or they see a logged-out one and load nothing.
    @State private var marks: ProvinceMarks
    private let restoresOnLaunch: Bool
    private let push: PushCenter?
    #if DEBUG
    private let widgetGallery: WidgetGallery.Page?
    #endif
    private var session: EmpireSession { store.session }

    init(push: PushCenter? = nil, arguments: [String] = ProcessInfo.processInfo.arguments) {
        let samples = AresusSamples.launched(arguments: arguments)
        #if DEBUG
        // Tests (the app is their host), samples and the screenshot screens never touch the real login.
        let testing = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let gallery = WidgetGallery.Page.launched(arguments: arguments)
        let quiet = samples != nil || testing || gallery != nil
        var session = EmpireSession(app: .aresus, restoreOnLaunch: !quiet, installDefaults: quiet ? nil : EmpireShared.defaults)
        var restores = !quiet
        if arguments.contains("-sampleLogin") || arguments.contains("-sampleLoading") {
            // Loading: a restore that never runs keeps the loading screen up.
            session = EmpireSession(app: .aresus, storage: DebugTokens(), restoreOnLaunch: arguments.contains("-sampleLoading"))
            restores = false
        }
        let navigation = AresusNavigation.launched(arguments: arguments)
        // Like push: samples, tests and the screenshot screens never write the widget's status.
        let widget: WidgetStatusPublisher = restores ? .live() : .disabled
        widgetGallery = gallery
        // Samples, tests and the screenshot screens never register for push.
        self.push = restores ? push : nil
        #else
        let session = EmpireSession(app: .aresus, installDefaults: EmpireShared.defaults)
        let restores = true
        let navigation = AresusNavigation()
        let widget = WidgetStatusPublisher.live()
        self.push = push
        #endif
        _store = State(initialValue: AresusStore(session: session, samples: samples, widget: widget))
        _navigation = State(initialValue: navigation)
        _marks = State(initialValue: ProvinceMarks(session: session, sample: samples != nil))
        restoresOnLaunch = restores
    }

    var body: some View {
        #if DEBUG
        if let widgetGallery {
            WidgetGallery(page: widgetGallery).preferredColorScheme(.dark)
        } else {
            app
        }
        #else
        app
        #endif
    }

    private var app: some View {
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
        .task {
            push?.start(app: "de.ares-empire.aresus", session: session)
            if restoresOnLaunch { await session.restore() }
        }
        .onChange(of: push?.openedURL) { _, url in
            if url != nil, let url = push?.takeOpenedURL() { navigation.open(url) }
        }
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
