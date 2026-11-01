import SwiftUI
import UIKit

/// The signed-in app: two tabs, Aresus (the watchtower) and Aresync (sync runs), and the run sheet over both.
/// What is on screen refreshes every minute while the app is open (`AresusStore.interval`).
struct AresusTabs: View {
    let store: AresusStore
    let drops: DropsStore
    @Bindable var navigation: AresusNavigation
    let marks: [String: UIImage]
    let logOut: () -> Void
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $navigation.tab) {
            Tab("Aresus", systemImage: "binoculars", value: AresusNavigation.Tab.aresus) {
                WatchtowerTab(store: store, navigation: navigation, marks: marks)
                    .tint(Ink.primary)
            }
            Tab("Aresync", systemImage: "arrow.triangle.2.circlepath", value: AresusNavigation.Tab.aresync) {
                SyncScreen(store: store, drops: drops, open: { navigation.openRun = RunRef(id: $0) },
                           openSettings: { navigation.showsSettings = true })
                    .tint(Ink.primary)
            }
        }
        .tint(AppAccent.aresus.color)
        .sheet(isPresented: $navigation.showsSettings) {
            SettingsScreen(app: SettingsApp(name: "Aresus", accent: .aresus, sendsNotifications: true),
                           session: store.session, sample: store.isSample, logOut: logOut)
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

    private struct Refresh: Equatable {
        let parts: [AresusStore.Part]
        let active: Bool
    }
}
