import SwiftUI

/// The Listings tab ("Angebote", brief 133, Patrik's choice of 2026-11-02): the header with the search over listings
/// (the magnifying glass), then two parts, New | Searches, the user's choice remembered across launches.
/// - **New:** every search's unread new listings, grouped under each search's name with its count (no headings while
///   there is one search), the search with the newest finding first, newest first within it; a listing opened leaves
///   New when its page closes (brief 182; brief 180 kept it without its dot); swipe right for a favorite, left to
///   dismiss; a group goes with its last new listing. Then "Recently viewed" (the listings opened in the last 7 days
///   that are still new, `RecentlyViewedPage`), "Filtered out" and "Not checked in time" (brief 187, `NotCheckedListingsPage`)
///   for every search, each a quiet row shown while it has listings (`QuietLinkRow`). A notification's match opens over
///   it.
/// - **Searches:** one card per search, in the Hunts tab's order (paused ones too): its kind and name, the new count,
///   favorites and applied (asked) in a quiet line; a tap opens that search's listings (`SearchListingsPage`), the long
///   press offers Rename, Pause or Start and Delete (`huntCardMenu`).
/// The stack also holds the search over listings (`ListingSearchPage`), Recently viewed, Not checked in time and the
/// matches' pages.
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
                    case .recent(let hunt): RecentlyViewedPage(hunt: hunt, store: store, navigation: navigation)
                    case .notChecked(let hunt): NotCheckedListingsPage(hunt: hunt, store: store, navigation: navigation)
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

/// New: every search's unread new listings, grouped by search, then Recently viewed, Filtered out and Not checked in time.
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
            async let recent: Void = store.loadRecent()
            async let rejected: Void = store.loadRejected()
            async let notChecked: Void = store.loadNotChecked()
            async let overview: Void = store.reloadOverview(quiet: true)
            _ = await (matches, recent, rejected, notChecked, overview)
        }
        // Asked again whenever the list was forgotten (a hunt deleted), never in a loop after a failure.
        .task(id: store.list(.new).loaded) { if !store.list(.new).loaded { await store.loadMatches(.new) } }
        .task(id: store.recentList().loaded) {
            if !store.recentList().loaded && store.recentList().error == nil { await store.loadRecent() }
        }
        .task(id: store.rejected().loaded) {
            if !store.rejected().loaded && store.rejected().error == nil { await store.loadRejected() }
        }
        .task(id: store.notChecked().loaded) {
            if !store.notChecked().loaded && store.notChecked().error == nil { await store.loadNotChecked() }
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
        if let recent = QuietLink(.recentlyViewed, count: store.recentMatches().count, more: store.recentList().more) {
            QuietLinkRow(link: recent) { navigation.showRecent(hunt: nil) }
        }
        if let filtered = QuietLink(.filteredOut, count: store.rejected().items.count) {
            QuietLinkRow(link: filtered, spot: .filteredOut) { navigation.sheet = .rejected(nil) }
        }
        if let notChecked = QuietLink(.notChecked, count: store.notCheckedCount()) {
            QuietLinkRow(link: notChecked) { navigation.showNotChecked(hunt: nil) }
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
/// opens it on the portal. A look hunt's (brief 268) show their photo and the thumbs that teach its judge.
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
                        if store.canVote(on: item) {
                            lookRow(item)
                        } else {
                            Button { open(item) } label: { row(item) }
                                .buttonStyle(.plain)
                                .disabled(item.listing.portalURL == nil)
                        }
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
        .overlay(alignment: .top) {
            if let notice = store.notice {
                NoticeBanner(text: notice.text) { store.dismissNotice() }
                    .padding(.top, 6)
            }
        }
        .task { await store.loadRejected(hunt: hunt) }
    }

    private func open(_ item: Rejected) {
        item.listing.portalURL.map { openURL($0) }
    }

    /// A listing turned down: the whole card opens it on its site.
    private func row(_ item: Rejected) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            words(item)
            sourceLine(item).padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the listing on \(item.listing.sourceName)")
    }

    /// A listing a look hunt turned down (brief 268): its photo beside the words, so it can be judged at a glance, and the
    /// thumbs at the foot of the card that teach the judge. The photo and the words open it on its site; the thumbs only
    /// vote.
    private func lookRow(_ item: Rejected) -> some View {
        let photo = item.listing.photos.first
        let photoSize = CGSize(width: 64, height: 80)
        return VStack(alignment: .leading, spacing: 4) {
            Button { open(item) } label: {
                HStack(alignment: .top, spacing: 12) {
                    if let photo {
                        ListingPhoto(url: photo).frame(width: photoSize.width, height: photoSize.height)
                            .clipShape(RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous))
                    }
                    VStack(alignment: .leading, spacing: 6) { words(item) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(item.listing.portalURL == nil)
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens the listing on \(item.listing.sourceName)")
            HStack(alignment: .center, spacing: 8) {
                sourceLine(item)
                Spacer(minLength: 0)
                LookVoteButtons(vote: item.vote, isSaving: store.changingRejectedVotes.contains(item.id),
                                size: .compact) { vote in
                    Task { await store.setVote(vote, forRejected: item.id) }
                }
                .padding(.vertical, -6).padding(.trailing, -6) // 44 pt targets around 32 pt circles
            }
            .padding(.leading, photo == nil ? 0 : photoSize.width + 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// The title with the mark that it opens the site, the listing's facts and why it was turned down.
    @ViewBuilder private func words(_ item: Rejected) -> some View {
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
        Text(reason(item.reason)).font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The reason as the server wrote it; the look check's "Look 4/10" (or "Look not judged") at its start a little
    /// stronger, as the score on a finding's page.
    private func reason(_ text: String) -> AttributedString {
        let reason = RejectedReason(text)
        guard let lead = reason.lead else { return AttributedString(reason.rest) }
        var label = AttributedString(lead + ":")
        label.font = AppFont.text(13, weight: .semibold)
        label.foregroundColor = Ink.secondary
        return label + AttributedString(" " + reason.rest)
    }

    private func sourceLine(_ item: Rejected) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            Text([item.listing.sourceName, Format.relative(item.found, now: context.date)].compactMap { $0 }
                    .joined(separator: " · "))
                // A touch fainter than muted on the dark wall; on the light one muted is already the faintest that reads.
                .font(AppFont.text(11)).foregroundStyle(Ink.muted.opacity(scheme == .dark ? 0.85 : 1))
                .lineLimit(1)
        }
    }
}
