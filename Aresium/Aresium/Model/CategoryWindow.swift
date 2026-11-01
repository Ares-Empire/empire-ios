import Foundation
import Observation

// The change window (`RecategoriseSheet`) for one payment and for a selection of a category's month list (brief 82): one
// view that reads `CategoryWindow`. What is picked in it (Switch's category, Add's extras, a category made here or picked
// from the other side) and what the grid's tiles do is one piece both share (`CategoryPicks` and the protocol's
// extension below); what Save does and asks is each one's own (`TransactionDetailStore`, `SelectionCategoryChange`).

/// What the change window shows above its grid: the payment's name, or "10 payments" with their total (brief 82), and
/// the category they are in now with, for one payment, why it is there.
struct CategoryWindowHeading {
    let title: String
    /// A selection's total, signed and in its side's colour as a payment's amount shows; nil for one payment.
    var amount: Double?
    /// The category the payment is in now (the dashboard's name); nil: none to show.
    let current: String?
    let currentColor: String
    /// Why one payment is in its category (brief 47); nil for a selection.
    var reason: String?
    /// The window is for several payments: its lines speak of them ("they move there").
    var selection = false
}

/// What the change window reads and does. One payment (`TransactionDetailStore`) or a selection
/// (`SelectionCategoryChange`); the picking and the grid's tiles are shared (`CategoryPicks`, the extension below).
@MainActor
protocol CategoryWindow: AnyObject, Observable {
    /// What is picked, and the categories made or picked from the other side in this opening.
    var picks: CategoryPicks { get }
    var dashboardStore: DashboardStore { get }
    /// The heading; nil while one payment loads (`loadError` then says why it could not).
    var heading: CategoryWindowHeading? { get }
    var loadError: String? { get }
    func retryLoad() async
    /// The categories offered in the grid before the picking adds its own (one made here, one from the other side).
    var offered: [Category] { get }
    /// The side the payments are on: money in is income's, money out spending's. Nil while one payment loads.
    var paymentSide: CategorySide? { get }
    /// The category the payments are in now: its tile says "current" and is never added to itself; nil: none.
    var currentCategory: String? { get }
    var isSample: Bool { get }
    var isSaving: Bool { get }
    var saveError: String? { get }
    var canSave: Bool { get }
    func save() async
    func retrySave() async
    /// The question Save asks now, in one alert: remove from the current category, or the shop's other payments.
    var question: RecategorisationQuestion? { get }
    func answerRemoveCurrent(remove: Bool) async
    /// The answer to the shop's other payments, taken at once (a dismissal that follows answers nothing twice).
    func answer(moveOthers: Bool)
    /// A change the grid makes at once (taking back an offer from the other side): busy meanwhile, its error shown.
    func working(_ work: () async throws -> Void) async
}

/// What is picked in the change window, for one payment or a selection: Switch's category, Add's extras (in the order
/// they were picked: with Remove the first becomes the primary), the categories made in this opening (shown last, just
/// before New category, brief 60) and those picked from the other side (brief 70: Save stores them as offered here).
@MainActor @Observable
final class CategoryPicks {
    var mode = RecategorisationMode.switchCategory
    private(set) var target: String?
    // Keep insertion order: with dropCurrent, the server promotes categories[0].
    private(set) var extras: [String] = []
    /// The New category alert, its busy state and its name problem (shared with the receipt window and Add cash).
    let newCategory = NewCategoryModel()
    /// The names made or picked from the other side in this opening, in their insertion order.
    private(set) var madeHere: [String] = []
    private(set) var pickedOtherSide: Set<String> = []
    /// Phone mode: the person's categories (their sides and offers); nil in server mode or before they are read.
    var list: PhoneCategoryList?

    /// The window opens: nothing picked but the extras the payment has, nothing made, no alert.
    func begin(mode: RecategorisationMode, extras: [String]) {
        self.mode = mode
        target = nil
        self.extras = extras
        madeHere = []
        pickedOtherSide = []
        newCategory.reset()
    }

