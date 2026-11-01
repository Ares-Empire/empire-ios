import Foundation
import Observation
import os

// The tour (briefs 24, 25, 42, 59 and 77): the real dashboard on a made-up store of its own, nineteen steps (eighteen
// while the graph is hidden in Settings), each pointing at one real control with one short sentence; it goes on when
// the person does the thing or taps Next. One walk through what Aresium does (brief 59, Patrik 2026-10-31: "explains
// everything and is coherent"): the start screen, its graph and its search, a category, a payment and what can be done
// with it, a list's swipe and adding up, then Settings' places in their real order, the import button, done. Everything
// the tour shows and changes is in `TourWorld`, a store in a temporary folder that is deleted when the tour ends: the
// person's own store, categories, learned shops, names and choices of adding up are never opened by it. Its Settings
// also point at Own names, Messages, the Lock, the Dashboard's switches and Contact & support, which in the tour only
// go on: no lock is set, no message planned and nothing is sent. The look is `Screens/TourScreens.swift`.

/// The tour's steps, in order. The raw value names a step (DEBUG `-tour <n>`); the card counts the steps a tour shows.
nonisolated enum TourStep: Int, CaseIterable, Sendable {
    case welcome = 1, income, overview, graph, search, category, payment, rename, switchCategory, addUp, sumIcon,
         allFrom, categories, messages, lock, dashboardSettings, contact, importFiles, done

    /// The steps a tour shows: all of them, but the graph's only while the dashboard shows the graph (Settings →
    /// Dashboard → Graph, `GraphSetting`); without the graph that step would point at nothing.
    static func steps(showingGraph: Bool) -> [TourStep] {
        showingGraph ? allCases : allCases.filter { $0 != .graph }
    }

    /// The card's sentence. `showingGraph`: whether the tour shows the graph; without it no card mentions it.
    func text(_ language: AppLanguage = .current, showingGraph: Bool = true) -> String {
        switch self {
        case .welcome: language.string("This is Aresium with made-up sample data.")
        case .income: language.string("Swipe sideways: your income.")
        case .overview: language.string("Overview shows all months.")
        case .graph:
            language.string("Hold the graph and slide to read each month. A tap opens the month, or the day where it shows days.")
        case .search: language.string("Search a name, your own or the bank's. A tap shows all its payments.")
        case .category: language.string("Tap a category: its payments this month.")
        case .payment: language.string("Every payment in detail.")
        case .rename: language.string("Tap the name to rename it, for this payment or all from this shop.")
        case .switchCategory: language.string("Sorted wrong? Tap the category. Aresium remembers the shop.")
        case .addUp: language.string("Swipe a payment left: Add up makes one row of its name.")
        case .sumIcon: language.string("Here you add up every name in this list.")
        case .allFrom: language.string("Swipe the row again: All shows every payment of the name. Hold a row for more.")
        case .categories: language.string("Here you choose categories and add your own. Own names can be turned off.")
        case .messages: language.string("Reminders to import and a review of each month, made on this iPhone.")
        case .lock: language.string("Protect Aresium with Face ID or a code of your own.")
        case .dashboardSettings:
            showingGraph ? language.string("Here you switch the graph, its moving away as you scroll, and adding up in every list.")
                         : language.string("Here you add up same names in every list.")
        case .contact: language.string("Questions, ideas, problems? Write to us here.")
        case .importFiles: language.string("Files from your bank, receipts and cash come in here.")
        case .done: language.string("Done. Now with your own data.")
        }
    }

    /// While a control is pointed at, the rest takes no taps; the swipe to income needs the whole page.
    var holdsTheRest: Bool { self != .income }

    /// The steps that show a row's swipe: its swipe and long press work on the row the ring is on (the back swipe stays
    /// off, as the header's arrow takes no taps).
    var swipesRows: Bool { self == .addUp || self == .allFrom }
}

/// The real controls the tour points at; each marks itself with `.tourAnchor(_:)`.
nonisolated enum TourTarget: Hashable, Sendable {
    case pageDots, range, graph, importButton, settings
    /// The start screen's search, the magnifying glass in its header (brief 77).
    case search
    /// A category's row on the start screen, by the name the dashboard shows.
    case category(String)
    /// A payment's row in a month's list, by its id.
    case payment(String)
    /// A name's payments added up in a category's list (brief 53), by the name's key.
    case summed(String)
    /// The name on a payment's page and its pen (brief 47).
    case paymentName
    /// The category's chip and its pen on a payment's page.
    case change
    /// The icon of adding up in a category's list's header (brief 53).
    case sumIcon
    /// The tour's Settings: Your data on this iPhone (Categories and Own names), Messages, the Lock section, the
    /// Dashboard's switches and Contact & support.
    case dataRows, messagesRow, lockRow, dashboardRows, contactRow
}

