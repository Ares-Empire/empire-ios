import SwiftUI

/// Ordinary listing cards under the monitor, with the same detail and state actions as every other listing.
struct MonitorMatchesSection: View {
    let id: Int
    let kind: MonitorListingKind
    let store: ArestemisStore
    let open: (Int) -> Void
    let showAll: () -> Void

    var body: some View {
        let matches = store.monitorMatches(kind, hunt: id)
        let list = store.monitorList(kind, hunt: id)
        if matches.isEmpty {
            MonitorListMessage(kind: kind, filter: .all, list: list) { await store.loadMonitorListings(kind, hunt: id, force: true, limit: kind == .alarms ? 3 : ArestemisStore.pageSize) }
        } else {
            VStack(spacing: Look.rowGap) {
                ForEach(matches.prefix(kind == .alarms ? 3 : 5)) { match in
                    Button { open(match.id) } label: {
                        MatchRow(match: match, kind: store.kind(of: match), showsNewDot: store.showsNewDot(match),
                                 showsState: true, alarmShop: store.alarmShop(of: match))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { MatchRowActions(match: match, store: store) }
                }
            }
            if kind == .alarms || matches.count > 5 || list.more {
                Button(action: showAll) {
                    HStack(spacing: 5) {
                        Text("Show all")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(kind == .used ? "usedAll" : "alarmsAll")
            }
            if let error = list.error {
                CalmMessage(text: error, action: (String(localized: "Try again"), {
                    Task { await store.loadMonitorListings(kind, hunt: id, force: true, limit: kind == .alarms ? 3 : ArestemisStore.pageSize) }
                }))
            }
        }
    }
}

struct MonitorListingsPage: View {
    let id: Int
    let kind: MonitorListingKind
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    @State private var filter: MatchFilter = .all

    var body: some View {
        Group {
            if let card = store.card(id), kind.supports(card.hunt.search.price) {
                let list = store.monitorList(kind, hunt: id, filter: filter)
                VStack(spacing: 0) {
                    Picker("Show", selection: $filter) {
                        ForEach([MatchFilter.new, .saved, .all]) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, Look.side).padding(.top, 6).padding(.bottom, 2)
                    List {
                        let matches = store.monitorMatches(kind, hunt: id, filter: filter)
                        if matches.isEmpty {
                            MonitorListMessage(kind: kind, filter: filter, list: list) {
                                await store.loadMonitorListings(kind, hunt: id, filter: filter, force: true)
                            }
                            .padding(.top, 40).plainRow()
                        } else {
                            ForEach(matches) { match in
                                ListingRow(match: match, store: store, showsState: filter == .all) {
                                    navigation.huntPath.append(.match(match.id))
                                }
                            }
                        }
                        if list.more {
                            MoreRow(error: list.error, last: list.ids.last) {
                                await store.loadMonitorListings(kind, hunt: id, filter: filter, more: true)
                            }
                        } else if !matches.isEmpty, let error = list.error {
                            CalmMessage(text: error, action: (String(localized: "Try again"), {
                                Task { await store.loadMonitorListings(kind, hunt: id, filter: filter, force: true) }
                            })).plainRow()
                        }
                    }
                    .listingsList()
                    .refreshable { await store.loadMonitorListings(kind, hunt: id, filter: filter, force: true) }
                }
                .task(id: PageRead(read: MonitorListingsRead(card), filter: filter, kind: kind)) {
                    await store.loadMonitorListings(kind, hunt: id, filter: filter)
                }
            } else {
                CalmMessage(text: String(localized: "This search is gone.")).frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity).provinceWall()
        .navigationTitle(kind.title).navigationBarTitleDisplayMode(.inline)
        .onAppear {
            #if DEBUG
            if store.isSample, let asked = LaunchArguments.value(kind == .used ? "-usedFilter" : "-alarmsFilter").flatMap(MatchFilter.init(rawValue:)),
               asked != .applied { filter = asked }
            #endif
        }
    }

    private struct PageRead: Equatable {
        let read: MonitorListingsRead
        let filter: MatchFilter
        let kind: MonitorListingKind
    }
}

private struct MonitorListMessage: View {
    let kind: MonitorListingKind
    let filter: MatchFilter
    let list: ArestemisStore.MatchList
    let retry: () async -> Void

    var body: some View {
        if let error = list.error {
            CalmMessage(text: error, action: (String(localized: "Try again"), { Task { await retry() } }))
        } else if !list.loaded {
            CalmMessage(text: String(localized: "Loading listings…"), loading: true)
        } else {
            CalmMessage(text: empty)
        }
    }

    private var empty: String {
        if kind == .alarms, filter == .all {
            return String(localized: "No alarm yet. It comes as a push the moment it rings.")
        }
        return switch filter {
        case .new: String(localized: "Nothing new. New listings appear here the moment they're found.")
        case .saved: String(localized: "Nothing saved. Swipe right on a listing to keep it here.")
        case .all, .applied: String(localized: "No listings yet. They appear here the moment they're found.")
        }
    }
}
