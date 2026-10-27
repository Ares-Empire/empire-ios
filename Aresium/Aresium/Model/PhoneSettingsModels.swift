import Foundation
import Observation
import os

/// The category picker (after an import while no category is chosen, Settings → Categories, the tour's Settings): the
/// default list by group with a toggle each, a field for one's own names; nothing is ticked at first (Patrik,
/// 2026-10-26). Each row carries how many payments its category has, or would get if ticked (`counts`). Unticking a
/// category with payments asks where they go. Every change is saved at once, the numbers counted again and the
/// dashboard rebuilt.
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
    private(set) var problem: String?
    private(set) var isWorking = false
    private(set) var untick: Untick?
    /// Category id → payments (`PhoneBackend.categoryCounts`): in it now, or for a default one not ticked, how many it
    /// would get. Counted at the start and after every change.
    private(set) var counts: [String: Int] = [:]
    @ObservationIgnored let phone: PhoneBackend
    /// After every change: the dashboard is built again.
    @ObservationIgnored private let changed: () async -> Void

    init(phone: PhoneBackend, changed: @escaping () async -> Void) {
        self.phone = phone
        self.changed = changed
    }

    var groups: [CategoryGroup] { list?.groups ?? [] }
    var custom: [CategoryGroup.Item] { list?.custom ?? [] }
    var chosenCount: Int { list?.chosen.count ?? 0 }

    /// The number a row shows; nil at 0 (and so while there are no payments).
    func count(of id: String) -> Int? {
        counts[id].flatMap { $0 > 0 ? $0 : nil }
    }

    /// Some row shows a number: the picker says what the numbers mean.
    var showsCounts: Bool {
        (groups.flatMap(\.items) + custom).contains { count(of: $0.id) != nil }
    }

    func load() async {
        do { list = try await phone.categories() }
        catch { problem = error.localizedDescription }
        await loadCounts()
    }

    /// The numbers help to choose but are not needed for it: when they cannot be counted, none show (never old ones).
    private func loadCounts() async {
        do { counts = try await phone.categoryCounts() }
        catch {
            counts = [:]
            Self.log.error("the picker's numbers were not counted: \(String(describing: error), privacy: .public)")
        }
    }

    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "categories")

    /// Ticks or unticks a category. Unticking one with payments asks first (`untick`).
    func toggle(_ id: String) async {
        guard !isWorking, let list else { return }
        problem = nil
        if !list.isChosen(id) {
            await work { try await self.phone.choose(id) }
            return
        }
        do {
            let count = try await phone.paymentCount(in: id)
            if count == 0 {
                await work { try await self.phone.unchoose(id, moveTo: nil) }
            } else {
                let targets = list.chosen.filter { $0.id != id }.compactMap { chosen in
                    list.name(of: chosen.id).map { Untick.Target(id: chosen.id, name: $0, look: list.look(of: chosen.id)) }
                }
                untick = Untick(id: id, name: list.name(of: id) ?? id, look: list.look(of: id), count: count,
                                targets: targets, notSortedName: list.notSortedName,
                                notSortedLook: list.look(of: CategoryCatalog.notSorted))
            }
        } catch { problem = error.localizedDescription }
    }

    /// The answer from the dialog: taken at once (so the dialog's dismissal that follows finds nothing to cancel), then
    /// carried out.
    func resolve(moveTo target: String?) {
        guard let untick else { return }
        self.untick = nil
        Task { await work { try await self.phone.unchoose(untick.id, moveTo: target) } }
    }

    /// The answer to "where do its payments go?": another category, or nil for Not sorted.
    func resolveUntick(moveTo target: String?) async {
        guard let untick else { return }
        self.untick = nil
        await work { try await self.phone.unchoose(untick.id, moveTo: target) }
    }

    func cancelUntick() { untick = nil }

    /// Adds one's own category from the field (ticked).
    func addCustom() async {
        guard !isWorking else { return }
        problem = nil
        let typed = newName
        await work {
            try await self.phone.addCustom(named: typed)
            self.newName = ""
        }
    }

    private func work(_ action: @escaping () async throws -> Void) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await action()
            list = try await phone.categories()
            await loadCounts()
            await changed()
        } catch { problem = error.localizedDescription }
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
