import SwiftUI

struct ContentView: View {
    @State private var store: DashboardStore
    @State private var imports: ImportStore
    @State private var dark = true
    @State private var current = true
    @State private var side = DashboardSide.expenses
    @State private var graph = false
    @State private var path: [DashboardRoute] = []
    @State private var sampleActive: Bool
    private var palette: Palette { Palette(dark: dark) }
    private var session: EmpireSession { store.session }

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        let sample = arguments.contains("-sampleData")
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
            _dark = State(initialValue: !arguments.contains("-sampleLight"))
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
        Group {
            if sampleActive || session.token != nil {
                NavigationStack(path: $path) {
                    VStack(spacing: 0) {
                        header()
                        StartScreen(store: store, imports: imports, palette: palette, current: $current, side: $side, graph: $graph) { path.append($0) }
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
        .preferredColorScheme(dark ? .dark : .light)
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
                            toggleTheme: { dark.toggle() }, logout: {
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
