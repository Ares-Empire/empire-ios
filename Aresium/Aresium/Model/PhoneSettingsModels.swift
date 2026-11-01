import Foundation
import Observation
import os

/// The category picker (after an import while no category is chosen, Settings → Categories, the tour's Settings): the
/// default list by group with a toggle each, a field for one's own names; nothing is ticked at first (Patrik,
/// 2026-10-26). Each row carries how many payments its category has, or would get if ticked (`counts`). Unticking a
/// category with payments asks where they go. Choices are saved per tap; sorting and counts wait until taps stop.
/// The dashboard is refreshed when the picker closes, before returning to it.
@MainActor @Observable
final class CategoryPickerModel {
    /// Unticking a category that has payments: where they go (another ticked category, or Not sorted).
    struct Untick: Identifiable, Equatable {
        struct Target: Identifiable, Equatable {
            let id: String
            let name: String
            let look: CategoryLook
        }
        let id: String
        let name: String
        let look: CategoryLook
        let count: Int
        let targets: [Target]
        let notSortedName: String
        let notSortedLook: CategoryLook
    }

    private(set) var list: PhoneCategoryList?
    var newName = ""
    /// The add row's side (brief 70): spending first; kept while the picker is open, so several of one side go quickly.
    var newSide = CategorySide.spend
    private(set) var problem: String?
    private(set) var isWorking = false
    private(set) var untick: Untick?
    /// Category id → payments (`PhoneBackend.categoryCounts`): in it now, or for a default one not ticked, how many it
    /// would get. Counted at the start and after every change.
    private(set) var counts: [String: Int] = [:]
    @ObservationIgnored private var workTail: Task<Bool, Never>?
    @ObservationIgnored private var debounce: Task<Void, Never>?
    @ObservationIgnored private var pendingSort = false
    @ObservationIgnored private var pendingDashboard = false
    @ObservationIgnored private var workCount = 0
    @ObservationIgnored let phone: PhoneBackend
    /// At closing, after all changes: the dashboard is built again before it is shown.
    @ObservationIgnored private let changed: () async -> Void
    /// How long the taps must stop before the sort runs. Tests that check the batching pass a long one and flush
    /// themselves, so a busy machine never decides the result.
    @ObservationIgnored private let settle: Duration

    init(phone: PhoneBackend, settle: Duration = .milliseconds(500), changed: @escaping () async -> Void) {
        self.phone = phone
        self.settle = settle
        self.changed = changed
    }

    var groups: [CategoryGroup] { PickerTiming.measure("picker.groups") { list?.groups ?? [] } }
    var custom: [CategoryGroup.Item] { list?.custom ?? [] }
    var chosenCount: Int { list?.chosen.count ?? 0 }

    /// The number a row shows; nil at 0 (and so while there are no payments).
    func count(of id: String) -> Int? {
        counts[id].flatMap { $0 > 0 ? $0 : nil }
    }

    /// Some row shows a number: the picker says what the numbers mean.
    var showsCounts: Bool {
        PickerTiming.measure("picker.showsCounts") { (groups.flatMap(\.items) + custom).contains { count(of: $0.id) != nil } }
    }

    func load() async {
        do { publishList(try await phone.categories()) }
        catch { problem = error.localizedDescription }
        await loadCounts()
    }

