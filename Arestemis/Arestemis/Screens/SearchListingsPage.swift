import SwiftUI

/// One search's listings (brief 133), pushed from Searches, a group's heading in New, or the search's page on the Hunts
/// tab (Listings and its figures): the search's name as the title, the magnifying glass searching only its listings,
/// then New · Saved · Applied · All ("Asked" for a thing's seller; a watch's changes are only saved, so it has no
/// Applied) and the list, as glass cards: swipe right to save, left to dismiss, tap for the match. At the end, the
/// listings the AI filtered out of this search.
struct SearchListingsPage: View {
    let id: Int
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation

    var body: some View {
        Group {
            if let card = store.card(id) {
                page(card)
            } else {
                CalmMessage(text: String(localized: "This search is gone.")).frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .provinceWall()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func page(_ card: HuntCard) -> some View {
        let text = HuntText(card, sites: store.siteNames)
        let filters = MatchFilter.choices(for: text.kind)
        let filter = filters.contains(navigation.filter) ? navigation.filter : .all
        let list = store.list(filter, hunt: id)
        return VStack(spacing: 0) {
            Picker("Show", selection: Binding(get: { filter }, set: { navigation.filter = $0 })) {
                ForEach(filters) { Text($0.title(asked: text.kind == .item)).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Look.side).padding(.top, 6).padding(.bottom, 2)
            List {
                content(filter, list: list, kind: text.kind)
            }
            .listingsList()
            .refreshable {
                async let matches: Void = store.loadMatches(filter, hunt: id)
                async let rejected: Void = store.loadRejected(hunt: id)
                async let overview: Void = store.reloadOverview(quiet: true)
                _ = await (matches, rejected, overview)
            }
        }
        .navigationTitle(text.title)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigation.find(hunt: id) } label: { Image(systemName: "magnifyingglass") }
                    .tint(Ink.primary)
                    .accessibilityLabel("Search listings")
            }
        }
        // Asked when the filter shows first, and again whenever the list was forgotten; never in a loop after a failure.
        .task(id: ListKey(filter: filter, loaded: list.loaded)) {
            if !store.list(filter, hunt: id).loaded { await store.loadMatches(filter, hunt: id) }
        }
        .task(id: store.rejected(hunt: id).loaded) {
            let rejected = store.rejected(hunt: id)
            if !rejected.loaded && rejected.error == nil { await store.loadRejected(hunt: id) }
        }
    }

    private struct ListKey: Equatable {
        let filter: MatchFilter
        let loaded: Bool
    }

    @ViewBuilder private func content(_ filter: MatchFilter, list: ArestemisStore.MatchList, kind: SearchKind?) -> some View {
        let matches = store.matches(filter, hunt: id)
        if matches.isEmpty {
            Group {
                if !list.loaded && list.error == nil {
                    CalmMessage(text: String(localized: "Loading listings…"), loading: true)
                } else if let error = list.error {
                    CalmMessage(text: error, action: (String(localized: "Try again"), {
                        Task { await store.loadMatches(filter, hunt: id) }
                    }))
                } else {
                    CalmMessage(text: emptyText(filter, kind: kind))
                }
            }
            .padding(.top, 40)
            .plainRow()
        } else {
            ForEach(matches) { match in
                ListingRow(match: match, store: store, showsState: filter == .all) {
                    navigation.listingsPath.append(.match(match.id))
                }
            }
        }
        if list.more {
            MoreRow(error: list.error, last: list.ids.last) { await store.loadMatches(filter, hunt: id, more: true) }
        }
        let rejected = store.rejected(hunt: id)
        if !rejected.items.isEmpty {
            FilteredOutButton(count: rejected.items.count) { navigation.sheet = .rejected(id) }
        }
    }

    private func emptyText(_ filter: MatchFilter, kind: SearchKind?) -> String {
        switch filter {
        case .new: String(localized: "Nothing new. New listings appear here the moment they're found.")
        case .saved: String(localized: "Nothing saved. Swipe right on a listing to keep it here.")
        case .applied:
            kind == .item ? String(localized: "No sellers asked yet.") : String(localized: "No applications yet.")
        case .all: String(localized: "No listings yet. They appear here the moment they're found.")
        }
    }
}
