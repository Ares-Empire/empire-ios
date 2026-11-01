import Foundation
import Observation

/// New category where a category is chosen (brief 60): the change window's last tile, and the last item of the receipt
/// window's and Add cash's category menu. One piece for the three places: the alert's name (kept after a name problem, so
/// the next tap shows it to correct), whether the alert shows, the busy state while the category is made, and the name
/// problem's line. The category is made as Settings → Categories makes it (`PhoneBackend.useCategory(named:side:sorting:)`: the name
/// check, its icon and colour, ticked); the window it was asked from then offers it and picks it (`create(in:side:offer:)`).
/// The look is `Screens/NewCategoryPieces.swift` (the alert; the menus' row) and the change window's tile.
@MainActor @Observable
final class NewCategoryModel {
    /// The name typed into the alert.
    var name = ""
    /// The alert with the name's field is shown.
    var isAsking = false
    /// Why the typed name made no category, in Settings → Categories' words (`LedgerError`).
    private(set) var problem: String?
    /// The category is being made: the place that asked shows the busy sign.
    private(set) var isMaking = false

    /// Create is on once the name is more than spaces.
    var canCreate: Bool { !isMaking && !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The tile or the menu item: the alert, with the field empty or holding the name a problem was found in.
    func begin() {
        guard !isMaking else { return }
        isAsking = true
    }

    /// The alert's Cancel: no category; the typed name and its problem go.
    func cancel() {
        name = ""
        problem = nil
    }

    /// The window opens again: nothing typed, no problem, no alert.
    func reset() {
        cancel()
        isAsking = false
    }

    /// Create (or the keyboard's Return): the category is made from the typed name, then `offer` puts it among the
    /// window's choices and picks it, given its id and its name as the windows show it; `offer` answers why it could not,
    /// or nil. A name problem (empty, built-in or reserved) makes nothing and keeps the typed name.
    func create(in phone: PhoneBackend, side: CategorySide, offer: (_ id: String, _ name: String) async -> String?) async {
        guard !isMaking else { return }
        let typed = name
        isMaking = true
        problem = nil
        defer { isMaking = false }
        do {
            #if DEBUG
            await DebugLaunch.holdWork()
            #endif
            let result = try await phone.useCategory(named: typed, side: side)
            let id = result.id
            name = ""
            let shown = try await phone.categories().name(of: id) ?? typed.trimmingCharacters(in: .whitespacesAndNewlines)
            problem = await offer(id, shown)
        } catch {
            problem = error.localizedDescription
        }
    }
}

#if DEBUG
extension NewCategoryModel {
    /// Screenshots (brief 60), in any window that offers New category: `-newCategory` opens the alert,
    /// `-newCategoryName <text>` types a name in it, `-newCategoryCreate` then taps Create (the category made and picked,
    /// or the name problem's line; `-holdWork` keeps it busy). `begin` is the window's tile or menu item, `create` its
    /// Create. True when Create was tapped.
    func debugLaunch(begin: () -> Void, create: () async -> Void) async -> Bool {
        let arguments = LaunchArguments.current
        let typed = LaunchArguments.value("-newCategoryName")
        guard arguments.contains("-newCategory") || typed != nil else { return false }
        // After the window has come up: an alert asked for while it still slides in is not shown.
        try? await Task.sleep(for: .milliseconds(900))
        if let typed { name = typed }
        begin()
        guard arguments.contains("-newCategoryCreate") else { return false }
        try? await Task.sleep(for: .milliseconds(900))
        isAsking = false
        await create()
        return true
    }
}
#endif
