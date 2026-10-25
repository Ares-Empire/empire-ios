import SwiftUI
import UserNotifications

/// Arestemis: the shared Empire login, then three tabs (Hunt, Listings, Search). Logged in once in any Empire app means
/// logged in here. `-sampleData` shows the bundled samples (see `LaunchOptions` for the screenshot arguments).
/// A new match arrives as a push (Shared/Push); tapping it, or its "Open listing" / "Application" action, opens the match.
struct ContentView: View {
    @State private var store: ArestemisStore
    @State private var navigation = AppNavigation()
    @Environment(\.scenePhase) private var scenePhase
    private let options: LaunchOptions
    private let restoresOnLaunch: Bool
    private let push: PushCenter?
    private var session: EmpireSession { store.session }

    init(push: PushCenter? = nil, arguments: [String] = LaunchArguments.current) {
        let options = LaunchOptions(arguments: arguments)
        #if DEBUG
        // Tests (the app is their host) and samples never touch the real login.
        let testing = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // Screenshots of the login and the no-access screen (`SampleAccount`): a made-up account, no server.
        let account = SampleAccount.session(app: .arestemis, arguments: arguments)
        let quiet = options.sample || testing || account != nil
        let installDefaults = quiet ? nil : EmpireShared.defaults
        self.push = quiet ? nil : push          // samples and tests never register for push
        let session = account?.session
            ?? EmpireSession(app: .arestemis, restoreOnLaunch: !quiet, installDefaults: installDefaults)
        restoresOnLaunch = account?.restores ?? !quiet
        #else
        let installDefaults = EmpireShared.defaults
        self.push = push
        let session = EmpireSession(app: .arestemis, restoreOnLaunch: true, installDefaults: installDefaults)
        restoresOnLaunch = true
        #endif
        _store = State(initialValue: Self.makeStore(session: session, options: options))
        self.options = options
    }

    private static func makeStore(session: EmpireSession, options: LaunchOptions) -> ArestemisStore {
        #if DEBUG
        if options.sample, let sample = try? SampleBackend(options: .init(noHunt: options.noHunt, paused: options.paused,
                                                                             hangs: options.loading)) {
            return ArestemisStore(session: session, backend: sample, sample: true)
        }
        #endif
        return ArestemisStore(session: session, backend: ArestemisAPI(token: { session.token }))
    }

    var body: some View {
        Group {
            if store.isSample || session.isSignedIn {
                if store.overview != nil {
                    MainTabs(store: store, navigation: navigation, logOut: logOut,
                             scrollTarget: store.isSample ? options.scrollTo : nil)
                } else {
                    ProvinceLoading(name: "Arestemis", bust: Image("Bust"), accent: Look.accent,
                                    message: store.isLoadingOverview ? nil : store.overviewError,
                                    retry: { Task { await store.reloadOverview() } },
                                    logOut: logOut)
                        .task { if store.overview == nil { await store.reloadOverview() } }
                }
            } else if session.isRestoring {
                ProvinceLoading(name: "Arestemis", bust: Image("Bust"), accent: Look.accent)
            } else {
                ProvinceLogin(session: session, name: "Arestemis", bust: Image("Bust"), accent: Look.accent)
            }
        }
        .task {
            push?.start(app: "de.ares-empire.arestemis", session: session,
                        categories: Array(MatchNotification.categories))
            if restoresOnLaunch { await session.restore() }
        }
        .onChange(of: push?.openedURL) { _, url in
            guard url != nil, let push else { return }
            let action = push.lastActionIdentifier ?? UNNotificationDefaultActionIdentifier
            if let link = MatchNotification.link(url: push.takeOpenedURL(), action: action) { navigation.follow(link) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await session.followSharedLogin()        // another Empire app may have logged in or out
                await store.refreshOnForeground()
            }
        }
        .onChange(of: session.generation) { _, _ in
            if !session.isSignedIn { navigation.reset() }
        }
        .onChange(of: store.overview != nil) { _, loaded in
            if loaded { options.apply(to: navigation, firstMatch: store.latest.first?.id) }
        }
        .onOpenURL { url in
            if let link = ArestemisLink(url: url) { navigation.follow(link) }
        }
    }

    /// Logging out ends the shared login (every Empire app); in sample mode it leaves the sample for the real login.
    private func logOut() {
        navigation.reset()
        if store.isSample {
            store.clear()
            let session = EmpireSession(app: .arestemis, restoreOnLaunch: false, installDefaults: EmpireShared.defaults)
            store = ArestemisStore(session: session, backend: ArestemisAPI(token: { session.token }))
        } else {
            session.logOut()
        }
    }
}

/// The three tabs, the sheets over them, and the notice for a failed action.
private struct MainTabs: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    let logOut: () -> Void
    var scrollTarget: String? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Hunt", systemImage: "scope", value: AppTab.hunt) {
                HuntScreen(store: store, navigation: navigation, scrollsToBottom: scrollTarget == "bottom")
            }
            Tab("Listings", systemImage: "list.bullet.rectangle", value: AppTab.listings) {
                ListingsScreen(store: store, navigation: navigation)
            }
            Tab("Search", systemImage: "slider.horizontal.3", value: AppTab.search) {
                SearchScreen(store: store, navigation: navigation, scrollTarget: scrollTarget)
            }
        }
        .tint(Look.accent.color)
        .sheet(item: $navigation.sheet) { sheet in
            Group {
                switch sheet {
                case .settings: SettingsSheet(store: store, logOut: logOut)
                case .rejected: RejectedSheet(store: store)
                case .application(let id): ApplicationSheet(matchID: id, store: store)
                }
            }
            .presentationDetents(sheet == .settings ? [.large] : [.medium, .large])
            .presentationBackground(Ink.background)
        }
        .overlay(alignment: .top) {
            if let notice = store.notice {
                NoticeBanner(text: notice.text) { store.dismissNotice() }
                    .padding(.top, 6)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(5))
                        if store.notice?.id == notice.id { store.dismissNotice() }
                    }
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.notice)
        .task(id: navigation.pendingListing) { await openPendingListing() }
        .task(id: navigation.pendingLink) {
            guard navigation.pendingLink != nil else { return }
            try? await Task.sleep(for: .milliseconds(150))      // the tabs are laid out first
            navigation.openPendingLink()
        }
    }

    /// A notification's "Open listing": the match is shown, and its portal page opens.
    private func openPendingListing() async {
        guard let id = navigation.pendingListing else { return }
        let match = await store.loadMatch(id)
        if navigation.pendingListing == id { navigation.pendingListing = nil }
        if let url = match?.listing.portalURL { openURL(url) }
    }
}

#if DEBUG
#Preview { ContentView(arguments: ["-sampleData"]) }
#endif
