import CoreSpotlight
import SwiftUI

/// Arestoteles: the shared Empire login, then four tabs (Positions, Topics, Library, Search). Logged in once in any
/// Empire app means logged in here. The vault saved on the device shows at once, also offline; it is refreshed at
/// launch, in the foreground and on pull to refresh. Links (`arestoteles://note/<id>#<heading>`), whether tapped in a
/// note, opened from outside or from Spotlight, all go through `NoteLink` and `AppNavigation.open`.
/// `-sampleData` shows the bundled samples (see `LaunchOptions` for the screenshot arguments).
struct ContentView: View {
    @State private var store: VaultStore
    @State private var navigation = AppNavigation()
    @State private var appliedOptions = false
    @State private var openedBestMatch = false
    private let options: LaunchOptions
    private let restoresOnLaunch: Bool
    private var session: EmpireSession { store.session }

    init(arguments: [String] = LaunchArguments.current) {
        let options = LaunchOptions(arguments: arguments)
        #if DEBUG
        // Tests (the app is their host) and samples never touch the real login, files or Spotlight.
        let testing = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        // Screenshots of the login and the no-access screen (`SampleAccount`): a made-up account, no server.
        let account = SampleAccount.session(app: .arestoteles, arguments: arguments)
        let quiet = options.sample || testing || account != nil
        let session = account?.session ?? EmpireSession(app: .arestoteles, restoreOnLaunch: !quiet,
                                                        sharedDefaults: quiet ? nil : EmpireShared.defaults)
        restoresOnLaunch = account?.restores ?? !quiet
        let store = Self.makeStore(session: session, options: options, testing: testing || account != nil)
        #else
        let session = EmpireSession(app: .arestoteles, restoreOnLaunch: true, sharedDefaults: EmpireShared.defaults)
        restoresOnLaunch = true
        let store = Self.makeStore(session: session, options: options, testing: false)
        #endif
        _store = State(initialValue: store)
        self.options = options
    }

    private static func makeStore(session: EmpireSession, options: LaunchOptions, testing: Bool) -> VaultStore {
        #if DEBUG
        if options.sample, let backend = try? SampleBackend(options: .init(
            conflict: options.editConflict, invalid: options.editInvalid, pushLater: options.pushLater,
            offline: options.offline, slowSearch: options.slowSearch)) {
            let saved = options.offline ? try? SampleBackend.savedVault() : nil
            return VaultStore(session: session, backend: backend, persistence: MemoryPersistence(vault: saved),
                              spotlight: DeviceSpotlight(), savedAccount: { nil }, sample: true)
        }
        if testing {
            return VaultStore(session: session, backend: ArestotelesAPI(token: { session.token }),
                              persistence: MemoryPersistence(), spotlight: NoSpotlight(), savedAccount: { nil })
        }
        #endif
        PushCenter.removeDevicesOnLogout(of: session, sharedDefaults: EmpireShared.defaults)
        return VaultStore(session: session, backend: ArestotelesAPI(token: { session.token }),
                          persistence: FilePersistence.standard, spotlight: DeviceSpotlight(),
                          savedAccount: Self.savedAccount)
    }

    /// Readable even on a locked background launch: show the saved vault only to the account in the marker.
    private static func savedAccount() -> String? {
        LoginMarker.account(in: EmpireShared.defaults)
    }

    /// The saved vault stays on screen while the login is restored or waits for the account server (offline).
    private var showsVault: Bool {
        store.vault != nil && (store.isSample || session.isSignedIn || session.isRestoring || session.needsRestoreRetry)
    }