    /// The numbers help to choose but are not needed for it: when they cannot be counted, none show (never old ones).
    private func loadCounts() async {
        let interval = PickerTiming.begin("loadCounts")
        defer { interval.end() }
        do {
            let value = try await phone.categoryCounts()
            PickerTiming.measure("counts.publish") { if counts != value { counts = value } }
        }
        catch {
            if !counts.isEmpty { counts = [:] }
            Self.log.error("the picker's numbers were not counted: \(String(describing: error), privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "categories")

    /// Ticks or unticks a category. Unticking one with payments asks first (`untick`).
    func toggle(_ id: String) async {
        let interval = PickerTiming.begin("toggle")
        defer { interval.end() }
        await work {
            guard let list = self.list else { return }
            self.problem = nil
            if !list.isChosen(id) {
                // Update the tick before waiting for storage; queued actions preserve tap order.
                self.list = PhoneCategoryList(catalog: list.catalog,
                    chosen: list.chosen + [ChosenCategory(id: id, order: (list.chosen.map(\.order).max() ?? -1) + 1)])
                try await self.phone.choose(id, sorting: false)
                try await self.selectionChanged()
                return
            }
            // The count must include choices made in the preceding burst.
            try await self.flushPending()
            let count = try await self.phone.paymentCount(in: id)
            if count == 0 {
                try await self.phone.unchoose(id, moveTo: nil, sorting: false)
                try await self.selectionChanged()
            } else {
                let targets = list.chosen.filter { $0.id != id }.compactMap { chosen in
                    list.name(of: chosen.id).map { Untick.Target(id: chosen.id, name: $0, look: list.look(of: chosen.id)) }
                }
                self.untick = Untick(id: id, name: list.name(of: id) ?? id, look: list.look(of: id), count: count,
                                targets: targets, notSortedName: list.notSortedName,
                                notSortedLook: list.look(of: CategoryCatalog.notSorted))
            }
        }
    }

    /// The answer from the dialog: taken at once (so the dialog's dismissal that follows finds nothing to cancel), then
    /// carried out.
    func resolve(moveTo target: String?) {
        guard let untick else { return }
        self.untick = nil
        Task {
            await work {
                try await self.phone.unchoose(untick.id, moveTo: target, sorting: false)
                try await self.selectionChanged()
            }
        }
    }

    /// The answer to "where do its payments go?": another category, or nil for Not sorted.
    func resolveUntick(moveTo target: String?) async {
        guard let untick else { return }
        self.untick = nil
        await work {
            try await self.phone.unchoose(untick.id, moveTo: target, sorting: false)
            try await self.selectionChanged()
        }
    }

    func cancelUntick() { untick = nil }

    /// Adds one's own category from the field (ticked), on the side the add row shows.
    func addCustom() async { await addCustom(side: newSide) }

    /// Adds one's own category from the field (ticked).
    func addCustom(side: CategorySide) async {
        guard !isWorking else { return }
        problem = nil
        let typed = newName
        await work {
            try await self.phone.addCustom(named: typed, side: side)
            self.newName = ""
            try await self.selectionChanged()
        }
    }

    /// One's own category's side line (brief 70): where it is offered. Its payments stay where they are; while it holds
    /// payments of the side it leaves, it stays offered there too (`PhoneBackend.setSide`).
    func setSide(_ side: CategorySide, of id: String) async {
        guard list?.side(of: id) != side else { return }
        await work {
            self.problem = nil
            try await self.phone.setSide(side, of: id)
            try await self.sidesChanged()
        }
    }

    /// "Also for money in" (or out) on a ticked category's row (brief 70): offered for the other direction too, or not.
    func setOtherSide(_ on: Bool, for id: String) async {
        guard let list, list.isChosen(id), !list.isTransfer(id), list.hasOtherSide(id) != on else { return }
        await work {
            self.problem = nil
            try await self.phone.setOtherSide(on, for: id)
            try await self.sidesChanged()
        }
    }

    /// Done and Back await the same queue as taps, including a tap whose save is still under way.
    @discardableResult
    func flush() async -> Bool {
        let interval = PickerTiming.begin("close-or-settle")
        defer { interval.end() }
        debounce?.cancel()
        debounce = nil
        return await work {
            try await self.flushPending()
            if self.pendingDashboard {
                let interval = PickerTiming.begin("changed")
                await self.changed()
                interval.end()
                self.pendingDashboard = false
            }
        }
    }

    private func publishList(_ value: PhoneCategoryList?) {
        PickerTiming.measure("list.publish") { if list != value { list = value } }
    }

    /// A side changed: the rows show it at once and the dashboard is built again when the picker closes. Nothing is
    /// sorted again (a side decides only where a category is offered).
    private func sidesChanged() async throws {
        publishList(try await phone.categories())
        pendingDashboard = true
    }

    private func selectionChanged() async throws {
        let value = try await phone.categories()
        publishList(value)
        pendingSort = true
        pendingDashboard = true
        debounce?.cancel()
        debounce = Task { [weak self] in
            do { try await Task.sleep(for: self?.settle ?? .milliseconds(500)) }
            catch { return }
            guard let self else { return }
            await self.settleSelection()
        }
    }

    /// The settle updates the picker and storage while leaving the covered dashboard alone. Closing uses `flush`.
    @discardableResult
    func settleSelection() async -> Bool {
        let interval = PickerTiming.begin("settled-flush")
        defer { interval.end() }
        return await work { try await self.flushPending() }
    }

    /// Called only inside the serial work queue. A cancelled wait never cancels a sort already in progress.
    private func flushPending() async throws {
        guard pendingSort else { return }
        try await phone.sort()
        try await phone.refresh()
        await loadCounts()
        pendingSort = false
    }

    @discardableResult
    private func work(_ action: @escaping () async throws -> Void) async -> Bool {
        let previous = workTail
        workCount += 1
        if !isWorking { isWorking = true }
        let task = Task { @MainActor in
            _ = await previous?.value
            defer {
                self.workCount -= 1
                let working = self.workCount > 0
                if self.isWorking != working { self.isWorking = working }
            }
            do {
                try await action()
                return true
            } catch {
                self.problem = error.localizedDescription
                self.publishList(try? await self.phone.categories())
                return false
            }
        }
        workTail = task
        return await task.value
    }

}

/// Settings → Aresium in phone mode: export (one JSON file through the share sheet), restore from an export (only into
/// an empty store), and "Delete Aresium data on this iPhone".
@MainActor @Observable
final class PhoneDataModel {
    /// A file ready for the share sheet.
    struct ExportFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private(set) var exportFile: ExportFile?
    private(set) var message: String?
    private(set) var problem: String?
    private(set) var isWorking = false
    @ObservationIgnored private let modes: ModeStore
    @ObservationIgnored private let directory: URL
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "phone-data")

    /// - Parameter directory: where an export waits for the share sheet (a temporary folder; deleted afterwards).
    init(modes: ModeStore,
         directory: URL = FileManager.default.temporaryDirectory.appending(path: "Aresium-export", directoryHint: .isDirectory)) {
        self.modes = modes
        self.directory = directory
    }

    /// The open phone store (a new one after "Delete Aresium data on this iPhone").
    var phone: PhoneBackend? { modes.phone }

    /// Restoring is possible only while the store holds no data.
    var canRestore: Bool { phone?.summary.isEmpty ?? false }

    /// Writes the export (`Aresium-<date>.json`) for the share sheet.
    func export() async {
        guard !isWorking else { return }
        isWorking = true
        problem = nil
        defer { isWorking = false }
        do {
            guard let phone else { throw LedgerError.notFound }
            let export = try await phone.export()
            try? FileManager.default.removeItem(at: directory)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            let url = directory.appending(path: export.fileName)
            try export.encoded().write(to: url, options: [.atomic, .completeFileProtection])
            exportFile = ExportFile(url: url)
        } catch {
            Self.log.error("export failed: \(String(describing: error), privacy: .public)")
            problem = error.localizedDescription
        }
    }

    /// The share sheet closed: the file leaves the app's temporary folder (the person has their copy, or none).
    func exportClosed() {
        exportFile = nil
        try? FileManager.default.removeItem(at: directory)
    }

    /// Restores an export the person picked; nothing changes unless all of it is good.
    func restore(from url: URL) async {
        guard !isWorking else { return }
        isWorking = true
        problem = nil
        message = nil
        defer { isWorking = false }
        do {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url)
            guard let phone else { throw LedgerError.notFound }
            try await phone.restore(data)
            await modes.dashboard.reloadAfterTransactionChange()
            message = String(localized: "Restored: \(phone.summary.payments) payments.")
        } catch {
            problem = error.localizedDescription
        }
    }

    /// Deletes Aresium's data on this iPhone (after the person confirmed); the app starts again with an empty store.
    func deleteAll() async {
        guard !isWorking else { return }
        isWorking = true
        problem = nil
        message = nil
        defer { isWorking = false }
        do { try await modes.deleteLocalData() }
        catch { problem = error.localizedDescription }
    }
}
