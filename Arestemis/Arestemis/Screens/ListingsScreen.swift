import SwiftUI

/// The Listings tab ("Angebote", brief 133, Patrik's choice of 2026-11-02): the header with the search over listings
/// (the magnifying glass), then two parts, New | Searches, the user's choice remembered across launches.
/// - **New:** every search's new listings, grouped under each search's name with its unread count (no headings while
///   there is one search), the search with the newest finding first, newest first within it; a listing opened stays,
///   without its dot, until it is a favorite, applied or dismissed (brief 180); swipe right for a favorite, left to
///   dismiss; a group goes with its last new listing. Then "Filtered out" for every search. A notification's match
///   opens over it.
/// - **Searches:** one card per search, in the Hunts tab's order (paused ones too): its kind and name, the new count,
///   favorites and applied (asked) in a quiet line; a tap opens that search's listings (`SearchListingsPage`), the long
///   press offers Rename, Pause or Start and Delete (`huntCardMenu`).
/// The stack also holds the search over listings (`ListingSearchPage`) and the matches' pages.
struct ListingsScreen: View {
    @Bindable var store: ArestemisStore
    @Bindable var navigation: AppNavigation

    var body: some View {
        NavigationStack(path: $navigation.listingsPath) {
            VStack(spacing: 0) {
                header
                switch navigation.part {
                case .new: NewPart(store: store, navigation: navigation)
                case .searches: SearchesPart(store: store, navigation: navigation)
                }
            }
            .tourSpotlight()
            .provinceWall()
            .tourCardRoom()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: ListingsRoute.self) { route in
                Group {
                    switch route {
                    case .hunt(let id): SearchListingsPage(id: id, store: store, navigation: navigation)
                    case .find(let hunt): ListingSearchPage(hunt: hunt, store: store, navigation: navigation)
                    case .match(let id): MatchDetailScreen(id: id, store: store, navigation: navigation)
                    }
                }
                .tourCardRoom()
            }
        }
        .undoBar(visibleUndo, accent: Look.accent)
        .tourCard()
    }

    /// Only the visible tab owns the shared offer's timer; cancelling a hidden tab must not clear it.
    private var visibleUndo: Binding<UndoOffer?> {
        // Read the offer here so Observation redraws the bar when the store changes it.
        _ = store.undo
        return Binding(get: { navigation.tab == .listings ? store.undo : nil }, set: { offer in
            if navigation.tab == .listings { store.undo = offer }
        })
    }

    private var header: some View {
        VStack(spacing: 10) {
            AppHeader(title: String(localized: "Listings")) {
                if !store.hunts.isEmpty {
                    GlassIconButton(symbol: "magnifyingglass", label: String(localized: "Search listings")) {
                        navigation.find(hunt: nil)
                    }
                    .tourAnchor(.findAll)
                }
            }
            Picker("Show", selection: Binding(get: { navigation.part }, set: { navigation.choose($0) })) {
                ForEach(ListingsPart.allCases) { Text($0.title()).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Look.side)
        }
        .padding(.bottom, 2)
    }
}

/// New: every search's new listings, grouped by search.
private struct NewPart: View {
    let store: ArestemisStore
    let navigation: AppNavigation

    var body: some View {
        List {
            content
        }
        .listingsList()
        .refreshable {
            async let matches: Void = store.loadMatches(.new)
            async let rejected: Void = store.loadRejected()
            async let overview: Void = store.reloadOverview(quiet: true)
            _ = await (matches, rejected, overview)
        }
        // Asked again whenever the list was forgotten (a hunt deleted), never in a loop after a failure.
        .task(id: store.list(.new).loaded) { if !store.list(.new).loaded { await store.loadMatches(.new) } }
        .task(id: store.rejected().loaded) {
            if !store.rejected().loaded && store.rejected().error == nil { await store.loadRejected() }
        }
    }