    /// The grid's categories: those offered, with the ones made or picked here last (they may not be offered yet).
    func ordered(_ offered: [Category], in dashboard: Dashboard?) -> [Category] {
        guard !madeHere.isEmpty else { return offered }
        let made = madeHere.compactMap { name in dashboard?.categories.first { $0.name == name } }
        return offered.filter { !madeHere.contains($0.name) } + made
    }

    /// Switch: the category. Add: an extra on or off (never the current category).
    func toggle(_ name: String, current: String?) {
        if mode == .switchCategory { target = name }
        else if name != current {
            if extras.contains(name) { extras.removeAll { $0 == name } }
            else { extras.append(name) }
        }
    }

    func isPicked(_ name: String) -> Bool { mode == .switchCategory ? target == name : extras.contains(name) }

    /// A category made here, or picked from the other side: shown last in the grid.
    func cameHere(_ name: String, fromOtherSide: Bool = false) {
        if fromOtherSide { pickedOtherSide.insert(name) }
        if !madeHere.contains(name) { madeHere.append(name) }
    }

    /// A category taken back: it leaves the window and is picked no more.
    func forget(_ name: String) {
        pickedOtherSide.remove(name)
        madeHere.removeAll { $0 == name }
        if target == name { target = nil }
        extras.removeAll { $0 == name }
    }

    /// What Save keeps: Switch's category, or Add's extras.
    var savedNames: [String] { mode == .switchCategory ? target.map { [$0] } ?? [] : extras }

    /// Save: the categories picked from the other side and kept are offered on this side from now on (brief 69).
    func storeOtherSides(in phone: PhoneBackend) async throws {
        let list = try await phone.categories()
        for name in savedNames where pickedOtherSide.contains(name) {
            guard let id = list.id(named: name) else { throw LedgerError.notFound }
            try await phone.setOtherSide(true, for: id)
        }
        self.list = try await phone.categories()
    }
}

extension CategoryWindow {
    var mode: RecategorisationMode {
        get { picks.mode }
        set { picks.mode = newValue }
    }
    var target: String? { picks.target }
    var extras: [String] { picks.extras }
    var newCategory: NewCategoryModel { picks.newCategory }

    /// The change window's categories. One made in this opening of the window comes last, just before the New category
    /// tile where it was asked for (brief 60), so it shows picked where the person looks.
    var choices: [Category] { picks.ordered(offered, in: dashboardStore.dashboard) }

    func isPicked(_ name: String) -> Bool { picks.isPicked(name) }

    /// A tap on a category tile.
    func select(_ name: String) {
        guard !isSaving, choices.contains(where: { $0.name == name }) else { return }
        picks.toggle(name, current: currentCategory)
    }

    /// Phone mode offers a new category for either direction, with the payments' side.
    var offersNewCategory: Bool { paymentSide != nil && dashboardStore.phone != nil }

    /// Other home categories not offered here yet, in the engine's order for their home direction.
    var otherSideChoices: [Category] {
        guard let side = paymentSide, let list = picks.list, dashboardStore.phone != nil else { return [] }
        let offered = Set(list.offered(for: side.direction))
        return (dashboardStore.dashboard?.recategorisationChoices(amount: side == .income ? -1 : 1) ?? []).filter {
            guard let id = list.id(named: $0.name) else { return false }
            return list.side(of: id) != nil && list.side(of: id) != side && !offered.contains(id)
                && !picks.pickedOtherSide.contains($0.name)
        }
    }

    /// Other category… (brief 70): the tile before New category, in Switch and Add, phone mode only, while the other
    /// side has a category not offered here yet.
    var offersOtherCategory: Bool { offersNewCategory && !otherSideChoices.isEmpty }

    /// The other side's list's line ("From spending" for money in); nil where there is no list.
    var otherSideListLine: String? {
        guard offersOtherCategory, let paymentSide else { return nil }
        return CategorySideWording.otherSideList(for: paymentSide)
    }

