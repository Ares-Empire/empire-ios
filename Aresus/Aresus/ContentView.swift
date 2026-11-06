import SwiftUI
import UIKit

/// The Aresus app: the shared Empire login, then the three tabs. Logged in once in any Empire app means logged in here.
/// Links (`aresus://…`) and notification taps go through `AresusNavigation`.
/// DEBUG launch arguments: `-sampleData` (`-sampleAllGood`), `-tab aresus|aresync|board`, `-openProvince <slug>`,
/// `-openRun <id>`, `-sampleLogin` / `-sampleNoAccess` / `-sampleAccessAsked` (`SampleAccount`) / `-sampleLoading` for
/// the login, no-access and loading screens,
/// `-widgetGallery good|issues|loggedout` for the widget's views, `-sampleShareExtension` (with `-sampleData`; and
/// `-sampleShareState loading|loggedOut|unreadable`) for the share extension's made-up login, and `-sampleDropHover
/// <count or name>` for the Aresync tab's drop hover (`AresusTabs`).
struct ContentView: View {
    @State private var store: AresusStore
    @State private var board: BoardStore
    @State private var drops: DropsStore
    @State private var navigation: AresusNavigation
    @State private var markImages: [String: UIImage] = [:]
    // State, like the store: SwiftUI may build this view again (a new session each time); the marks must keep using
    // the store's session, or they see a logged-out one and load nothing.
    @State private var marks: ProvinceMarks
    private let restoresOnLaunch: Bool
    private let push: PushCenter?
    #if DEBUG
    private let widgetGallery: WidgetGallery.Page?
    #endif
    @Environment(\.scenePhase) private var scenePhase
    private var session: EmpireSession { store.session }

    init(push: PushCenter? = nil, arguments: [String] = LaunchArguments.current) {
        let samples = AresusSamples.launched(arguments: arguments)
        #if DEBUG
        if arguments.contains("-sampleShareExtension") {
            // The share extension's made-up login and folders, and with `-sampleShareState loading|loggedOut|unreadable`
            // one of its other screens (ShareViewController's `SharePreview`).
            let group = UserDefaults(suiteName: DropContainer.appGroup)
            group?.set(samples != nil, forKey: "aresus.drops.preview")
            let state = arguments.firstIndex(of: "-sampleShareState").flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            group?.set(state, forKey: "aresus.drops.preview.state")
        }
        #endif
        #if DEBUG
        // Tests (the app is their host), samples and the screenshot screens never touch the real login.
        let testing = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let gallery = WidgetGallery.Page.launched(arguments: arguments)
        // Screenshots of the login and the no-access screen (`SampleAccount`): a made-up account, no server.
        let account = SampleAccount.session(app: .aresus, arguments: arguments)
        let quiet = samples != nil || testing || gallery != nil || account != nil
        var session = account?.session
            ?? EmpireSession(app: .aresus, restoreOnLaunch: !quiet, sharedDefaults: quiet ? nil : EmpireShared.defaults)
        var restores = account?.restores ?? !quiet
        if arguments.contains("-sampleLoading") {
            // Loading: a restore that never runs keeps the loading screen up.
            session = EmpireSession(app: .aresus, storage: DebugTokens(), restoreOnLaunch: true)
            restores = false
        }
        let navigation = AresusNavigation.launched(arguments: arguments)
        // Like push: samples, tests and the screenshot screens never write the widget's status.
        let widget: WidgetStatusPublisher = restores ? .live() : .disabled
        widgetGallery = gallery
        // Samples, tests and the screenshot screens never register for push.
        self.push = restores ? push : nil
        #else
        let session = EmpireSession(app: .aresus, sharedDefaults: EmpireShared.defaults)
        let restores = true
        let navigation = AresusNavigation()
        let widget = WidgetStatusPublisher.live()
        self.push = push
        #endif
        let dropEnvironment = DropAppActivity.environment(enabled: restores)
        _store = State(initialValue: AresusStore(session: session, samples: samples, widget: widget))
        _drops = State(initialValue: DropsStore(session: session, samples: samples, automatic: restores || samples != nil,
                                                activity: dropEnvironment.activity,
                                                legacyDirectory: dropEnvironment.legacyDirectory,
                                                legacyDefaults: dropEnvironment.legacyDefaults,
                                                legacyCacheURL: dropEnvironment.legacyCacheURL))
        _board = State(initialValue: BoardStore(session: session, samples: samples,
                                               failNextSend: arguments.contains("-sampleBoardFailed")))
        _navigation = State(initialValue: navigation)
        _marks = State(initialValue: ProvinceMarks(session: session, sample: samples != nil))
        restoresOnLaunch = restores
    }

    var body: some View {
        #if DEBUG
        if let widgetGallery {
            WidgetGallery(page: widgetGallery)
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
                AresusTabs(store: store, drops: drops, board: board, navigation: navigation, marks: markImages, logOut: logOut)
                    .task(id: logos) { await loadMarks() }
            } else if session.isRestoring {
                ProvinceLoading(name: "Aresus", bust: Image("Bust"), accent: .aresus)
            } else {
                ProvinceLogin(session: session, name: "Aresus", bust: Image("Bust"), accent: .aresus)
            }
        }
        .task {
            push?.start(app: "de.ares-empire.aresus", session: session)
            if restoresOnLaunch { await session.restore() }
            await drops.outbox?.reconnect()
            await drops.outbox?.recoverSharedUploads()
            drops.outbox?.start()
        }
        .onChange(of: push?.openedURL) { _, url in
            if url != nil, let url = push?.takeOpenedURL() { navigation.open(url) }
        }
        .onEmpireForeground(session: session) {
            await session.followSharedLogin()        // another Empire app may have logged in or out
            await store.refreshOnForeground(visible: navigation.visibleParts)
            await drops.outbox?.reconnect()
            await drops.outbox?.recoverSharedUploads()
            drops.recentFolders.reload()
            drops.outbox?.start()
            if navigation.tab == .aresync { await drops.refresh(olderThan: 10) }
            await board.refresh(olderThan: 10)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await board.leavingForeground() } }
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
            drops.leaveSample()
            board.leaveSample()
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
/// The loading screenshot's login: kept in memory, never in the shared Keychain.
private final class DebugTokens: TokenStorage {
    private var token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

#Preview { ContentView(arguments: ["-sampleData"]) }
#endif