    @ViewBuilder private var content: some View {
        let list = store.list(.new)
        let groups = NewListings.groups(store.matches(.new))
        if groups.isEmpty {
            Group {
                if !list.loaded && list.error == nil {
                    CalmMessage(text: String(localized: "Loading listings…"), loading: true)
                } else if let error = list.error {
                    CalmMessage(text: error, action: (String(localized: "Try again"), { Task { await store.loadMatches(.new) } }))
                } else if store.hunts.isEmpty {
                    CalmMessage(text: String(localized: "No search yet. Set one up and listings appear here the moment they're found."),
                                action: (String(localized: "New search"), { navigation.startNewSearch() }))
                } else {
                    CalmMessage(text: String(localized: "Nothing new. New listings appear here the moment they're found."))
                }
            }
            .padding(.top, 40)
            .plainRow()
        } else {
            let headings = NewListings.showsHeadings(searches: store.hunts.count)
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if headings { heading(group, first: index == 0) }
                ForEach(group.matches) { match in
                    ListingRow(match: match, store: store, spot: .newListing(match.id)) {
                        navigation.listingsPath.append(.match(match.id))
                    }
                }
            }
        }
        if list.more {
            MoreRow(error: list.error, last: list.ids.last) { await store.loadMatches(.new, more: true) }
        }
        let rejected = store.rejected()
        if !rejected.items.isEmpty {
            FilteredOutButton(count: rejected.items.count) { navigation.sheet = .rejected(nil) }
        }
    }

    private func heading(_ group: NewGroup, first: Bool) -> some View {
        let text = store.card(group.huntID).map { HuntText($0, sites: store.siteNames) }
        return NewGroupHeading(kind: text?.kind, title: text?.title ?? String(localized: "Search"),
                               count: group.unread) {
            navigation.openSearch(group.huntID, filter: .new)
        }
        .listRowInsets(EdgeInsets(top: first ? 0 : 16, leading: Look.side, bottom: 0, trailing: Look.side))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }
}

/// Searches: one card per search, opening its listings.
private struct SearchesPart: View {
    let store: ArestemisStore
    let navigation: AppNavigation

    var body: some View {
        List {
            if store.hunts.isEmpty {
                CalmMessage(text: String(localized: "No search yet. Set one up and listings appear here the moment they're found."),
                            action: (String(localized: "New search"), { navigation.startNewSearch() }))
                    .padding(.top, 40)
                    .plainRow()
            } else {
                ForEach(store.hunts) { card in
                    SearchRowCard(row: SearchRow(card, sites: store.siteNames)) {
                        navigation.openSearch(card.id, filter: .opening(card.counts))
                    }
                    .huntCardMenu(card, store: store, navigation: navigation)
                    .plainRow(vertical: Look.rowGap / 2)
                }
            }
        }
        .listingsList()
        .refreshable { await store.reloadOverview() }
    }
}

/// The listings the AI turned down in the last 7 days (of every search, or of one), each with its reason; tapping one
/// opens it on the portal.
struct RejectedSheet: View {
    let store: ArestemisStore
    /// nil: every search's.
    var hunt: Int? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Look.rowGap) {
                    Text("Listings that passed the fields but not the check, from the last 7 days. If good ones end up here, the search may be too strict.")
                        .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.bottom, 6)
                    let rejected = store.rejected(hunt: hunt)
                    if rejected.items.isEmpty {
                        CalmMessage(text: rejected.error ?? String(localized: "Nothing was filtered out."), loading: rejected.isLoading)
                    }
                    ForEach(rejected.items) { item in
                        Button { item.listing.portalURL.map { openURL($0) } } label: { row(item) }
                            .buttonStyle(.plain)
                            .disabled(item.listing.portalURL == nil)
                    }
                }
                .padding(.horizontal, Look.side).padding(.top, 8).padding(.bottom, 30)
            }
            .provinceWall()
            .navigationTitle("Filtered out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await store.loadRejected(hunt: hunt) }
    }

    private func row(_ item: Rejected) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.listing.title).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.muted)
            }
            let facts = item.listing.item == nil ? item.listing.factsWithRent : item.listing.itemFactsWithPrice()
            if !facts.isEmpty {
                Text(facts).font(AppFont.text(13)).foregroundStyle(Ink.secondary).lineLimit(1)
            }
            Text(item.reason).font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text([item.listing.sourceName, Format.relative(item.found, now: context.date)].compactMap { $0 }
                        .joined(separator: " · "))
                    // A touch fainter than muted on the dark wall; on the light one muted is already the faintest that reads.
                    .font(AppFont.text(11)).foregroundStyle(Ink.muted.opacity(scheme == .dark ? 0.85 : 1))
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the listing on \(item.listing.sourceName)")
    }
}