/// The tour's state, one model that tests drive step by step: the step, where its dashboard is (`DashboardPlace`), which
/// of its sheets are open, and the made-up world under it.
@MainActor @Observable
final class TourModel {
    enum Phase: Equatable {
        /// The made-up store is being filled.
        case preparing
        case running
        /// The made-up store could not be made.
        case failed(String)
        /// Ended: the made-up store is deleted.
        case ended
    }

    private(set) var phase = Phase.preparing
    private(set) var step = TourStep.welcome
    /// Whether the tour's dashboard shows the graph: the person's setting when the tour starts (their Settings cannot
    /// be opened during it), so the screens and the steps agree.
    let showsGraph: Bool
    /// Whether that graph moves away while its list scrolls (Settings → Dashboard, `GraphMotionSetting`, brief 56): the
    /// person's setting when the tour starts, as the graph's.
    let graphMoves: Bool
    /// The steps this tour shows, in order (`TourStep.steps`).
    let steps: [TourStep]
    /// Where the tour's dashboard is: its pushed screens, Current or Overview, the page, the open payment.
    private(set) var place = DashboardPlace()
    /// The tour's Settings (its categories, and the rows to point at), and its category picker pushed there.
    private(set) var showsSettings = false
    private(set) var showsCategories = false
    /// "How do I get my file?" from the import step.
    var showsGuide = false
    /// The name the person added up at the Add up step (its key), so the next swipe step points at the same row.
    private(set) var addedUpName: String?
    private(set) var world: TourWorld?
    @ObservationIgnored private let makeWorld: () async throws -> TourWorld
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "tour")

    init(showsGraph: Bool = GraphSetting.isShown(), graphMoves: Bool = GraphMotionSetting.moves(),
         makeWorld: @escaping () async throws -> TourWorld = { try await TourWorld.make() }) {
        self.showsGraph = showsGraph
        self.graphMoves = graphMoves
        self.steps = TourStep.steps(showingGraph: showsGraph)
        self.makeWorld = makeWorld
    }

    /// How many steps this tour shows, and the current one's place among them (the card's "Tour · 3 of 18").
    var count: Int { steps.count }
    var number: Int { (steps.firstIndex(of: step) ?? 0) + 1 }

    /// The current card's sentence.
    var text: String { step.text(showingGraph: showsGraph) }

    /// The step after the current one; nil at the last.
    var nextStep: TourStep? {
        guard let index = steps.firstIndex(of: step), steps.indices.contains(index + 1) else { return nil }
        return steps[index + 1]
    }

    /// Fills the made-up store, then shows `first` (the welcome; DEBUG screenshots start at any step; a step this tour
    /// leaves out starts at the one after it).
    func start(at first: TourStep = .welcome) async {
        guard phase == .preparing, world == nil else { return }
        do {
            let world = try await makeWorld()
            guard phase == .preparing else {
                world.delete()                      // ended while it was being made
                return
            }
            self.world = world
            world.dashboard.onRecategorised = { [weak self] in self?.paymentRecategorised() }
            world.dashboard.onRenamed = { [weak self] in self?.paymentRenamed() }
            world.dashboard.sums.onChange = { [weak self] in self?.sumsChanged() }
            phase = .running
            go(to: steps.first { $0.rawValue >= first.rawValue } ?? .welcome)
        } catch {
            Self.log.error("the tour's store was not made: \(String(describing: error), privacy: .public)")
            phase = .failed(error.localizedDescription)
        }
    }

    /// End tour (on the card at every step, the one button at the last): the made-up store is deleted; the app is as it
    /// was before.
    func end() {
        guard phase != .ended else { return }
        phase = .ended
        // Its sheets close with it.
        place.payment = nil
        closeSheets()
        world?.delete()
        world = nil
    }

    /// "Next": the following step (the last ends the tour).
    func next() {
        guard phase == .running else { return }
        if let next = nextStep { go(to: next) } else { end() }
    }

    // MARK: what the person does

    /// The tour's dashboard moved (a swipe, Current/Overview, a category, a payment or a name's page opened, Back).
    /// Doing what the step asks moves on. The graph's step asks nothing (a tap on a month may open its page there, on a
    /// day a day's), nor the search's (the search and the names it opens are free to try there): Next goes on.
    func update(_ new: DashboardPlace) {
        let old = place
        place = new
        guard phase == .running else { return }
        let done: Bool
        switch step {
        case .income: done = new.side == .income && old.side != .income
        case .overview: done = !new.current && old.current
        case .category: done = new.path.count > old.path.count && new.path.last?.month != nil
        case .payment: done = new.payment != nil && old.payment == nil
        case .allFrom: done = new.path.count > old.path.count && new.path.last?.isNamePage == true
        default: done = false
        }
        if done { next() }
    }

    /// The gear: the tour's Settings.
    func openSettings() { showsSettings = true }

    func closeSettings() {
        showsSettings = false
        showsCategories = false
    }

    /// Settings → Categories, pushed or popped.
    func setCategoriesShown(_ shown: Bool) { showsCategories = shown }

    /// The import button: in the tour it only answers the import step (no file is picked into the made-up store).
    func importTapped() {
        if phase == .running && step == .importFiles { next() }
    }

    /// A row of the tour's Settings (Own names, Messages, the Lock, the Dashboard's switches, Contact & support): in the
    /// tour it only answers the step that points at it. No lock is set, no message planned, no form opens, nothing is
    /// sent, no setting changes.
    func settingsRowTapped(_ row: TourTarget) {
        if phase == .running && target == row { next() }
    }

    /// A payment's category change finished (its sheet closed, the shop question answered).
    func paymentRecategorised() {
        if phase == .running && step == .switchCategory { next() }
    }

    /// A payment's name was saved (on its page, the shop's other payments asked about).
    func paymentRenamed() {
        if phase == .running && step == .rename { next() }
    }

    /// The tour's choices of adding up changed (in memory, its own): the Add up step goes on once a name is added up
    /// in the list (the swipe's or the long press's Add up), the icon's step with its tap.
    func sumsChanged() {
        guard phase == .running else { return }
        switch step {
        case .addUp:
            guard let list = shownList?.list, let sum = list.firstSummed else { return }
            addedUpName = sum.key
            next()
        case .sumIcon:
            next()
        default:
            break
        }
    }

    // MARK: where the tour points

    /// The control the current step points at, nil when none (the first and last step; while the person works in a
    /// sheet the step leads to, or looks at a page the step does not point into).
    var target: TourTarget? {
        guard phase == .running else { return nil }
        switch step {
        case .welcome, .done: return nil
        case .income: return .pageDots
        case .overview: return .range
        case .graph: return .graph
        // The magnifying glass on the start screen; on the search's page and the names it opens, nothing: free to try.
        case .search: return place.path.isEmpty ? .search : nil
        case .category: return firstCategory.map { .category($0) }
        case .payment: return firstPayment.map { .payment($0.id) }
        case .rename: return place.payment != nil ? .paymentName : firstPayment.map { .payment($0.id) }
        case .switchCategory: return place.payment != nil ? .change : firstPayment.map { .payment($0.id) }
        case .addUp: return place.payment == nil ? addUpRow.map { .payment($0.id) } : nil
        case .sumIcon: return place.payment == nil && shownList?.list.canSum == true ? .sumIcon : nil
        case .allFrom: return place.payment == nil ? allFromRow : nil
        case .categories: return showsCategories ? nil : showsSettings ? .dataRows : .settings
        case .messages: return showsSettings ? .messagesRow : .settings
        case .lock: return showsSettings ? .lockRow : .settings
        case .dashboardSettings: return showsSettings ? .dashboardRows : .settings
        case .contact: return showsSettings ? .contactRow : .settings
        case .importFiles: return .importButton
        }
    }

    /// The tour points at a control and keeps taps off the rest of the screen, the header's back arrow included. The
    /// back swipe is off meanwhile too, since it does only what the arrow does (brief 38); a swipe the tour lets through
    /// reaches `update` through the dashboard's path, as the arrow does. So are a payment row's long press and swipe
    /// (brief 41) except at the swipe steps (`rowShortcuts`): at the payment step the row the ring is on opens the
    /// payment's page, and a menu there would skip the page the card points at. While the tour points at nothing (the
    /// first and last step), they work as everywhere, on the made-up store.
    var holdsTheScreen: Bool { target != nil && step.holdsTheRest }

    /// The rows' swipe and long press: wherever the tour does not hold the screen, and at the steps that show the swipe
    /// (`TourStep.swipesRows`) on the row the ring is on (the veil keeps the other rows' touches off).
    var rowShortcuts: Bool { !holdsTheScreen || step.swipesRows }

    /// The category row the category step points at: the tour's first category when the page shows it, else the
    /// page's first row.
    private var firstCategory: String? {
        guard let dashboard = world?.dashboard else { return nil }
        let rows = dashboard.rows(side: place.side, current: place.current)
        if let preferred = world?.firstCategory, rows.contains(where: { $0.category.name == preferred }) { return preferred }
        return rows.first?.category.name
    }

    /// The category's month list on top of the tour's dashboard, as its rows show (names added up as chosen), if one is.
    private var shownList: (route: DashboardRoute, list: PaymentList)? {
        guard let dashboard = world?.dashboard, let route = place.path.last, route.isCategoryList,
              let month = route.month else { return nil }
        return (route, dashboard.paymentList(category: route.category, month: month, side: route.side))
    }

    /// The first payment of the month list on screen, if one is (a single row: nothing is added up before the Add up
    /// step).
    private var firstPayment: Transaction? {
        guard let dashboard = world?.dashboard, let route = place.path.last, route.isCategoryList,
              let month = route.month else { return nil }
        return dashboard.transactions(category: route.category, month: month, side: route.side).first?.transaction
    }

    /// The Add up step's row: the list's first single row whose name has more payments there (its swipe offers Add up).
    private var addUpRow: Transaction? {
        guard let list = shownList?.list else { return nil }
        for case let .payment(row, addsUp) in list.entries where addsUp { return row.transaction }
        return nil
    }

    /// The All step's row: the name added up at the Add up step (its summed row, or its first row when separated
    /// again), else the list's first name with more payments there.
    private var allFromRow: TourTarget? {
        guard let list = shownList?.list else { return nil }
        if let key = addedUpName, list.sumKeys.contains(key) {
            if list.summed(key) != nil { return .summed(key) }
            if let row = list.rows.first(where: { PaymentList.nameKey($0.transaction) == key }) {
                return .payment(row.transaction.id)
            }
        }
        for entry in list.entries {
            switch entry {
            case let .summed(sum): return .summed(sum.key)
            case let .payment(row, addsUp) where addsUp: return .payment(row.transaction.id)
            default: continue
            }
        }
        return nil
    }

    // MARK: getting each step's screen ready

    private func go(to step: TourStep) {
        self.step = step
        prepare(step)
    }

    /// What a step needs on screen, without undoing what the person just did: the step before's action stays (the
    /// income page stays after the swipe, Overview for the graph after it was tapped, the name's page the swipe's All
    /// opened while the gear is pointed at).
    private func prepare(_ step: TourStep) {
        switch step {
        case .welcome, .done, .importFiles: toStart()
        case .income:
            toStart()
            place.side = .expenses
        case .overview:
            toStart()
            place.current = true
        case .graph:
            // Overview's months: the ones a hold reads and a tap opens.
            toStart()
            place.current = false
        case .search:
            // The start screen, as the graph left it: its header has the search.
            toStart()
        case .category:
            toStart()
            place.current = true
            place.side = .expenses
        case .payment:
            closeSheets()
            showList()
        case .rename, .switchCategory:
            closeSheets()
            showList()
            if place.payment == nil { place.payment = firstPayment }
        case .addUp, .sumIcon, .allFrom:
            // The list under the payment's page, which closes.
            closeSheets()
            place.payment = nil
            showList()
        case .categories:
            // The gear is in every screen's header: the page stays, the payment closes.
            closeSheets()
            place.payment = nil
        case .messages, .lock, .dashboardSettings, .contact:
            // The tour's Settings, open on its rows (the category picker closes).
            showsGuide = false
            showsCategories = false
            place.payment = nil
            showsSettings = true
        }
    }

    private func toStart() {
        closeSheets()
        place.payment = nil
        place.path = []
    }

    private func closeSheets() {
        showsSettings = false
        showsCategories = false
        showsGuide = false
        place.day = nil
    }

    /// A category's month list on top of the stack: the one shown, or the one a page shown was opened from (back to
    /// it), else this month's of the tour's first category.
    private func showList() {
        if let index = place.path.lastIndex(where: \.isCategoryList) {
            if index < place.path.count - 1 { place.path.removeSubrange((index + 1)...) }
            return
        }
        guard let dashboard = world?.dashboard else { return }
        place.payment = nil
        place.current = true
        place.side = .expenses
        guard let category = firstCategory, let month = dashboard.currentMonth?.key else { return }
        place.path = [DashboardRoute(category: category, side: .expenses, month: month)]
    }
}

