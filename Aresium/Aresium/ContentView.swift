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
    /// Settings → Dashboard → Graph (brief 42): the dashboard's graph, on by default and kept across launches.
    @AppStorage(GraphSetting.key) private var showsGraph = GraphSetting.shownByDefault
    /// Settings → Dashboard → the graph moving away while its list scrolls (brief 56), on by default.
    @AppStorage(GraphMotionSetting.key) private var graphMoves = GraphMotionSetting.movesByDefault
    /// Light or dark as Settings → Appearance (or the iPhone) says; red mode shows over it.
    @Environment(\.appearanceScheme) private var appearanceScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var theme: ThemeState
    private let pausedIntroProgress: Double?
    private let restoresOnLaunch: Bool
    private let messagesActive: Bool
    /// Where the person's dashboard is (pushed screens, Current/Overview, the page, the open payment).
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
    @State private var heldLink: URL?
    @State private var showsSettings = false
    /// Import data's file picker (the first screen). The category picker follows an import that added payments while
    /// none is chosen (`ImportStore.asksForCategories`).
    @State private var picksFiles = false
    /// Import's receipts in phone mode: the document scanner, the photo picker and the sheet that reads, checks and keeps
    /// the receipt.
    @State private var receipts: ReceiptCaptureModel
    /// The after-import question shown now ("Is this the same payment?"), so closing it lets only that receipt wait.
    @State private var askedReceipt: String?
    /// Import → Add cash (brief 33): the window for a hand entry, while it is open.
    @State private var cashEntry: CashEntryModel?
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
        // Which names add up in a category's payments (brief 53): the person's, kept in the app's defaults; the samples
        // and the app while tests run keep theirs in memory (`-sampleSums on`: every name, as Settings' switch).
        #if DEBUG
        let sums = debugLaunch ? PaymentSums(choices: SumChoices(everywhere: LaunchArguments.value("-sampleSums") == "on"))
                               : PaymentSums(defaults: .standard)
        #else
        let sums = PaymentSums(defaults: .standard)
        #endif
        // The server sample shows the bundled dashboard; otherwise the backend comes with the mode (`ModeStore`).
        let store = sample && !phoneSample
            ? DashboardStore(session: session, sample: true, widgetPublisher: publisher, sums: sums)
            : DashboardStore(session: session, backend: nil, widgetPublisher: publisher, sums: sums)
        #if DEBUG
        messagesActive = !debugLaunch
        #else
        messagesActive = true
        #endif
        // Samples (and the app while tests run) only pretend to send a bank's format or name.
        #if DEBUG
        let outbox = sample || DebugLaunch.isTesting ? BankOutbox.sample()
                                                     : BankOutbox(file: PhoneStorage.standard.bankOutboxURL)
        #else
        let outbox = BankOutbox(file: PhoneStorage.standard.bankOutboxURL)
        #endif
        let imports = ImportStore(dashboard: store, outbox: outbox)
        let modes = ModeStore(session: session, dashboard: store, markerDefaults: markerDefaults)
        // A kept receipt: its line in the import's result banner, and the dashboard built again.
        let receipts = ReceiptCaptureModel { [modes] in modes.phone }
        receipts.saved = { [imports, store] line in
            imports.show(line, success: true)
            await store.reloadAfterTransactionChange()
        }
        _receipts = State(initialValue: receipts)
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
        }
        if phoneSample {
            // Screenshots: `-sampleOverview` (Overview, not Current), `-sampleCategory`. The graph follows the setting.
            // `-sampleIncome`: the income side, also for `-sampleCategory` (a payment of money in, brief 70).
            let side: DashboardSide = arguments.contains("-sampleIncome") ? .income : .expenses
            var place = DashboardPlace(current: !arguments.contains("-sampleOverview"), side: side)
            if let index = arguments.firstIndex(of: "-sampleCategory"), arguments.indices.contains(index + 1) {
                place.path = [DashboardRoute(category: arguments[index + 1], side: side)]
                if let month = arguments.firstIndex(of: "-sampleMonth"), arguments.indices.contains(month + 1) {
                    place.path.append(DashboardRoute(category: arguments[index + 1], side: side,
                                                     month: arguments[month + 1]))
                }
            }
            // `-openMonthPage <YYYY-MM>`: that month's page, as a tap on Overview's graph opens it (brief 56).
            if let month = LaunchArguments.value("-openMonthPage") {
                place.current = false
                place.path = [DashboardRoute(monthPage: month, side: .expenses)]
            }
            // Brief 77: `-openDay <YYYY-MM-DD>` that day's page, as a tap on its point opens it (`-daySide income` on
            // the income side); `-openSearch` the search (`-searchText <text>` typed in it).
            if let day = LaunchArguments.value("-openDay") {
                let side: DashboardSide = LaunchArguments.value("-daySide") == "income" ? .income : .expenses
                place.day = DayRoute(date: day, side: side)
            }
            if arguments.contains("-openSearch") { place.path = [.search] }
            // `-openCash`: the Cash page (this month's; `-cashMonth <YYYY-MM>` another; with `-sampleOverview` its months).
            if arguments.contains("-openCash") {
                let month = LaunchArguments.value("-cashMonth") ?? String(LedgerExport.day(.now).prefix(7))
                place.path = [DashboardRoute(category: "", side: .expenses, month: place.current ? month : nil, cash: true)]
            }
            _place = State(initialValue: place)
        }
        // Screenshots: `-openGuide list|<bank id>` (the guide), `-tour <step>` (the tour at that step, 1–18).
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
            var place = DashboardPlace(current: !arguments.contains("-sampleOverview"), side: side)
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
                            header(route, in: tour.world?.dashboard, imports: route == nil ? tourImport(tour) : nil,
                                   search: route == nil ? tourSearch(tour) : nil, openSettings: openSettings)
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
                    DashboardStack(store: store, palette: palette, place: $place, graph: showsGraph,
                                   graphMoves: graphMoves, band: band(in: geometry)) { route in
                        // The import button beside the gear on the start screen's title row (brief 56), only where the
                        // dashboard shows (the first screen has its own Import data); the search beside it (brief 77).
                        let start = route == nil && mainScreen == .dashboard
                        header(route, imports: start ? dashboardImport : nil,
                               search: start && store.offersSearch ? { place.open(.search) } : nil)
                        restoreFeedback
                    } root: {
                        switch mainScreen {
                        case .waitingForLogin:
                            // Server mode at launch: the saved login is being renewed before the server is asked.
                            ProgressView().tint(palette.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
                        case .firstScreen:
                            PhoneFirstScreen(imports: imports, palette: palette, band: band(in: geometry),
                                             restoreProblem: phoneData.problem, importChoices: phoneImportChoices,
                                             startTour: startTour, openGuide: { showsGuide = true },
                                             restore: { restoringExport = true })
                        default:
                            StartScreen(store: store, palette: palette, current: $place.current,
                                        side: $place.side, graph: showsGraph, graphMoves: graphMoves,
                                        band: band(in: geometry), openGuide: { showsGuide = true },
                                        openDay: { place.day = $0 }) {
                                place.path.append($0)
                            }
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
                // A month review opened from its message stays on screen while the person reads it; leaving the app
                // brings Current back to this month, so it never quietly shows an old month later.
                if phase == .background { store.showReview(month: nil) }
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
                // The other mode's data. While the phone's store opened nothing was shown, so a path set meanwhile (a
                // DEBUG sample's `-sampleCategory`) stays.
                if old != new, old == .phone || old == .server {
                    place.path = []
                    place.day = nil
                }
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
            .onOpenURL(perform: route)
            .overlay(alignment: .bottom) {
                ImportFeedback(store: imports, palette: palette, offer: reminderOffer)
            }
            .sheet(isPresented: $showsSettings, onDismiss: importPickedInGuide) {
                SettingsScreen(app: SettingsApp(name: "Aresium",
                                                signInNote: String(localized: "Only for an Aresium server of your own. Your data here stays on this iPhone."),
                                                licences: [.shopList()]),
                               session: session, sample: sampleActive, logOut: logOut) {
                    if modes.phone != nil { PhoneSettingsSection(modes: modes, data: phoneData, palette: palette) }
                    // Brief 46: Aresium's own messages (phone mode), after the data they are about, before the Lock.
                    if modes.phone != nil, let messages = store.messages {
                        MessagesSettingsSection(messages: messages, lock: lock)
                    }
                    LockSettingsSection(lock: lock)
                    // Last of Aresium's own, so it sits just above General → Appearance: how the app looks. Adding up
                    // names (brief 53) only in phone mode, where payments have names.
                    DashboardSettingsSection(sums: modes.phone != nil ? store.sums : nil)
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
            .sheet(isPresented: Binding(get: { showsCategoriesAfterImport },
                                        set: { if !$0 { imports.categoriesClosed() } })) {
                // After an import that added payments while no category is chosen (`ImportStore`): ticking sorts them.
                if let phone = modes.phone {
                    NavigationStack {
                        CategoryPickerScreen(model: CategoryPickerModel(phone: phone) {
                            await store.reloadAfterTransactionChange()
                        }, afterImport: true, done: { imports.categoriesClosed() })
                    }
                    .presentationBackground(Ink.background)
                }
            }
            .background {
                // Import data's file picker, on a view of its own (one file picker per view; the restore's is below).
                Color.clear
                    .fileImporter(isPresented: $picksFiles, allowedContentTypes: importTypes,
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
            .receiptCapture(receipts, palette: palette)
            .cashEntry($cashEntry, saved: cashEntrySaved)
            .sheet(item: Binding(get: { pendingReceiptQuestion }, set: { if $0 == nil { receiptQuestionClosed() } })) { question in
                // After a bank import: a waiting card receipt with payments to ask about, once each.
                if let phone = modes.phone {
                    ReceiptQuestionSheet(question: question, phone: phone, palette: palette) {
                        await store.reloadAfterTransactionChange()
                    }
                    .onAppear { askedReceipt = question.id }
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
        .onChange(of: MessageTapRouter.shared.openedURL, initial: true) { _, _ in
            if let url = MessageTapRouter.shared.take() { route(url) }
        }
        .onChange(of: tour != nil) { _, touring in store.messages?.setTour(touring) }
        .onChange(of: modes.state) { _, _ in routeHeldLink() }
        .onChange(of: lock.isLocked) { _, _ in routeHeldLink() }
        .accessibilityHidden(lock.isLocked)
        .background { LockWindowReader(lockWindow: lockWindow) }
        .task { store.installMessages(lock: lock, active: messagesActive) }
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

    /// The guide's Choose file: the file picker for this mode; the files are imported once the guide's sheet has closed
    /// (`close`, then `importPickedInGuide`), so the import's own windows can show.
    private func guideImport(close: @escaping () -> Void) -> GuideImport {
        GuideImport(types: importTypes) { result in
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

    /// Widget links, notification taps and shared files all end the tour before opening the person's own store.
    private func route(_ url: URL) {
        tour?.end()
        if url.isFileURL {
            if lock.isLocked { heldFiles.append(url) }
            else { Task { await imports.receive([url], source: .shared) } }
        } else if let destination = AresiumURL(url: url) {
            // A cold-launch tap waits for the phone's store; a picker waits for the lock window to open too.
            if modes.state == .opening || (destination == .importData && lock.isLocked) {
                heldLink = url
                return
            }
            place.current = true
            place.side = .expenses
            place.day = nil
            switch destination {
            case .start: store.showReview(month: nil); place.path = []
            case .importData: picksFiles = modes.phone != nil
            case .review(let month): store.showReview(month: month); place.path = []
            case .category(let name):
                store.showReview(month: nil)
                place.path = [store.route(category: name, side: .expenses, current: true)]
            }
        }
    }

    private func routeHeldLink() {
        guard let url = heldLink else { return }
        heldLink = nil
        route(url)
    }

    /// The tour, from the first screen or Settings → Help: fills its made-up store in place of the dashboard.
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
    /// Screenshots: `-tour <step>` starts the tour at that step (1–18); `-tourSettings` opens its Settings.
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
                          phoneRecords: modes.phone.map { $0.summary.payments + $0.summary.receipts })
    }

    /// Import data (the first screen): the file picker.
    private func importData() {
        picksFiles = true
    }

    /// Phone mode's Import (the first screen's Import data, the dashboard's import button): Choose file, Scan receipt,
    /// Choose photo. Server mode keeps its own button (no receipts there yet).
    private var phoneImportChoices: ImportChoices {
        ImportChoices(chooseFile: importData, scanReceipt: receipts.scan, choosePhoto: receipts.choosePhoto,
                      addCash: addCash)
    }

    /// Import → Add cash: the window for cash spent or received by hand.
    private func addCash() {
        guard let phone = modes.phone else { return }
        cashEntry = CashEntryModel(phone: phone)
    }

    /// Add cash saved: its line in the import's result banner, and the dashboard built again.
    private func cashEntrySaved(_ entry: LedgerReceipt) async {
        let line = entry.direction == .in ? String(localized: "Saved: cash received.") : String(localized: "Saved: cash spent.")
        imports.show(line, success: true)
        await store.reloadAfterTransactionChange()
    }

    /// The category picker after an import shows in phone mode once no other sheet of the app is open (a file shared in
    /// while Settings or the guide is open waits for it to close).
    private var showsCategoriesAfterImport: Bool {
        imports.asksForCategories && modes.phone != nil && !showsSettings && !showsGuide
    }

    /// The after-import question to show now: once the import, its file check window and the category picker are done
    /// (the picker first when both are due), and no other window of the app is open.
    private var pendingReceiptQuestion: ReceiptQuestion? {
        guard let phone = modes.phone, !imports.isBusy, !imports.asksForCategories, imports.layoutRequest == nil,
              !showsSettings, !showsGuide, receipts.reading == nil, cashEntry == nil, tour == nil else { return nil }
        return phone.receiptQuestions.first
    }

    /// The one-time offer of the messages (brief 46), in the import result's place: after the first import that added
    /// payments, once its result (with the send card), the category picker and any other window are done. Never in the
    /// tour, nor in the samples (their messages are none, or a pretend model that offers only with
    /// `-sampleReminderOffer`).
    private var reminderOffer: ReminderOfferChoice? {
        guard let messages = store.messages else { return nil }
        let windowOpen = showsSettings || showsGuide || picksFiles || restoringExport || imports.layoutRequest != nil
            || pendingReceiptQuestion != nil || receipts.reading != nil || receipts.scanning || receipts.pickingPhoto
            || cashEntry != nil
        let moment = ReminderOffer.Moment(messages: messages, imports: imports, tour: tour != nil, locked: lock.isLocked,
                                          window: windowOpen)
        guard ReminderOffer.shows(moment) else { return nil }
        return ReminderOfferChoice(interval: messages.preferences.interval,
                                   turnOn: { acceptReminderOffer(messages) },
                                   notNow: { messages.declineReminderOffer() })
    }

    /// The offer's Turn on: both messages on (iOS asks now, the first time); once iOS allowed them, a line in the
    /// result's place says where they are changed. Waiting for iOS's answer happens off the tap (`idle`).
    private func acceptReminderOffer(_ messages: AresiumMessages) {
        messages.acceptReminderOffer()
        Task {
            await messages.idle()
            // Never in place of a result that came meanwhile.
            if messages.authorization == .allowed, messages.preferences.enabled, imports.banner == nil, !imports.isBusy {
                imports.show(String(localized: "Messages are on. You can change them in Settings."), success: true)
            }
        }
    }

    /// The question was closed without an answer: that receipt waits (asked again only after the next import).
    private func receiptQuestionClosed() {
        guard let phone = modes.phone, let id = askedReceipt,
              let question = phone.receiptQuestions.first(where: { $0.id == id }) else { return }
        phone.dismissQuestion(question)
    }

    /// Server mode before its login is renewed at launch: nothing to show yet.
    private var waitsForServerLogin: Bool {
        modes.state == .server && !sampleActive && store.dashboard == nil && session.isRestoring
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
            // Kept receipts before the store shows, so the first dashboard (and a page opened at launch) has them.
            if arguments.contains("-sampleReceipts") { try await PhoneSample.addReceipts(phone) }
            if arguments.contains("-sampleCash") { try await PhoneSample.addCash(phone) }
            if arguments.contains("-sampleShopReceipt") { try await PhoneSample.addShopReceipt(phone) }
            if arguments.contains("-sampleImportQuestion") { try await PhoneSample.addImportQuestions(phone) }
            await modes.showFixed(phone, storage: storage)
            // Settings → Messages and the offer on the sample (brief 46): a pretend model; nothing reaches iOS.
            store.installSampleMessages()
            SettingsTiming.startIfRequested()
            // `-importData`: the first screen's Import data at launch (the file picker).
            if arguments.contains("-importData") { importData() }
            // `-choosePhoto`: Import → Choose photo at launch (the photo picker). Receipts (the simulator has no camera):
            // the made-up receipt read through the real Vision path and the engine, as a scanned one.
            if arguments.contains("-choosePhoto") { receipts.choosePhoto() }
            // `-addCash spent|received` without `-openCash`: Import → Add cash at launch (`-openPaidFrom`: its Paid from).
            if !arguments.contains("-openCash"), let direction = LaunchArguments.value("-addCash") {
                cashEntry = CashEntryModel(direction: direction == "received" ? .in : .out, phone: phone)
            }
            await startReceiptSample(phone, arguments: arguments)
            // `-sampleImport`: the made-up bank file imported as if picked; on `-samplePhoneEmpty` (no category chosen)
            // the category picker opens after it, as after a real import (`-sampleTick`, `-samplePickerDone` in it).
            if arguments.contains("-sampleImport") { imports.debugImport([TourData.bankFile(now: .now)]) }
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

    /// Receipts in the phone sample (`ReceiptSample`, `PhoneSample.addReceipts`): `-sampleReceipt` the check window read
    /// from the register's code (the made-up shop's name is not sure; `-sampleReceiptShop REWE` prints a chain the shop
    /// list knows, so everything is sure), `-sampleReceiptUnsure` with fields to check first (no code, no
    /// payment line, a damaged total), `-sampleReceiptBlank` nothing read; `-sampleReceiptQuestion` the receipt saved
    /// with two bank payments of its amount: "Is this the same payment?"; `-sampleReceipts` made-up receipts kept in
    /// the store (waiting, cash, joined, another currency), then `-sampleCategory … -samplePhoneTransaction <shop>`
    /// opens one (`-editReceipt`: its Edit at once), `-openSheet settings -openReceipts` Settings → Receipts.
    /// `-sampleShopCorrection <name>`: the made-up receipt's shop was corrected to this name before (brief 33), so
    /// `-sampleReceipt` shows it as "Corrected by you before".
    private func startReceiptSample(_ phone: PhoneBackend, arguments: [String]) async {
        if let name = LaunchArguments.value("-sampleShopCorrection"),
           let change = ShopNames.change(read: ReceiptSample.shop, saved: name) {
            try? await phone.ledger.apply(change)
        }
        if arguments.contains("-sampleReceiptQuestion") {
            try? await PhoneSample.addQuestionPayments(phone)
            receipts.read([ReceiptPage(image: ReceiptSample.image())])
            await receipts.finished()
            if case let .checking(check)? = receipts.reading?.phase {
                check.method = .card
                await receipts.save(check)
            }
        } else if arguments.contains("-sampleReceipt") {
            receipts.read([ReceiptPage(image: ReceiptSample.image(shop: LaunchArguments.value("-sampleReceiptShop")))])
        } else if arguments.contains("-sampleReceiptUnsure") {
            receipts.read([ReceiptPage(image: ReceiptSample.unsureImage())])
        } else if arguments.contains("-sampleReceiptBlank") {
            receipts.read([ReceiptPage(image: ReceiptSample.blankImage())])
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

    /// The start screen's import button: phone mode's menu, or server mode's file picker.
    private var dashboardImport: ScreenHeader.Import {
        ScreenHeader.Import(store: imports, sample: store.isSample, choices: modes.phone == nil ? nil : phoneImportChoices)
    }

    /// The tour's import button: every item only answers its step (`ImportChoices.tour`).
    private func tourImport(_ tour: TourModel) -> ScreenHeader.Import? {
        guard let world = tour.world else { return nil }
        return ScreenHeader.Import(store: world.imports, sample: world.dashboard.isSample,
                                   choices: .tour { tour.importTapped() })
    }

    /// The tour's search (brief 77): the page on the tour's own stack, searching its made-up store.
    private func tourSearch(_ tour: TourModel) -> (() -> Void)? {
        guard tour.world?.dashboard.offersSearch == true else { return nil }
        return {
            var place = tour.place
            place.open(.search)
            tour.update(place)
        }
    }

    /// A screen's header; the tour's screens name its store (`in`) and open its own Settings. `imports`: the start
    /// screen's import button; `search`: its search (phone mode).
    private func header(_ route: DashboardRoute? = nil, in dashboard: DashboardStore? = nil,
                        imports: ScreenHeader.Import? = nil, search: (() -> Void)? = nil,
                        openSettings: (() -> Void)? = nil) -> some View {
        let store = dashboard ?? store
        let category = route.flatMap { $0.cash || $0.monthPage != nil ? nil : store.category($0.category, side: $0.side) }
        let subtitle: String? = route.flatMap { route -> String? in
            if route.search { return nil }                                                   // the search (brief 77)
            if route.monthPage != nil { return String(localized: "Expenses and income") }  // a month's page (brief 56)
            // A name's page (brief 44); its months' pages (brief 55) read as a category's month list, below.
            if route.name != nil && route.month == nil { return String(localized: "All payments") }
            // The Cash page: its month, or its months (Overview).
            if route.cash { return route.month.map { store.monthTitle($0) } ?? String(localized: "By month") }
            if let key = route.month {
                let month = store.dashboard?.months.first { $0.key == key }?.title() ?? key
                return String(localized: "\(month) · activities")
            }
            return route.side == .income ? String(localized: "Monthly income") : String(localized: "Monthly spend")
        }
        let title = route.map { route in
            if route.search { return String(localized: "Search") }
            if let month = route.monthPage { return store.monthTitle(month) }
            return route.name?.title ?? (route.cash ? String(localized: "Cash") : CategoryName.shown(route.category))
        } ?? "Aresium"
        return ScreenHeader(title: title, subtitle: subtitle,
                            category: category, palette: palette,
                            back: route == nil ? nil : { back(route) },
                            sums: route.flatMap { sumsIcon($0, in: store) },
                            search: search,
                            imports: imports,
                            leaveRed: {
            guard !theme.isAnimating, theme.red else { return }
            bandLanding = nil
            theme.send(.header, reduceMotion: reduceMotion)           // the X: back to light or dark
        }, openSettings: openSettings ?? { showsSettings = true })
    }

    /// A category's payments in a month (brief 53): the icon of adding up, while some name has more payments there
    /// (phone mode; not the Cash page or a name's page). A tap adds up every name in the category, or none.
    private func sumsIcon(_ route: DashboardRoute, in store: DashboardStore) -> ScreenHeader.Sums? {
        guard store.offersSums, let month = route.month, !route.cash, route.name == nil else { return nil }
        let list = store.paymentList(category: route.category, month: month, side: route.side)
        guard list.canSum else { return nil }
        let category = store.sumCategoryKey(route.category)
        // On while the list shows every name with two or more payments as one row (fix 58); the tap reads the list
        // again, in case the dashboard changed since the header was drawn.
        return ScreenHeader.Sums(on: list.allSummed) {
            let names = store.paymentList(category: route.category, month: month, side: route.side).sumKeys
            withAnimation(SumMotion.animation(reduceMotion: reduceMotion)) { store.sums.toggleCategory(category, names: names) }
        }
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
        place.day = nil
        session.logOut()
    }
}

#if DEBUG
#Preview { ContentView(lockWindow: LockWindow(lock: .forLaunch(arguments: ["-sampleData"])), arguments: ["-sampleData"]) }
#endif
