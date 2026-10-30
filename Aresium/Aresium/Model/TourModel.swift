import Foundation
import Observation
import os

// The tour (briefs 24 and 25): the real dashboard on a made-up store of its own, twelve steps, each pointing at one real
// control with one short sentence; it goes on when the person does the thing or taps Next. Everything the tour shows and
// changes is in `TourWorld`, a store in a temporary folder that is deleted when the tour ends: the person's own store,
// categories and learned shops are never opened by it. Its Settings also point at the lock and at Contact & support,
// which in the tour only go on: no lock is set and nothing is sent. The look is `Screens/TourScreens.swift`.

/// The tour's steps, in order.
nonisolated enum TourStep: Int, CaseIterable, Sendable {
    case welcome = 1, income, overview, graph, category, payment, switchCategory, categories, lock, contact, importFiles,
         done

    /// The step after this one; nil after the last.
    var next: TourStep? { TourStep(rawValue: rawValue + 1) }

    /// The card's sentence.
    func text(_ language: AppLanguage = .current) -> String {
        switch self {
        case .welcome: language.string("This is Aresium with made-up sample data.")
        case .income: language.string("Swipe sideways: your income.")
        case .overview: language.string("Overview shows all months.")
        case .graph: language.string("The trend as a graph.")
        case .category: language.string("Tap a category: its payments this month.")
        case .payment: language.string("Every payment in detail.")
        case .switchCategory: language.string("Sorted wrong? Pick the right category. Aresium remembers the shop.")
        case .categories: language.string("Here you choose categories and add your own.")
        case .lock: language.string("Protect Aresium with Face ID or a code of your own.")
        case .contact: language.string("Questions, ideas, problems? Write to us here.")
        case .importFiles: language.string("New files from your bank and your receipts come in here.")
        case .done: language.string("Done. Now with your own data.")
        }
    }

    /// While a control is pointed at, the rest takes no taps; the swipe to income needs the whole page.
    var holdsTheRest: Bool { self != .income }
}

