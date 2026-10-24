import SwiftUI

struct ContentView: View {
    @State private var store: DashboardStore
    @State private var imports: ImportStore
    @AppStorage(ThemeState.preferenceKey) private var rememberedTheme = AppTheme.dark.rawValue
    @AppStorage(ThemeState.previousPreferenceKey) private var rememberedPreviousTheme = AppTheme.dark.rawValue
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var theme: ThemeState
    private let pausedIntroProgress: Double?
    private let restoresOnLaunch: Bool
    @State private var current = true
    @State private var side = DashboardSide.expenses
    @State private var graph = false
    @State private var path: [DashboardRoute] = []
    @State private var sampleActive: Bool
    /// Where the band was tapped last (from the screen's bottom edge to its word), so the intro's word lands there.
    @State private var bandLanding: CGFloat?
    private var palette: Palette { Palette(theme: theme.theme) }
    private var session: EmpireSession { store.session }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        var sample = false
        var skipRestore = false
        #if DEBUG
        sample = arguments.contains("-sampleData")
        let debugLaunch = DebugLaunch.isTesting || sample || arguments.contains("-sampleAuthUnavailable") || arguments.contains("-sampleLoginWaiting")
        skipRestore = DebugLaunch.isTesting || arguments.contains("-sampleLoginWaiting")
        #endif
        var initialTheme = ThemeState(rememberedValue: UserDefaults.standard.string(forKey: ThemeState.preferenceKey),
                                      previousValue: UserDefaults.standard.string(forKey: ThemeState.previousPreferenceKey))
        var pausedProgress: Double?
        #if DEBUG
        if sample {
            initialTheme = ThemeState(rememberedValue: arguments.contains("-sampleRed") ? "red" :
                                        arguments.contains("-sampleLight") ? "light" : "dark")
            if let index = arguments.firstIndex(of: "-sampleIntroProgress"), arguments.indices.contains(index + 1),
               let progress = Double(arguments[index + 1]), progress.isFinite {
                let clamped = min(1, max(0, progress))
                pausedProgress = clamped
                initialTheme.send(.band, reduceMotion: false)
                initialTheme.advance(to: clamped)
            }
        }
        if sample, arguments.contains("-sampleIntro"), pausedProgress == nil {
            initialTheme.send(.band, reduceMotion: false)
        }
        #endif
        _theme = State(initialValue: initialTheme)
        pausedIntroProgress = pausedProgress
        restoresOnLaunch = !sample && !skipRestore
        #if DEBUG
        var session = EmpireSession(app: .aresium, restoreOnLaunch: !sample && !skipRestore,
                                    installDefaults: debugLaunch ? nil : EmpireShared.defaults)
        if DebugLaunch.isTesting { session = DebugLaunch.testingSession() }
        if arguments.contains("-sampleAuthUnavailable") { session = DebugLaunch.unavailableSession() }
        let publisher: WidgetSnapshotPublisher = debugLaunch ? .temporary() : WidgetSnapshotPublisher()
        #else
        let session = EmpireSession(app: .aresium, installDefaults: EmpireShared.defaults)
        let publisher = WidgetSnapshotPublisher()
        #endif
        let store = DashboardStore(session: session, sample: sample, widgetPublisher: publisher)
        let imports = ImportStore(dashboard: store)
        _store = State(initialValue: store)
        _imports = State(initialValue: imports)
        _sampleActive = State(initialValue: sample)
        #if DEBUG
        if arguments.contains("-sampleLoginWaiting") { imports.seedDebugWaitingFiles() }
        if sample {
            if arguments.contains("-sampleImportFailed") { imports.seedDebugImportFailure() }
            if arguments.contains("-sampleImportResult") {
                imports.show("12 new transactions imported · 1 skipped", success: true)
            }
            let side: DashboardSide = arguments.contains("-sampleIncome") ? .income : .expenses
            _side = State(initialValue: side)
            _current = State(initialValue: !arguments.contains("-sampleOverview"))
            _graph = State(initialValue: arguments.contains("-sampleGraph"))
            if let index = arguments.firstIndex(of: "-sampleCategory"), arguments.indices.contains(index + 1) {
                let name = arguments[index + 1]
                var routes = [DashboardRoute(category: name, side: side)]
                if let index = arguments.firstIndex(of: "-sampleMonth"), arguments.indices.contains(index + 1) {
                    routes.append(DashboardRoute(category: name, side: side, month: arguments[index + 1]))
                }
                _path = State(initialValue: routes)
            }
        }
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if sampleActive || session.isSignedIn {
                    NavigationStack(path: $path) {
                        VStack(spacing: 0) {
                            header()
                            restoreFeedback
                            StartScreen(store: store, imports: imports, palette: palette, current: $current, side: $side, graph: $graph,
                                        band: band(in: geometry)) { path.append($0) }
                        }
                        .background { Wall(palette: palette) }
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: DashboardRoute.self) { route in
                            VStack(spacing: 0) {
                                header(route)
                                restoreFeedback
                                if route.month != nil {
                                    TransactionsScreen(route: route, store: store, palette: palette, band: band(in: geometry))
                                } else {
                                    CategoryScreen(route: route, store: store, palette: palette, graph: $graph,
                                                   band: band(in: geometry)) { path.append($0) }
                                }
                            }.background { Wall(palette: palette) }.toolbar(.hidden, for: .navigationBar)
                        }
                    }.task { if store.dashboard == nil { await store.reload() } }
                } else if session.isRestoring {
                    ProgressView("Restoring session…").font(AppFont.text(14)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LoginScreen(session: session, palette: palette, waitingFiles: imports.waitingCount)
                }
            }
            .foregroundStyle(palette.ink).background { Wall(palette: palette) }
            .preferredColorScheme(palette.dark ? .dark : .light)
            .allowsHitTesting(!theme.isAnimating)
            .overlay {
                if let transition = theme.transition {
                    // Without a tapped band (the DEBUG intro arguments): where the band sits when scrolled to the end.
                    AresiumIntro(transition: transition, landing: bandLanding ?? geometry.safeAreaInsets.bottom + 10,
                                 pausedProgress: pausedIntroProgress)
                        .id(transition.id)
                }
            }
            .task(id: theme.transition?.id) { await runTransition() }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { theme.finishImmediately() }
            }
            .onChange(of: theme.theme) { _, value in
                if !store.isSample { rememberedTheme = value.rawValue }
                store.setWidgetTheme(value)
            }
            .onChange(of: theme.previousTheme) { _, value in
                if !store.isSample { rememberedPreviousTheme = value.rawValue }
            }
            .task {
                if restoresOnLaunch { await session.restore() }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    Task {
                        await session.followSharedLogin()    // another Empire app may have logged in or out
                        await store.refreshOnForeground()
                    }
                }
            }
            .task { store.setWidgetTheme(theme.theme) }
            .onChange(of: session.generation) { _, _ in
                if !session.isSignedIn { path = [] }
                Task { await imports.sessionChanged() }
            }
            .onOpenURL { url in
                if url.isFileURL { Task { await imports.receive([url], source: .shared) } }
                else if let destination = AresiumURL(url: url) {
                    current = true
                    side = .expenses
                    graph = false
                    switch destination {
                    case .start: path = []
                    case .category(let name): path = [DashboardRoute(category: name, side: .expenses)]
                    }
                }
            }
            .overlay(alignment: .bottom) {
                ImportFeedback(store: imports, palette: palette)
            }
        }
    }

    @ViewBuilder private var restoreFeedback: some View {
        if session.needsRestoreRetry, let error = session.error {
            HStack {
                Text(error).foregroundStyle(palette.expense)
                Button("Retry") {
                    Task {
                        await session.restore()
                        if !session.needsRestoreRetry { await store.refreshOnForeground() }
                    }
                }.disabled(session.isBusy)
            }.font(AppFont.text(13)).padding(12)
        }
    }

    /// The band that ends each screen's scroll content; tapping it enters or leaves the special mode.
    private func band(in geometry: GeometryProxy) -> AresiumBand {
        let screenHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
        return AresiumBand(palette: palette, width: geometry.size.width, hidden: theme.isAnimating) { wordFrame in
            guard !theme.isAnimating else { return }
            bandLanding = screenHeight - wordFrame.maxY
            theme.send(.band, reduceMotion: reduceMotion)
        }
    }

    @MainActor
    private func runTransition() async {
        guard let transition = theme.transition, pausedIntroProgress == nil else { return }
        let haptic = UIImpactFeedbackGenerator(style: .soft)
        haptic.prepare()
        let hero = transition.entering ? 0.26 : 0.30
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await clock.sleep(until: start.advanced(by: .seconds(IntroTimeline.duration * hero)))
            guard theme.transition?.id == transition.id else { return }
            haptic.impactOccurred()
            try await clock.sleep(until: start.advanced(by: .seconds(IntroTimeline.duration * IntroTimeline.swapAt)))
            theme.advance(to: IntroTimeline.swapAt)
            try await clock.sleep(until: start.advanced(by: .seconds(IntroTimeline.duration)))
            theme.advance(to: 1)
        } catch is CancellationError {
            // A changed Reduce Motion preference finishes the transition and cancels this clock.
        } catch {
            theme.finishImmediately()
        }
    }

    private func header(_ route: DashboardRoute? = nil) -> some View {
        let category = route.flatMap { store.category($0.category, side: $0.side) }
        let subtitle: String? = route.map { route in
            if let key = route.month {
                let month = store.dashboard?.months.first { $0.key == key }?.title() ?? key
                return String(localized: "\(month) · activities")
            }
            return route.side == .income ? String(localized: "Monthly income") : String(localized: "Monthly spend")
        }
        return ScreenHeader(title: route?.category ?? "Aresium", subtitle: subtitle, category: category, palette: palette,
                            back: route == nil ? nil : { if !path.isEmpty { path.removeLast() } },
                            toggleTheme: { theme.send(.header, reduceMotion: reduceMotion) }, logout: {
            path = []
            store.clear()
            if sampleActive {
                sampleActive = false
                store = DashboardStore(session: EmpireSession(app: .aresium, restoreOnLaunch: false,
                                                              installDefaults: EmpireShared.defaults),
                                       widgetPublisher: WidgetSnapshotPublisher())
                imports = ImportStore(dashboard: store)
            }
            else { session.logOut() }
        })
    }
}

#if DEBUG
#Preview { ContentView(arguments: ["-sampleData"]) }
#endif
