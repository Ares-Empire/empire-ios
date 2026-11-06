import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The signed-in app: Aresus (the watchtower), Aresync (drops and sync runs), For you (the board), and Settings
/// and the send sheet over both.
/// What is on screen refreshes every minute while the app is open (`AresusStore.interval`).
struct AresusTabs: View {
    let store: AresusStore
    let drops: DropsStore
    @Bindable var board: BoardStore
    @Bindable var navigation: AresusNavigation
    let marks: [String: UIImage]
    let logOut: () -> Void
    @State private var droppedFiles: [DropFile] = []
    @State private var droppedUnreadable = 0
    @State private var hovering: ProviderFiles.Hover?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Files dropped on either tab go to the send sheet (brief 100; dropping has no other meaning in Aresus): the hover
    /// over the tab while they hover, the tab bar left free; letting go opens the send sheet with them.
    private func takingDrops(_ content: some View) -> some View {
        content
            .overlay {
                if let hovering, !navigation.showsSend { DropHoverScreen(hover: hovering).transition(.opacity) }
            }
            .onDrop(of: [.item], delegate: ProviderDropTarget(enabled: !navigation.showsSend,
                type: { $0.types.first }, copy: copyDropped, hovering: $hovering, reduceMotion: reduceMotion,
                dropped: { urls, failed in
                    droppedUnreadable = failed
                    droppedFiles = urls.map { DropFile(content: .file($0), suggestedName: $0.lastPathComponent) }
                    if !droppedFiles.isEmpty { navigation.showsSend = true }
                }))
    }

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Aresus", systemImage: "binoculars", value: AresusNavigation.Tab.aresus) {
                takingDrops(WatchtowerTab(store: store, navigation: navigation, marks: marks)
                    .tint(Ink.primary))
            }
            Tab("Aresync", systemImage: "arrow.triangle.2.circlepath", value: AresusNavigation.Tab.aresync) {
                takingDrops(NavigationStack(path: $navigation.syncPath) {
                    SyncScreen(store: store, drops: drops, open: { navigation.openRun = RunRef(id: $0) },
                               openSettings: { navigation.showsSettings = true },
                               openSend: { navigation.showsSend = true },
                               showAllDrops: { navigation.syncPath.append(.drops) })
                        .navigationDestination(for: SyncRoute.self) { route in
                            switch route {
                            case .drops: DropsListScreen(drops: drops)
                            }
                        }
                }
                .tint(Ink.primary))
            }
            Tab("For you", systemImage: "tray", value: AresusNavigation.Tab.board) {
                takingDrops(NavigationStack {
                    BoardScreen(board: board, openSettings: { navigation.showsSettings = true })
                }.tint(Ink.primary).undoBar($board.undoOffer, accent: .aresus))
            }
            .badge(board.badgeCount)
        }
        .onChange(of: navigation.tab) { old, new in
            if old == .board, new != .board { Task { await board.commitPending() } }
        }
        .task { await board.refresh(olderThan: AresusStore.interval) }
        .tint(AppAccent.aresus.color)
        .sheet(isPresented: $navigation.showsSettings) {
            SettingsScreen(app: SettingsApp(name: "Aresus", accent: .aresus, sendsNotifications: true),
                           session: store.session, sample: store.isSample, logOut: logOut)
        }
        // The copies of picked photos go with the sheet; what was sent has its own copy in the outbox.
        .sheet(isPresented: $navigation.showsSend, onDismiss: { SendTemporaryFiles().clear(); droppedFiles = []; droppedUnreadable = 0 }) {
            SendSheet(drops: drops, files: droppedFiles, unreadable: droppedUnreadable)
        }
        .sheet(item: $navigation.openRun) { run in
            RunSheet(id: run.id, store: store)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationBackground { ProvinceWall(accent: .aresus) }
                .tint(Ink.primary)
        }
        #if DEBUG
        .task { showsHoverFromLaunchArgument() }
        #endif
        .task(id: Refresh(parts: navigation.visibleParts, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            let parts = navigation.visibleParts
            if navigation.tab == .board { await board.refresh(olderThan: AresusStore.interval) }
            await store.refresh(parts, olderThan: AresusStore.interval)
            if navigation.tab == .aresync { await drops.refresh(olderThan: AresusStore.interval) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AresusStore.interval))
                guard !Task.isCancelled else { return }
                await store.refresh(parts)
                if navigation.tab == .board { await board.refresh() }
                if navigation.tab == .aresync { await drops.refresh() }
            }
        }
    }

    private func copyDropped(_ providers: [NSItemProvider], done: @escaping @MainActor ([URL], Int) -> Void) {
        // The draft owns these copies until Send has copied them into the durable queue.
        ProviderFiles.copyTaken(providers, into: SendTemporaryFiles().base,
                                type: { $0.types.first },
                                name: { ShareItems.name(suggested: $1, loaded: $0, type: $2) }, done: done)
    }

    #if DEBUG
    /// Screenshots (with `-sampleData -tab aresync`): `-sampleDropHover <count or name>` shows the hover as if that many
    /// files, or one so named, were held over the tab (the simulator's drop needs two fingers).
    private func showsHoverFromLaunchArgument() {
        guard store.isSample, let value = LaunchArguments.value("-sampleDropHover") else { return }
        hovering = Int(value).map { ProviderFiles.Hover(count: $0, name: nil) } ?? ProviderFiles.Hover(count: 1, name: value)
    }
    #endif

    private struct Refresh: Equatable {
        let parts: [AresusStore.Part]
        let active: Bool
    }
}
