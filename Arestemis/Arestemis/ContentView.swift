import SwiftUI
import UserNotifications

/// Arestemis: the shared Empire login, then two tabs (Hunts, Listings: New | Searches); a hunt's search opens from the hunt. Logged in once in any Empire app means
/// logged in here. `-sampleData` shows the bundled samples (see `LaunchOptions` for the screenshot arguments).
/// A new match arrives as a push (Shared/Push); tapping it, or its "Open listing" / "Application text" action, opens the match.
/// A monitor's "No matching product" push opens the monitor's page (`arestemis://hunt/<id>`, brief 180).
/// The tour (brief 139, `Model/Tour.swift`) shows the same tabs on its own world in place of the account's, once by
/// itself per account and again from Settings → Help; a notification, a link or logging out ends it first.
struct ContentView: View {
    @State private var store: ArestemisStore
    @State private var navigation = AppNavigation()
    /// The tour, while it runs in place of the account's tabs.
    @State private var tours = TourRunner()
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
        let sharedDefaults = quiet ? nil : EmpireShared.defaults
        self.push = quiet ? nil : push          // samples and tests never register for push
        let session = account?.session
            ?? EmpireSession(app: .arestemis, restoreOnLaunch: !quiet, sharedDefaults: sharedDefaults)
        restoresOnLaunch = account?.restores ?? !quiet
        #else
        let sharedDefaults = EmpireShared.defaults
        self.push = push
        let session = EmpireSession(app: .arestemis, restoreOnLaunch: true, sharedDefaults: sharedDefaults)
        restoresOnLaunch = true
        #endif
        _store = State(initialValue: Self.makeStore(session: session, options: options))
        self.options = options
    }

    private static func makeStore(session: EmpireSession, options: LaunchOptions) -> ArestemisStore {
        #if DEBUG
        if options.sample, let sample = try? SampleBackend(options: .init(noHunt: options.noHunt, paused: options.paused,
                                                                             hangs: options.loading, moreLoading: options.moreLoading,
                                                                             moreFailure: options.moreFailure,
                                                                             longDescription: options.longDescription,
                                                                             ownMode: options.ownMode, noTexts: options.noTexts,
                                                                             slowed: options.slowed,
                                                                             newerKind: options.newerKind,
                                                                             ebayNotReady: options.ebayNotReady,
                                                                             watchRead: options.watchRead,
                                                                             preview: options.pricePreview,
                                                                             wordRefusal: options.wordRefusal,
                                                                             spelling: options.spelling,
                                                                             suggestedPage: options.suggestedPage,
                                                                             productState: options.productState,
                                                                             read: options.read)) {
            return ArestemisStore(session: session, backend: sample, sample: true)
        }
        #endif
        return ArestemisStore(session: session, backend: ArestemisAPI(token: { session.token }))
    }

    var body: some View {
        Group {
            if store.isSample || session.isSignedIn {
                if let tour = tours.tour, tour.phase == .running, let world = tour.world {
                    // The tour's world in the same tabs; Settings behind the gear stays the account's own.
                    MainTabs(store: world.store, navigation: world.navigation, own: store, logOut: logOut,
                             startTour: { startTour() })
                        .environment(\.tour, tour)
                } else if store.overview != nil {
                    MainTabs(store: store, navigation: navigation, own: store, logOut: logOut,
                             startTour: { startTour() },
                             scrollsToBottom: store.isSample && options.scrollTo == "bottom" && options.form == nil,
                             scrollsToHunt: store.isSample ? options.scrollToHunt : nil)
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
            if let link = MatchNotification.link(url: push.takeOpenedURL(), action: action) { follow(link) }
        }
        // Once per account, when its main screen first shows (`TourOffer`); a moment later, so a notification that
        // opened the app is seen first.
        .task(id: TourCheck(account: session.accountID, mainScreen: !store.isSample && store.overview != nil)) {
            guard !store.isSample, store.overview != nil, session.accountID != nil else { return }
            try? await Task.sleep(for: .milliseconds(800))
            await tours.offer(tourMoment)
        }
        .onChange(of: tours.tour?.phase) { _, _ in tours.clearEnded() }
        .onEmpireForeground(session: session) {
            await session.followSharedLogin()        // another Empire app may have logged in or out
            await store.refreshOnForeground()
        }
        .onChange(of: session.generation) { _, _ in
            if !session.isSignedIn {
                tours.end()
                navigation.reset()
            }
        }
        .onChange(of: store.overview != nil) { _, loaded in
            if loaded {
                options.apply(to: navigation, hunts: store.hunts, firstMatch: store.latest.first?.id)
                #if DEBUG
                // Screenshots: `-tour <1–8>` starts the tour at that step (`-tourSheet rejected|application` then
                // opens that sheet of the tour's flat).
                if store.isSample, let step = options.tour.flatMap(TourStep.init(rawValue:)) {
                    Task {
                        await tours.start(at: step, account: nil)
                        guard let world = tours.tour?.world else { return }
                        switch options.tourSheet {
                        case "rejected": world.navigation.sheet = .rejected(world.flatHunt)
                        case "application": world.navigation.sheet = world.flatMatch.map { .application($0) }
                        default: break
                        }
                    }
                }
                if store.isSample, options.sampleUndo, let id = store.latest.first?.id {
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        await store.setState(.dismissed, for: id)
                    }
                }
                #endif
            }
        }
        .onOpenURL { url in
            if let link = ArestemisLink(url: url) { follow(link) }
        }
    }

    /// A link or a tapped notification: the account's own listing or search, never the tour's. A search's link (the
    /// server's "No matching product for …" push) asks for the cards again, so its page shows what the server found.
    private func follow(_ link: ArestemisLink) {
        tours.end()
        navigation.follow(link)
        if link.hunt != nil { Task { await store.reloadOverview(quiet: true) } }
    }

    /// What the moment is like for the tour to start by itself: the account, its main screen, and whether a
    /// notification, a link, a sheet or a pushed page is in the way.
    private var tourMoment: TourOffer.Moment {
        TourOffer.Moment(account: store.isSample ? nil : session.accountID,
                         mainScreen: session.isSignedIn && store.overview != nil,
                         busy: push?.openedURL != nil || navigation.pendingLink != nil || navigation.pendingListing != nil
                             || navigation.sheet != nil || !navigation.huntPath.isEmpty || !navigation.listingsPath.isEmpty)
    }

    /// The tour from Settings → Help (or DEBUG's `-tour`): its world is made, then it shows in place of the account's
    /// tabs.
    private func startTour(at step: TourStep = .welcome) {
        let account = store.isSample ? nil : session.accountID
        Task { await tours.start(at: step, account: account) }
    }

    /// Logging out ends the shared login (every Empire app); in sample mode it leaves the sample for the real login.
    private func logOut() {
        tours.end()
        navigation.reset()
        if store.isSample {
            store.clear()
            let session = EmpireSession(app: .arestemis, restoreOnLaunch: false, sharedDefaults: EmpireShared.defaults)
            store = ArestemisStore(session: session, backend: ArestemisAPI(token: { session.token }))
        } else {
            session.logOut()
        }
    }
}

/// When the tour may start by itself: once the account's main screen is there (again for another account).
private struct TourCheck: Equatable {
    let account: String?
    let mainScreen: Bool
}

/// The two tabs, the sheets over them, and the notice for a failed action. In the tour they run on its world; Settings
/// is always the account's own (`own`).
private struct MainTabs: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    /// The account's store, for Settings.
    let own: ArestemisStore
    let logOut: () -> Void
    let startTour: () -> Void
    var scrollsToBottom = false
    var scrollsToHunt: Int? = nil
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Hunts", systemImage: "scope", value: AppTab.hunt) {
                HuntsScreen(store: store, navigation: navigation, scrollsToBottom: scrollsToBottom,
                            scrollsToHunt: scrollsToHunt)
            }
            Tab("Listings", systemImage: "list.bullet.rectangle", value: AppTab.listings) {
                ListingsScreen(store: store, navigation: navigation)
            }
        }
        .tint(Look.accent.color)
        .sheet(item: $navigation.sheet) { sheet in
            Group {
                switch sheet {
                case .settings:
                    SettingsSheet(store: own, logOut: logOut) {
                        navigation.sheet = nil
                        startTour()
                    }
                case .rejected(let hunt): RejectedSheet(store: store, hunt: hunt)
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