    var body: some View {
        Group {
            if showsVault {
                MainTabs()
            } else if store.isSample || session.isSignedIn {
                ProvinceLoading(name: "Arestoteles", bust: Image("Bust"), accent: Look.accent,
                                message: store.isRefreshing ? nil : loadingProblem,
                                retry: { Task { await store.refresh() } },
                                logOut: logOut)
                    .task { if store.vault == nil { await store.refresh() } }
            } else if session.isRestoring {
                ProvinceLoading(name: "Arestoteles", bust: Image("Bust"), accent: Look.accent)
            } else {
                ProvinceLogin(session: session, name: "Arestoteles", bust: Image("Bust"), accent: Look.accent)
            }
        }
        .environment(store)
        .environment(navigation)
        .environment(\.logOut, LogOutAction(run: logOut))
        .task {
            if restoresOnLaunch { await session.restore() }
            await store.update(renewsLogin: false)
        }
        .onEmpireForeground(session: session) {
            if !store.isSample { await session.followSharedLogin() }   // another Empire app may have logged in or out
            await store.update(minimumAge: 30)
        }
        .onChange(of: session.generation) { _, _ in
            if !session.isSignedIn && !store.isSample { navigation.reset() }
        }
        .task(id: store.vault != nil) {
            guard store.vault != nil, !appliedOptions else { return }
            appliedOptions = true
            options.apply(to: navigation, index: store.index)
        }
        .onChange(of: store.bestMatches.answer) { _, answer in
            // -openBestMatch (screenshots): the tap on a best match, once one is there.
            guard !openedBestMatch else { return }
            openedBestMatch = options.openBestMatch(of: answer, navigation: navigation, index: store.index)
        }
        .onOpenURL { url in
            if let link = NoteLink(url: url) { navigation.follow(link) }
        }
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let link = SpotlightItems.link(from: activity) { navigation.follow(link) }
        }
    }

    /// Why the first load has no vault to show (nil: still loading).
    private var loadingProblem: String? {
        store.loadError ?? (store.isOffline ? VaultStore.offlineMessage : nil)
    }

    /// Logging out ends the shared login (every Empire app); in sample mode it leaves the sample for the real login.
    private func logOut() {
        navigation.reset()
        if store.isSample {
            store.clear()
            let session = EmpireSession(app: .arestoteles, restoreOnLaunch: false, sharedDefaults: EmpireShared.defaults)
            PushCenter.removeDevicesOnLogout(of: session, sharedDefaults: EmpireShared.defaults)
            store = VaultStore(session: session, backend: ArestotelesAPI(token: { session.token }),
                               persistence: FilePersistence.standard, spotlight: DeviceSpotlight(),
                               savedAccount: Self.savedAccount)
        } else {
            session.logOut()
        }
    }
}

/// Ends the login (Settings → Account). Always equal: it is the root's one action, so a new closure for it never needs
/// to redraw the views reading it.
struct LogOutAction: Equatable {
    let run: () -> Void
    func callAsFunction() { run() }
    static func == (_: LogOutAction, _: LogOutAction) -> Bool { true }
}

extension EnvironmentValues {
    @Entry var logOut = LogOutAction {}
}

/// The four tabs, the sheets over them, the notice of the last edit. Links in notes open in the app, web links in
/// Safari.
private struct MainTabs: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.logOut) private var logOut
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var navigation = navigation
        TabView(selection: $navigation.tab) {
            Tab("Positions", systemImage: "quote.bubble", value: AppTab.positions) {
                NavigationStack(path: $navigation.positionsPath) { PositionsScreen().routes() }
            }
            Tab("Topics", systemImage: "books.vertical", value: AppTab.topics) {
                NavigationStack(path: $navigation.topicsPath) { TopicsScreen().routes() }
            }
            Tab("Library", systemImage: "building.columns", value: AppTab.library) {
                NavigationStack(path: $navigation.libraryPath) { LibraryScreen().routes() }
            }
            Tab(value: AppTab.search, role: .search) {
                NavigationStack(path: $navigation.searchPath) { SearchScreen().routes() }
            }
        }
        .tint(Look.accent.color)
        .sheet(item: $navigation.sheet) { sheet in
            Group {
                switch sheet {
                case let .brief(note): BriefSheet(note: note)
                case let .editor(note): EditorSheet(note: note, store: store)
                case let .discuss(subject): DiscussSheet(subject: subject)
                case let .quickNote(about): QuickNoteSheet(about: about)
                case .discussions: DiscussionsSheet()
                case .settings:
                    SettingsScreen(app: SettingsApp(name: "Arestoteles", accent: Look.accent), session: store.session,
                                   sample: store.isSample, logOut: logOut.run)
                case let .passage(note, lines): PassageSheet(note: note, lines: lines)
                case let .position(kind): PositionSheet(kind: kind, index: store.index)
                }
            }
            .presentationDetents(sheet.isSmall ? [.medium, .large] : [.large])
            .presentationBackground(Ink.background)
        }
        .overlay(alignment: .top) {
            if let notice = store.notice {
                NoticeBanner(notice: notice) { store.dismissNotice() }
                    .padding(.top, 6)
                    .transition(reduceMotion ? .opacity : .move(edge: .top).combined(with: .opacity))
                    .task(id: notice.id) {
                        try? await Task.sleep(for: .seconds(6))
                        if store.notice?.id == notice.id { store.dismissNotice() }
                    }
            }
        }
        .animation(.easeOut(duration: 0.25), value: store.notice)
        .task(id: navigation.pendingLink) {
            guard navigation.pendingLink != nil else { return }
            try? await Task.sleep(for: .milliseconds(150))      // the tabs are laid out first
            navigation.openPendingLink()
        }
        .environment(\.openURL, OpenURLAction { url in
            if let link = NoteLink(url: url) {
                navigation.open(link)
                return .handled
            }
            return .systemAction                                // web links: Safari
        })
    }
}

private extension View {
    /// The pages any tab can push: notes and positions.
    func routes() -> some View {
        navigationDestination(for: Route.self) { route in
            switch route {
            case let .note(link): NoteScreen(link: link)
            case let .position(id): PositionScreen(id: id)
            }
        }
    }
}

#if DEBUG
#Preview { ContentView(arguments: ["-sampleData"]) }
#endif
