import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// The signed-in app: two tabs, Aresus (the watchtower) and Aresync (drops and sync runs), and the run sheet, Settings
/// and the send sheet over both.
/// What is on screen refreshes every minute while the app is open (`AresusStore.interval`).
struct AresusTabs: View {
    let store: AresusStore
    let drops: DropsStore
    @Bindable var navigation: AresusNavigation
    let marks: [String: UIImage]
    let logOut: () -> Void
    @State private var droppedFiles: [DropFile] = []
    @State private var droppedUnreadable = 0
    @State private var hovering: ProviderFiles.Hover?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Aresus", systemImage: "binoculars", value: AresusNavigation.Tab.aresus) {
                WatchtowerTab(store: store, navigation: navigation, marks: marks)
                    .tint(Ink.primary)
            }
            Tab("Aresync", systemImage: "arrow.triangle.2.circlepath", value: AresusNavigation.Tab.aresync) {
                NavigationStack(path: $navigation.syncPath) {
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
                .tint(Ink.primary)
                .onDrop(of: [.item], delegate: ProviderDropTarget(enabled: !navigation.showsSend,
                    type: { $0.types.first }, copy: copyDropped, hovering: $hovering, reduceMotion: true,
                    dropped: { urls, failed in
                        droppedUnreadable = failed
                        droppedFiles = urls.map { DropFile(content: .file($0), suggestedName: $0.lastPathComponent) }
                        if !droppedFiles.isEmpty { navigation.showsSend = true }
                    }))
            }
        }
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
        .task(id: Refresh(parts: navigation.visibleParts, active: scenePhase == .active)) {
            guard scenePhase == .active else { return }
            let parts = navigation.visibleParts
            await store.refresh(parts, olderThan: AresusStore.interval)
            if navigation.tab == .aresync { await drops.refresh(olderThan: AresusStore.interval) }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(AresusStore.interval))
                guard !Task.isCancelled else { return }
                await store.refresh(parts)
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

    private struct Refresh: Equatable {
        let parts: [AresusStore.Part]
        let active: Bool
    }
}