extension DashboardRoute {
    /// A category's payments in one month (not a name's, the Cash page's or a month's page).
    var isCategoryList: Bool { month != nil && !cash && name == nil && monthPage == nil }
    /// A name's page with its months (not one of its month's pages).
    var isNamePage: Bool { name != nil && month == nil }
}

extension PaymentList {
    /// The first name added up in the list, if any.
    var firstSummed: SummedPayments? {
        for case let .summed(sum) in entries { return sum }
        return nil
    }
}

/// The tour's made-up world: a phone store in a temporary folder of its own, filled through the real import with
/// `TourData`, and the dashboard, imports and widget numbers that go with it (the widget numbers in that folder too, never
/// the App Group). `delete()` removes the folder; nothing here ever opens `PhoneStorage.standard`.
@MainActor
final class TourWorld {
    /// The folder's name starts with this; a folder left by a tour that never ended (the app was closed) is removed at
    /// the next launch (`removeLeftovers`).
    static let folderPrefix = "aresium-tour-"

    let root: URL
    let phone: PhoneBackend
    let dashboard: DashboardStore
    let imports: ImportStore
    /// The name the dashboard shows for the tour's first category (Groceries in the app's language).
    let firstCategory: String?
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "tour")

    private init(root: URL, phone: PhoneBackend, dashboard: DashboardStore, imports: ImportStore, firstCategory: String?) {
        self.root = root
        self.phone = phone
        self.dashboard = dashboard
        self.imports = imports
        self.firstCategory = firstCategory
    }

    /// Makes and fills the store in a new folder inside `parent` (the app's temporary folder; tests give their own).
    static func make(in parent: URL = FileManager.default.temporaryDirectory, now: Date = .now,
                     makeEngine: () async throws -> AresiumEngine = { try await AresiumEngine.bundledForPhone() }) async throws -> TourWorld {
        let root = parent.appending(path: folderPrefix + UUID().uuidString, directoryHint: .isDirectory)
        do {
            let storage = PhoneStorage(root: root)
            let ledger = try await Task.detached { try storage.open() }.value
            let phone = PhoneBackend(ledger: ledger, engine: try await makeEngine(),
                                     defaults: UserDefaults(suiteName: "aresium.phone.tour")!)
            phone.today = { LedgerExport.day(now) }
            try await phone.load()
            for id in TourData.chosen { try await ledger.choose(id) }
            try await phone.addCustom(named: TourData.customName(), side: .spend)
            _ = try await phone.importFiles([TourData.bankFile(now: now)], auth: BackendAuth(token: nil))
            // Its own session, never logged in: the tour asks no server and follows no login.
            let session = EmpireSession(app: .aresium, storage: TourTokens(), restoreOnLaunch: false)
            let widgetFolder = root.appending(path: "widget", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: widgetFolder, withIntermediateDirectories: true)
            let widget = WidgetSnapshotPublisher(store: WidgetSnapshotStore(directory: widgetFolder), reloadTimelines: {})
            // Its own choices of adding up (brief 53), empty and in memory (never the person's `aresium.sums`): the
            // swipe's Add up, the list's icon and the name's page's switch work on them (brief 59). Nothing is added
            // up before the tour's Add up step, so the rows the earlier steps point at are single.
            let dashboard = DashboardStore(session: session, backend: phone, widgetPublisher: widget,
                                           sums: PaymentSums())
            await dashboard.reload()
            if let error = dashboard.error { throw TourError.dashboard(error) }
            let first = try await phone.categories().name(of: TourData.firstCategory)
            return TourWorld(root: root, phone: phone, dashboard: dashboard, imports: ImportStore(dashboard: dashboard),
                             firstCategory: first)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    /// Deletes the made-up store's folder (only ever a tour's own).
    func delete() {
        guard root.lastPathComponent.hasPrefix(Self.folderPrefix) else { return }
        do { try FileManager.default.removeItem(at: root) }
        catch { Self.log.error("the tour's folder was not deleted: \(String(describing: error), privacy: .public)") }
    }

    /// Removes tours' folders left in `parent` (a tour the app was closed in); call at launch, before any tour runs.
    static func removeLeftovers(in parent: URL = FileManager.default.temporaryDirectory) {
        let folders = (try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.lastPathComponent.hasPrefix(folderPrefix) {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    enum TourError: LocalizedError {
        case dashboard(String)
        var errorDescription: String? {
            switch self { case .dashboard(let message): message }
        }
    }
}

/// The tour's session keeps no login.
private final class TourTokens: TokenStorage {
    func read() throws -> String? { nil }
    func save(_ token: String) throws {}
    func delete() throws {}
}
