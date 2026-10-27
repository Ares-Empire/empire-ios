import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    /// The lock's window (one per launch, `AresiumApp`), and through it the lock.
    let lockWindow: LockWindow
    private var lock: AppLock { lockWindow.lock }
    @State private var store: DashboardStore
    @State private var imports: ImportStore
    /// Phone mode (the phone's own store, no account needed) or the owner's server mode (`ModeStore`).
    @State private var modes: ModeStore
    /// Phone mode's export, restore and delete (Settings and the first screen).
    @State private var phoneData: PhoneDataModel
    /// Unknown banks' formats and the names of banks the guide does not know, on their way to us; what could not go at
    /// once is sent again at the start and on return (`BankOutbox`).
    @State private var outbox: BankOutbox
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ThemeState.preferenceKey) private var rememberedRed = false
    @AppStorage(Appearance.key) private var appearance = Appearance.iPhone.rawValue
    /// Light or dark as Settings → Appearance (or the iPhone) says; red mode shows over it.
    @Environment(\.appearanceScheme) private var appearanceScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var theme: ThemeState
    private let pausedIntroProgress: Double?
    private let restoresOnLaunch: Bool
    /// Where the person's dashboard is (pushed screens, Current/Overview, the page, the graph, the open payment).
    @State private var place = DashboardPlace()
    /// The tour, while it runs in place of the dashboard (on a made-up store of its own, `TourModel`).
    @State private var tour: TourModel?
    /// "How do I get my file?" as a sheet (the first screen, an empty dashboard).
    @State private var showsGuide = false
    /// Files picked in the guide, imported once its sheet (or Settings) has closed, so the import's own sheets can show.
    @State private var pickedInGuide: [URL] = []
    @State private var sampleActive: Bool
    /// DEBUG `-samplePhone` / `-samplePhoneEmpty`: phone mode on a made-up store, without a login.
    @State private var samplePhone: Bool
    /// Files shared into Aresium while it was locked: imported once it is unlocked.
    @State private var heldFiles: [URL] = []
    @State private var showsSettings = false
    /// Import data in phone mode: the category picker first while none is chosen, then the file picker.
    @State private var importFlow = ImportFlow()
    @State private var restoringExport = false
    /// Where the band was when it was tapped (from the screen's bottom edge to its word), so the intro's word lands
    /// there; nil when the header started the transition.
    @State private var bandLanding: CGFloat?
    private var base: AppTheme { appearanceScheme == .light ? .light : .dark }
    private var shownTheme: AppTheme { theme.theme(over: base) }
    private var palette: Palette { Palette(theme: shownTheme) }
    private var session: EmpireSession { store.session }

    init(lockWindow: LockWindow, arguments: [String] = LaunchArguments.current) {
        self.lockWindow = lockWindow
        var sample = false
        var phoneSample = false
        var restores = true
        #if DEBUG
        phoneSample = arguments.contains("-samplePhone") || arguments.contains("-samplePhoneEmpty")
        sample = arguments.contains("-sampleData") || phoneSample
        // Samples and screenshots run on a made-up account server and a login in memory (`SampleAccount`), never the
        // real ones: signed out, or with `-sampleSignedIn` signed in.
        let account = SampleAccount.session(app: .aresium, arguments: arguments)
            ?? (sample ? SampleAccount.session(app: .aresium, start: .login) : nil)
        let debugLaunch = DebugLaunch.isTesting || sample || account != nil
        restores = !DebugLaunch.isTesting && (account?.restores ?? true)
        #endif
        var initialTheme = ThemeState(red: UserDefaults.standard.bool(forKey: ThemeState.preferenceKey))
        var pausedProgress: Double?
        #if DEBUG
        if sample {
            // Light or dark in screenshots: `-appearance light|dark`.
            initialTheme = ThemeState(red: arguments.contains("-sampleRed"))
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
        restoresOnLaunch = restores
        #if DEBUG
        var session = EmpireSession(app: .aresium, restoreOnLaunch: restores,
                                    sharedDefaults: debugLaunch ? nil : EmpireShared.defaults)
        if DebugLaunch.isTesting { session = DebugLaunch.testingSession() }
        if let account { session = account.session }
        let publisher: WidgetSnapshotPublisher = debugLaunch ? .temporary() : WidgetSnapshotPublisher()
        PushCenter.removeDevicesOnLogout(of: session, sharedDefaults: debugLaunch ? nil : EmpireShared.defaults)
        let markerDefaults = debugLaunch ? nil : EmpireShared.defaults
        #else
        let session = EmpireSession(app: .aresium, sharedDefaults: EmpireShared.defaults)
        let publisher = WidgetSnapshotPublisher()
        PushCenter.removeDevicesOnLogout(of: session, sharedDefaults: EmpireShared.defaults)
        let markerDefaults = EmpireShared.defaults
        #endif
        // The server sample shows the bundled dashboard; otherwise the backend comes with the mode (`ModeStore`).
        let store = sample && !phoneSample
            ? DashboardStore(session: session, sample: true, widgetPublisher: publisher)
            : DashboardStore(session: session, backend: nil, widgetPublisher: publisher)
        // Samples (and the app while tests run) only pretend to send a bank's format or name.
        #if DEBUG
        let outbox = sample || DebugLaunch.isTesting ? BankOutbox.sample()
                                                     : BankOutbox(file: PhoneStorage.standard.bankOutboxURL)
        #else
        let outbox = BankOutbox(file: PhoneStorage.standard.bankOutboxURL)
        #endif
        let imports = ImportStore(dashboard: store, outbox: outbox)
        let modes = ModeStore(session: session, dashboard: store, markerDefaults: markerDefaults)
        _store = State(initialValue: store)
        _imports = State(initialValue: imports)
        _modes = State(initialValue: modes)
        _phoneData = State(initialValue: PhoneDataModel(modes: modes))
        _outbox = State(initialValue: outbox)
        _sampleActive = State(initialValue: sample)
        _samplePhone = State(initialValue: phoneSample)
        #if DEBUG
        if phoneSample, let index = arguments.firstIndex(of: "-openSheet"), arguments.indices.contains(index + 1) {
            _showsSettings = State(initialValue: arguments[index + 1] == "settings")
            if arguments[index + 1] == "categories" {
                let flow = ImportFlow()
                flow.showCategories()
                _importFlow = State(initialValue: flow)
            }
        }
        if phoneSample, let index = arguments.firstIndex(of: "-sampleCategory"), arguments.indices.contains(index + 1) {
            var routes = [DashboardRoute(category: arguments[index + 1], side: .expenses)]
            if let month = arguments.firstIndex(of: "-sampleMonth"), arguments.indices.contains(month + 1) {
                routes.append(DashboardRoute(category: arguments[index + 1], side: .expenses, month: arguments[month + 1]))
            }
            _place = State(initialValue: DashboardPlace(path: routes))
        }
        // Screenshots: `-openGuide list|<bank id>` (the guide), `-tour <step>` (the tour at that step, 1–12).
        if sample, LaunchArguments.value("-openGuide") != nil { _showsGuide = State(initialValue: true) }
        if sample { modes.holdForSample(server: !phoneSample) }
        if sample && !phoneSample {
            if let index = arguments.firstIndex(of: "-openSheet"), arguments.indices.contains(index + 1) {
                _showsSettings = State(initialValue: arguments[index + 1] == "settings")
            }
            if arguments.contains("-sampleImportFailed") { imports.seedDebugImportFailure() }
            if arguments.contains("-sampleImportResult") {
                imports.show("12 new transactions imported · 1 skipped", success: true)
            }
            let side: DashboardSide = arguments.contains("-sampleIncome") ? .income : .expenses
            var place = DashboardPlace(current: !arguments.contains("-sampleOverview"), side: side,
                                       graph: arguments.contains("-sampleGraph"))
            if let index = arguments.firstIndex(of: "-sampleCategory"), arguments.indices.contains(index + 1) {
                let name = arguments[index + 1]
                var routes = [DashboardRoute(category: name, side: side)]
                if let index = arguments.firstIndex(of: "-sampleMonth"), arguments.indices.contains(index + 1) {
                    routes.append(DashboardRoute(category: name, side: side, month: arguments[index + 1]))
                }
                place.path = routes
            }
            _place = State(initialValue: place)
        }
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            Group {
                switch mainScreen {
                case .tour:
                    // The tour in place of the dashboard; the person's own stays as it was, untouched.
                    if let tour {
                        TourScreen(tour: tour, palette: palette, band: tourBand(in: geometry)) { route, openSettings in
                            header(route, in: tour.world?.dashboard, openSettings: openSettings)
                        }
                        .transition(.opacity)
                    }
                case .opening:
                    // The phone's store is opening, or did not open.
                    VStack(spacing: 0) {
                        header()
                        ModeStatusScreen(modes: modes, palette: palette)
                    }
                case .waitingForLogin, .firstScreen, .dashboard:
                    DashboardStack(store: store, palette: palette, place: $place, band: band(in: geometry)) { route in
                        header(route)
                        restoreFeedback
                    } root: {
                        switch mainScreen {
                        case .waitingForLogin:
                            // Server mode at launch: the saved login is being renewed before the server is asked.
                            ProgressView().tint(palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .firstScreen:
                            PhoneFirstScreen(imports: imports, palette: palette, band: band(in: geometry),
                                             restoreProblem: phoneData.problem, importData: importData,
                                             startTour: startTour, openGuide: { showsGuide = true },
                                             restore: { restoringExport = true })
                        default:
                            StartScreen(store: store, imports: imports, palette: palette, current: $place.current,
                                        side: $place.side, graph: $place.graph, band: band(in: geometry),
                                        importTypes: importTypes, beforeImport: chooseCategoriesFirst,
                                        openGuide: { showsGuide = true }) { place.path.append($0) }
                        }
                    }
                }
            }
            .foregroundStyle(palette.ink).background { Wall(palette: palette) }
            .holdsColorScheme(palette.red ? .dark : nil)      // red mode: dark status bar, sheets and keyboard
            .allowsHitTesting(!theme.isAnimating)
            .overlay {
                if let transition = theme.transition {
                    // Without a tapped band (the header, the DEBUG intro arguments): where the band sits at the end.
                    AresiumIntro(transition: transition, target: transition.entering ? .red : base,
                                 landing: bandLanding ?? geometry.safeAreaInsets.bottom + WordmarkEnd.below,
                                 pausedProgress: pausedIntroProgress)
                        .id(transition.id)
                }
            }
            .task(id: theme.transition?.id) { await runTransition() }
            .onChange(of: reduceMotion) { _, reduced in
                if reduced { theme.finishImmediately() }
            }
            .onChange(of: theme.red) { _, red in
                if !store.isSample { rememberedRed = red }
                store.setWidgetRedMode(red)
            }
            // Phone mode opens at once; nothing waits for a login or the network.
            .task { if !sampleActive { await modes.start() } }
            .task {
                if restoresOnLaunch { await session.restore() }
                if !sampleActive { await modes.update() }
            }
            .task { await outbox.sendWaiting() }           // formats and bank names kept for later go at the start
            #if DEBUG
            .task { await startPhoneSample() }
            #endif
            .onChange(of: scenePhase) { _, phase in
                // Before anything async: server mode on a login not renewed yet ends when the saved login changed.
                if phase == .active { modes.followMarker() }
            }
            .onEmpireForeground(session: session) {
                await session.followSharedLogin()    // another Empire app may have logged in or out
                await modes.update()
                await store.refreshOnForeground()
                await outbox.sendWaiting()
            }
            .task { store.setWidgetRedMode(theme.red) }
            .onChange(of: session.generation) { _, _ in
                Task {
                    await modes.update()
                    await imports.sessionChanged()
                }
            }
            .onChange(of: session.services) { _, _ in Task { await modes.update() } }    // left Aresium, say
            .onChange(of: session.needsRestoreRetry) { _, _ in Task { await modes.update() } }
            .onChange(of: modes.state) { old, new in
                if old != new { place.path = [] }                // the other mode's data
                Task { await imports.sessionChanged() }       // files waiting for the phone's store
            }
            .onChange(of: lock.isOn) { _, on in
                if !on { store.republishWidget() }            // the lock kept no numbers for the widgets
            }
            .onChange(of: lock.isLocked) { _, locked in
                guard !locked, !heldFiles.isEmpty else { return }
                let files = heldFiles
                heldFiles = []
                Task { await imports.receive(files, source: .shared) }
            }
            .onOpenURL { url in
                // A file shared to Aresium or a widget's link ends a tour first (its made-up store goes): the file goes
                // to the person's own store, the link opens their own dashboard.
                tour?.end()
                if url.isFileURL {
                    // Shared into Aresium while locked: it waits until Aresium is unlocked.
                    if lock.isLocked { heldFiles.append(url) }
                    else { Task { await imports.receive([url], source: .shared) } }
                } else if let destination = AresiumURL(url: url) {
                    place.current = true
                    place.side = .expenses
                    place.graph = false
                    switch destination {
                    case .start: place.path = []
                    case .category(let name): place.path = [store.route(category: name, side: .expenses, current: true)]
                    }
                }
            }
            .overlay(alignment: .bottom) {
                ImportFeedback(store: imports, palette: palette)
            }
            .sheet(isPresented: $showsSettings, onDismiss: importPickedInGuide) {
                SettingsScreen(app: SettingsApp(name: "Aresium",
                                                signInNote: String(localized: "Only for an Aresium server of your own. Your data here stays on this iPhone."),
                                                licences: [.shopList()]),
                               session: session, sample: sampleActive, logOut: logOut) {
                    if modes.phone != nil { PhoneSettingsSection(modes: modes, data: phoneData) }
                    LockSettingsSection(lock: lock)
                } help: {
                    NavigationLink {
                        BankGuideList(importing: guideImport { showsSettings = false }, outbox: outbox)
                    } label: {
                        SettingsRow(title: String(localized: "Get the file from your bank"))
                    }
                    .buttonStyle(SettingsRowStyle())
                    SettingsDivider()
                    Button {
                        showsSettings = false
                        startTour()
                    } label: {
                        SettingsRow(title: String(localized: "Tour of Aresium"),
                                    subtitle: String(localized: "With made-up sample data"), trailing: .none)
                    }
                    .buttonStyle(SettingsRowStyle())
                }
            }
            .sheet(isPresented: $showsGuide, onDismiss: importPickedInGuide) {
                BankGuideSheet(importing: guideImport { showsGuide = false }, outbox: outbox)
            }
            .sheet(isPresented: $importFlow.choosesCategories, onDismiss: {
                // Categories chosen: on to the file (`ImportFlow`).
                importFlow.categoriesClosed(hasCategories: modes.phone?.hasChosenCategories == true)
            }) {
                if let phone = modes.phone {
                    NavigationStack {
                        CategoryPickerScreen(model: CategoryPickerModel(phone: phone) {
                            await store.reloadAfterTransactionChange()
                        }, done: { importFlow.choosesCategories = false })
                    }
                    .presentationBackground(Ink.background)
                }
            }
            .background {
                // Import data's file picker, on a view of its own (one file picker per view; the restore's is below).
                Color.clear
                    .fileImporter(isPresented: $importFlow.picksFiles, allowedContentTypes: importTypes,
                                  allowsMultipleSelection: true) { result in
                        switch result {
                        case let .success(urls): if !urls.isEmpty { Task { await imports.receive(urls) } }
                        case let .failure(error): imports.show(error.localizedDescription, success: false)
                        }
                    }
            }
            .sheet(item: Binding(get: { imports.layoutRequest }, set: { _ in })) { request in
                // An unknown bank's file: "Does this look right?", then the column check.
                if let phone = modes.phone {
                    FileCheckSheet(model: FileCheckModel(request: request, phone: phone, imports: imports), palette: palette)
                }
            }
            .fileImporter(isPresented: $restoringExport, allowedContentTypes: [.json]) { result in
                if case let .success(url) = result { Task { await phoneData.restore(from: url) } }
            }
            .overlay(alignment: .bottom) {
                // A restore from the first screen shows its problem there.
                if let problem = phoneData.problem, !showsSettings, mainScreen != .firstScreen {
                    Text(problem).font(AppFont.text(13)).foregroundStyle(palette.expenseText).padding(18)
                }
            }
        }
        // While locked, the lock window is all there is: the app below is not read out either.
        .accessibilityHidden(lock.isLocked)
        .background { LockWindowReader(lockWindow: lockWindow) }
        .task { handOverForgotCode() }
        // A tour the app was closed in left its made-up store behind: it goes now (no tour runs yet).
        .task { if tour == nil { TourWorld.removeLeftovers() } }
        .onChange(of: tour?.phase == .ended) { _, ended in
            if ended { withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { tour = nil } }
        }
        #if DEBUG
        .task { await startDebugTour() }
        #endif
    }

    /// What the bank files picker offers: the server's CSV and XML, or phone mode's bank files.
    private var importTypes: [UTType] { modes.phone == nil ? [.commaSeparatedText, .xml] : PhoneImportTypes.all }

    /// The guide's Choose file: the picker for this mode (the categories first in phone mode while none is chosen);
    /// the files are imported once the guide's sheet has closed (`close`, then `importPickedInGuide`).
    private func guideImport(close: @escaping () -> Void) -> GuideImport {
        GuideImport(types: importTypes, phone: modes.phone,
                    categoriesChanged: { await store.reloadAfterTransactionChange() }) { result in
            switch result {
            case let .success(urls): pickedInGuide = urls
            case let .failure(error): imports.show(error.localizedDescription, success: false)
            }
            close()
        }
    }

    private func importPickedInGuide() {
        guard !pickedInGuide.isEmpty else { return }
        let urls = pickedInGuide
        pickedInGuide = []
        Task { await imports.receive(urls) }
    }

    /// The tour, from the first screen or Settings → Help: it fills its made-up store and shows in place of the
    /// dashboard. When it ends, the first screen comes back while there is no data (`MainScreen`).
    private func startTour() {
        guard tour == nil else { return }
        let model = TourModel()
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { tour = model }
        Task { await model.start() }
    }

    /// The band in the tour: the word ends its screens as everywhere, but red mode is not part of the tour.
    private func tourBand(in geometry: GeometryProxy) -> AresiumBand {
        AresiumBand(palette: palette, width: geometry.size.width, hidden: theme.isAnimating) { _ in }
    }

    #if DEBUG
    /// Screenshots: `-tour <step>` starts the tour at that step (1–12); `-tourSettings` opens its Settings.
    private func startDebugTour() async {
        guard sampleActive, tour == nil, let value = LaunchArguments.value("-tour"),
              let step = Int(value).flatMap(TourStep.init(rawValue:)) else { return }
        let model = TourModel()
        tour = model
        await model.start(at: step)
        if LaunchArguments.current.contains("-tourSettings") { model.openSettings() }
    }
    #endif

    /// What shows in place of the dashboard: the tour, the store's state, the first screen (phone mode without data) or
    /// the dashboard.
    private var mainScreen: MainScreen {
        MainScreen.choose(tour: tour?.phase, hasMode: showsDashboard, waitsForServerLogin: waitsForServerLogin,
                          phonePayments: modes.phone?.summary.payments)
    }

    /// Import data (the first screen): the category picker first while none is chosen, then the file picker.
    private func importData() {
        importFlow.start(hasCategories: modes.phone?.hasChosenCategories ?? true)
    }

    /// Server mode before its login is renewed at launch: nothing to show yet.
    private var waitsForServerLogin: Bool {
        modes.state == .server && !sampleActive && store.dashboard == nil && session.isRestoring
    }

    /// Phone mode before any category is chosen: the import button opens the category picker first, then the file
    /// picker (`ImportFlow`).
    private var chooseCategoriesFirst: (() -> Void)? {
        guard let phone = modes.phone, !phone.hasChosenCategories else { return nil }
        return { importFlow.start(hasCategories: false) }
    }

    /// The dashboard (or phone mode's first screen) shows: the server sample, or a mode with its backend.
    private var showsDashboard: Bool {
        if sampleActive && !samplePhone { return true }
        switch modes.state {
        case .server, .phone: return true
        case .opening, .failed: return false
        }
    }

    /// The lock screen's "Forgot the code?": Aresium's data on this iPhone goes, then the lock. In server mode the
    /// login ends too, so the lock never opens the server's data to someone without the code.
    private func handOverForgotCode() {
        let modes = modes, session = session, lock = lock
        lockWindow.forgotLogsOut = { modes.state == .server && session.token != nil }
        lockWindow.forgot = {
            let logsOut = modes.state == .server && session.token != nil
            try await modes.deleteLocalData()
            if logsOut { session.logOut() }
            lock.reset()
        }
    }

    #if DEBUG
    /// `-samplePhone` / `-samplePhoneEmpty`: the made-up phone store, then the screens the arguments ask for.
    private func startPhoneSample() async {
        guard samplePhone, modes.phone == nil else { return }
        let arguments = LaunchArguments.current
        do {
            let (phone, storage) = try await PhoneSample.backend(empty: arguments.contains("-samplePhoneEmpty"))
            // `-samplePhoneEmpty -sampleChosen`: the first screen with categories chosen (Import data opens the files).
            if arguments.contains("-sampleChosen"), phone.summary.chosen.isEmpty {
                for id in PhoneSample.chosen { try await phone.choose(id) }
            }
            await modes.showFixed(phone, storage: storage)
            // `-importData`: the first screen's Import data at launch (the category picker first, or the files).
            if arguments.contains("-importData") { importData() }
            if arguments.contains("-sampleLayout"), let file = PhoneSample.unknownBankFile() {
                imports.debugImport([file])           // the window; `-sampleReading 2|columns` in it
            }
            if arguments.contains("-sampleFormat") { await showSampleFormat(phone) }
            if arguments.contains("-sampleImportResult") {
                // An import's result line, as a bank file of 45 payments leaves it (made-up numbers).
                let result = PhoneImportResult(name: "Umsaetze-Girokonto.csv", added: 42, already: 3, sorted: 38, waiting: 4)
                imports.debugShowResult(ImportWording.summary([result]), files: [result.displayMessage])
            }
        } catch {
            modes.debugShow(.failed(error.localizedDescription))
        }
    }

    /// `-sampleFormat`: the made-up unknown bank's file, confirmed as the engine reads it first, imported for real: the
    /// result with the send card. `-formatBank <name>` types the name, `-formatPhase sending|sent|kept|refused|badName`
    /// shows a state (`-formatMessage <text>`: the server's refusal), `-openFormatDetails` opens "What is sent?",
    /// `-formatFocus` the keyboard on the name.
    private func showSampleFormat(_ phone: PhoneBackend) async {
        guard let file = PhoneSample.unknownBankFile(),
              let layout = try? await phone.engine.readings(file.data, layouts: []).first?.layout else { return }
        try? await phone.saveLayout(layout)
        imports.debugImport([file])
        for _ in 0..<50 where imports.banner?.share == nil { try? await Task.sleep(for: .milliseconds(100)) }
        guard let card = imports.banner?.share else { return }
        if let bank = LaunchArguments.value("-formatBank") { card.bank = bank }
        switch LaunchArguments.value("-formatPhase") {
        case "sending": card.debugPhase(.sending)
        case "sent": card.debugPhase(.sent)
        case "kept": card.debugPhase(.kept)
        case "refused": card.debugPhase(.refused(LaunchArguments.value("-formatMessage") ?? BankFormatCard.refusedLine()))
        case "badName": card.debugProblem(LaunchArguments.value("-formatMessage") ?? BankFormatCard.refusedLine())
        default: break
        }
    }
    #endif

    /// Server mode's line when its login could not be renewed (offline at launch), with Retry. Phone mode needs no
    /// login, so it never shows there.
    @ViewBuilder private var restoreFeedback: some View {
        if modes.state == .server, session.needsRestoreRetry, let error = session.error {
            HStack {
                Text(error).foregroundStyle(palette.expenseText)
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

    /// A screen's header; the tour's screens name its store (`in`) and open its own Settings.
    private func header(_ route: DashboardRoute? = nil, in dashboard: DashboardStore? = nil,
                        openSettings: (() -> Void)? = nil) -> some View {
        let store = dashboard ?? store
        let category = route.flatMap { store.category($0.category, side: $0.side) }
        let subtitle: String? = route.map { route in
            if let key = route.month {
                let month = store.dashboard?.months.first { $0.key == key }?.title() ?? key
                return String(localized: "\(month) · activities")
            }
            return route.side == .income ? String(localized: "Monthly income") : String(localized: "Monthly spend")
        }
        return ScreenHeader(title: route.map { CategoryName.shown($0.category) } ?? "Aresium", subtitle: subtitle,
                            category: category, palette: palette,
                            back: route == nil ? nil : { back(route) },
                            toggleTheme: {
            guard !theme.isAnimating else { return }
            if theme.red {
                bandLanding = nil
                theme.send(.header, reduceMotion: reduceMotion)       // the X: back to light or dark
            } else {
                appearance = Appearance.toggled(from: appearanceScheme).rawValue    // the sun: the app's appearance
            }
        }, openSettings: openSettings ?? { showsSettings = true })
    }

    /// The header's back button: the tour's dashboard or the person's, whichever shows.
    private func back(_ route: DashboardRoute?) {
        if let tour {
            var place = tour.place
            if !place.path.isEmpty { place.path.removeLast() }
            tour.update(place)
        } else if !place.path.isEmpty {
            place.path.removeLast()
        }
    }

    /// Settings → Log out: ends the shared login in every Ares app. Server mode ends with it; phone mode's data stays on
    /// the phone (it never belonged to the login).
    private func logOut() {
        place.path = []
        session.logOut()
    }
}

#if DEBUG
#Preview { ContentView(lockWindow: LockWindow(lock: .forLaunch(arguments: ["-sampleData"])), arguments: ["-sampleData"]) }
#endif
