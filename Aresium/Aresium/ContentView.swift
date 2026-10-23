import SwiftUI

struct ContentView: View {
    @State private var store: DashboardStore
    @State private var imports: ImportStore
    @AppStorage(ThemeState.preferenceKey) private var rememberedTheme = AppTheme.dark.rawValue
    @AppStorage(ThemeState.previousPreferenceKey) private var rememberedPreviousTheme = AppTheme.dark.rawValue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var theme: ThemeState
    private let pausedIntroProgress: Double?
    @State private var current = true
    @State private var side = DashboardSide.expenses
    @State private var graph = false
    @State private var path: [DashboardRoute] = []
    @State private var sampleActive: Bool
    private var palette: Palette { Palette(theme: theme.theme) }
    private var session: EmpireSession { store.session }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let sample = arguments.contains("-sampleData")
        var initialTheme = ThemeState(rememberedValue: UserDefaults.standard.string(forKey: ThemeState.preferenceKey),
                                      previousValue: UserDefaults.standard.string(forKey: ThemeState.previousPreferenceKey))
        var pausedProgress: Double?
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
        _theme = State(initialValue: initialTheme)
        pausedIntroProgress = pausedProgress
        let session = EmpireSession(restoreOnLaunch: !sample)
        let store = DashboardStore(session: session, sample: sample)
        let imports = ImportStore(dashboard: store)
        _store = State(initialValue: store)
        _imports = State(initialValue: imports)
        _sampleActive = State(initialValue: sample)
        if sample {
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
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                if sampleActive || session.token != nil {
                    NavigationStack(path: $path) {
                        VStack(spacing: 0) {
                            header()
                            StartScreen(store: store, imports: imports, palette: palette, current: $current, side: $side, graph: $graph) { path.append($0) }
                            band(in: geometry)
                        }
                        .background { Wall(palette: palette) }
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: DashboardRoute.self) { route in
                            VStack(spacing: 0) {
                                header(route)
                                if route.month != nil {
                                    TransactionsScreen(route: route, store: store, palette: palette)
                                } else {
                                    CategoryScreen(route: route, store: store, palette: palette, graph: $graph) { path.append($0) }
                                }
                                band(in: geometry)
                            }.background { Wall(palette: palette) }.toolbar(.hidden, for: .navigationBar)
                        }
                    }.task { if store.dashboard == nil { await store.reload() } }
                } else if session.isRestoring {
                    ProgressView("Restoring session…").font(AppFont.text(14)).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    LoginScreen(session: session, palette: palette)
                }
            }
            .foregroundStyle(palette.ink).background { Wall(palette: palette) }
            .preferredColorScheme(palette.dark ? .dark : .light)
            .allowsHitTesting(!theme.isAnimating)
            .overlay {
                if let transition = theme.transition {
                    AresiumIntro(transition: transition, bottomInset: geometry.safeAreaInsets.bottom,
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
            }
            .onChange(of: theme.previousTheme) { _, value in
                if !store.isSample { rememberedPreviousTheme = value.rawValue }
            }
            .task { if !store.isSample { await session.restore() } }
            .onChange(of: session.token) { _, token in
                if token == nil { store.clear(); path = [] }
                Task { await imports.sessionChanged() }
            }
            .onOpenURL { url in
                if url.isFileURL { Task { await imports.receive([url]) } }
            }
            .overlay(alignment: .bottom) {
                ImportFeedback(store: imports, palette: palette)
            }
        }
    }

    private func band(in geometry: GeometryProxy) -> some View {
        AresiumBand(palette: palette,
                    screenSize: CGSize(width: geometry.size.width,
                                       height: geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom),
                    hidden: theme.isAnimating) { theme.send(.band, reduceMotion: reduceMotion) }
    }

    @MainActor
    private func runTransition() async {
        guard let transition = theme.transition, pausedIntroProgress == nil else { return }
        let hero = transition.entering ? 0.26 : 0.30
        let clock = ContinuousClock()
        let start = clock.now
        do {
            try await clock.sleep(until: start.advanced(by: .seconds(IntroTimeline.duration * hero)))
            guard theme.transition?.id == transition.id else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
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
                return "\(store.dashboard?.months.first { $0.key == key }?.label ?? key) · activities"
            }
            return route.side == .income ? "Monthly income" : "Monthly spend"
        }
        return ScreenHeader(title: route?.category ?? "Aresium", subtitle: subtitle, category: category, palette: palette,
                            back: route == nil ? nil : { if !path.isEmpty { path.removeLast() } },
                            toggleTheme: { theme.send(.header, reduceMotion: reduceMotion) }, logout: {
            path = []
            store.clear()
            if sampleActive {
                sampleActive = false
                store = DashboardStore(session: EmpireSession(restoreOnLaunch: false))
                imports = ImportStore(dashboard: store)
            }
            else { session.logOut() }
        })
    }
}

#Preview { ContentView(arguments: ["-sampleData"]) }