    /// A tile offered here only from the other side: one stored as offered here (not the current category), or one
    /// picked from the list in this opening. Its long press takes it back (`stopOffering`).
    func offeredFromOtherSide(_ name: String) -> Bool {
        guard let side = paymentSide, let list = picks.list, dashboardStore.phone != nil, name != currentCategory
        else { return false }
        if picks.pickedOtherSide.contains(name) { return true }
        guard let id = list.id(named: name), let home = list.side(of: id) else { return false }
        return home != side && list.hasOtherSide(id)
    }

    /// The long press's one entry on such a tile: "Not for money in" (or out); nil on every other tile.
    func stopOfferingEntry(for name: String) -> String? {
        guard offeredFromOtherSide(name), let paymentSide else { return nil }
        return CategorySideWording.notFor(paymentSide)
    }

    /// Picks locally; Save widens the category's menu, and Cancel has no stored effect.
    func pickFromOtherSide(_ name: String) {
        guard !isSaving, !newCategory.isMaking, otherSideChoices.contains(where: { $0.name == name }) else { return }
        picks.cameHere(name, fromOtherSide: true)
        select(name)
    }

    /// Removes an addition to this direction at once. A home category and the current category stay offered. One picked
    /// from the other side in this opening was never stored: it only leaves the window (and the list has it again).
    func stopOffering(_ name: String) async {
        if picks.pickedOtherSide.contains(name), !isSaving, !newCategory.isMaking {
            picks.forget(name)
            return
        }
        guard !isSaving, !newCategory.isMaking, let side = paymentSide, let phone = dashboardStore.phone,
              let list = picks.list, let id = list.id(named: name), list.hasOtherSide(id),
              let home = list.side(of: id), home != side, name != currentCategory else { return }
        await working {
            try await phone.setOtherSide(false, for: id)
            picks.list = try await phone.categories()
            picks.forget(name)
            await dashboardStore.reloadIfCategoriesChanged()
        }
    }

    /// The tile: the alert with the name's field (empty, or the name a problem was found in).
    func beginNewCategory() {
        guard offersNewCategory, !isSaving else { return }
        newCategory.begin()
    }

    /// The alert's Create (or the keyboard's Return): the category is made (`NewCategoryModel`), the dashboard is built
    /// again so the window's choices have it, and it is picked: the target in Switch, one of the extras in Add. Nothing
    /// about the payments is saved before Save. Returns the name picked, nil when none was (the quick sort, brief 99,
    /// sorts its card into it at once).
    @discardableResult
    func createCategory() async -> String? {
        guard offersNewCategory, let phone = dashboardStore.phone, let side = paymentSide, !isSaving else { return nil }
        var picked: String?
        await newCategory.create(in: phone, side: side) { _, name in
            picks.cameHere(name)
            picks.list = try? await phone.categories()
            await dashboardStore.reloadAfterTransactionChange()
            // Not offered only when the dashboard could not be built again: the category is made (Settings →
            // Categories shows it), but the window cannot offer it yet.
            guard choices.contains(where: { $0.name == name }) else { return dashboardStore.error }
            if mode == .switchCategory || !extras.contains(name) { select(name) }
            picked = name
            return nil
        }
        return picked
    }
}

/// The change window's words that differ between one payment and several (brief 82), in the app's language.
nonisolated enum CategoryWindowWording {
    /// The line under Switch and Add: what the mode does.
    static func modeLine(_ mode: RecategorisationMode, current: String?, selection: Bool,
                         language: AppLanguage = .current) -> String {
        switch (mode, selection) {
        case (.switchCategory, false): language.string("Wrong category? Pick the one it belongs in — it moves there.")
        case (.switchCategory, true): language.string("Wrong category? Pick the one they belong in — they move there.")
        case (.add, false):
            language.string("Also show this under other categories. It stays counted once (in \(CategoryName.shown(current ?? "", language: language))), so nothing is double-counted.")
        case (.add, true):
            language.string("Also show these under other categories. Each stays counted once, so nothing is double-counted.")
        }
    }
}