/// The real controls the tour points at; each marks itself with `.tourAnchor(_:)`.
nonisolated enum TourTarget: Hashable, Sendable {
    case pageDots, range, graph, importButton, settings
    /// A category's row on the start screen, by the name the dashboard shows.
    case category(String)
    /// A payment's row in a month's list, by its id.
    case payment(String)
    /// "Change" in a payment's detail.
    case change
    /// Settings → Categories, the Lock section and Contact & support (the tour's Settings).
    case categoriesRow, lockRow, contactRow
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
    /// Where the tour's dashboard is: its pushed screens, Current or Overview, the page, the graph, the open payment.
    private(set) var place = DashboardPlace()
    /// The tour's Settings (its categories, and the lock and Contact & support to point at), and its category picker
    /// pushed there.
    private(set) var showsSettings = false
    private(set) var showsCategories = false
    /// "How do I get my file?" from the import step.
    var showsGuide = false
    private(set) var world: TourWorld?
    @ObservationIgnored private let makeWorld: () async throws -> TourWorld
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "tour")

    init(makeWorld: @escaping () async throws -> TourWorld = { try await TourWorld.make() }) {
        self.makeWorld = makeWorld
    }

    var count: Int { TourStep.allCases.count }

    /// Fills the made-up store, then shows `first` (the welcome; DEBUG screenshots start at any step).
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
            phase = .running
            go(to: first)
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
        if let next = step.next { go(to: next) } else { end() }
    }

    // MARK: what the person does

    /// The tour's dashboard moved (a swipe, Current/Overview, the graph, a category or payment opened, Back). Doing what
    /// the step asks moves on.
    func update(_ new: DashboardPlace) {
        let old = place
        place = new
        guard phase == .running else { return }
        let done: Bool
        switch step {
        case .income: done = new.side == .income && old.side != .income
        case .overview: done = !new.current && old.current
        case .graph: done = new.graph && !old.graph
        case .category: done = new.path.count > old.path.count && new.path.last?.month != nil
        case .payment: done = new.payment != nil && old.payment == nil
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

    /// The Lock rows in the tour's Settings: in the tour they only answer their step (no lock is set).
    func lockTapped() {
        if phase == .running && step == .lock { next() }
    }

    /// Contact & support in the tour's Settings: it only answers its step (no form opens, nothing is sent).
    func contactTapped() {
        if phase == .running && step == .contact { next() }
    }

    /// A payment's category change finished (its sheet closed, the shop question answered).
    func paymentRecategorised() {
        if phase == .running && step == .switchCategory { next() }
    }

    // MARK: where the tour points

    /// The control the current step points at, nil when none (the first and last step; while the person works in a
    /// sheet the step leads to).
    var target: TourTarget? {
        guard phase == .running else { return nil }
        switch step {
        case .welcome, .done: return nil
        case .income: return .pageDots
        case .overview: return .range
        case .graph: return .graph
        case .category: return firstCategory.map { .category($0) }
        case .payment: return firstPayment.map { .payment($0.id) }
        case .switchCategory: return place.payment != nil ? .change : firstPayment.map { .payment($0.id) }
        case .categories: return showsCategories ? nil : showsSettings ? .categoriesRow : .settings
        case .lock: return showsSettings ? .lockRow : .settings
        case .contact: return showsSettings ? .contactRow : .settings
        case .importFiles: return .importButton
        }
    }

    /// The tour points at a control and keeps taps off the rest of the screen, the header's back arrow included. The
    /// back swipe is off meanwhile too, since it does only what the arrow does (brief 38); a swipe the tour lets through
    /// reaches `update` through the dashboard's path, as the arrow does. So is a payment row's long press (brief 41): at
    /// the payment step the row the ring is on opens the payment's page, and a menu there would skip the page the card
    /// points at; the switch step points at the page's Change. While the tour points at nothing (the first and last
    /// step), the menu works as everywhere, on the made-up store.
    var holdsTheScreen: Bool { target != nil && step.holdsTheRest }

    /// The category row the category step points at: the tour's first category when the page shows it, else the
    /// page's first row.
    private var firstCategory: String? {
        guard let dashboard = world?.dashboard else { return nil }
        let rows = dashboard.rows(side: place.side, current: place.current)
        if let preferred = world?.firstCategory, rows.contains(where: { $0.category.name == preferred }) { return preferred }
        return rows.first?.category.name
    }

    /// The first payment of the month list on screen, if one is.
    private var firstPayment: Transaction? {
        guard let dashboard = world?.dashboard, let route = place.path.last, let month = route.month else { return nil }
        return dashboard.transactions(category: route.category, month: month, side: route.side).first?.transaction
    }

    // MARK: getting each step's screen ready

    private func go(to step: TourStep) {
        self.step = step
        prepare(step)
    }

    /// What a step needs on screen, without undoing what the person just did: the step before's action stays (the
    /// income page stays after the swipe, the graph after it was opened).
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
            toStart()
            place.graph = false
        case .category:
            toStart()
            place.current = true
            place.side = .expenses
        case .payment:
            closeSheets()
            openMonthList()
        case .switchCategory:
            closeSheets()
            openMonthList()
            if place.payment == nil { place.payment = firstPayment }
        case .categories:
            // The gear is in every screen's header: the list stays, the payment closes.
            closeSheets()
            place.payment = nil
        case .lock, .contact:
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
    }

    /// A month's payments on screen: kept when one is shown, else this month's of the tour's first category.
    private func openMonthList() {
        guard place.path.last?.month == nil, let dashboard = world?.dashboard else { return }
        place.payment = nil
        place.current = true
        place.side = .expenses
        guard let category = firstCategory, let month = dashboard.currentMonth?.key else { return }
        place.path = [DashboardRoute(category: category, side: .expenses, month: month)]
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
            try await phone.addCustom(named: TourData.customName())
            _ = try await phone.importFiles([TourData.bankFile(now: now)], auth: BackendAuth(token: nil))
            // Its own session, never logged in: the tour asks no server and follows no login.
            let session = EmpireSession(app: .aresium, storage: TourTokens(), restoreOnLaunch: false)
            let widgetFolder = root.appending(path: "widget", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: widgetFolder, withIntermediateDirectories: true)
            let widget = WidgetSnapshotPublisher(store: WidgetSnapshotStore(directory: widgetFolder), reloadTimelines: {})
            let dashboard = DashboardStore(session: session, backend: phone, widgetPublisher: widget)
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
