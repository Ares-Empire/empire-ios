import SwiftUI

/// Recently viewed (brief 182; Patrik, 2026-11-05, on read listings that stayed in New: "It should leave neu … Like a past
/// / history sort of thing but limited time maybe? Because if you want to look at it again just favor it"): the listings
/// opened in the last 7 days that are still new, of every search (from the row in New) or of one (from the row on its
/// listings), the latest opened first; the server decides the 7 days. Under the title one quiet line says what it holds
/// and how to keep one, then the usual rows (tap, swipes and long press as everywhere; no dot, they are read), over every
/// search each with its search's mark and name. One made a favorite, applied or dismissed leaves at once; once none is
/// left, one calm line.
struct RecentlyViewedPage: View {
    let hunt: Int?
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation

    var body: some View {
        List {
            Text(RecentlyViewedWords.line())
                .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.bottom, 6)
                .plainRow()
            content
        }
        .listingsList()
        .refreshable { await store.loadRecent(hunt: hunt) }
        .provinceWall()
        .navigationTitle(RecentlyViewedWords.title())
        .navigationBarTitleDisplayMode(.inline)
        // Loaded with New or the search's listings; asked here when it was not, never in a loop after a failure.
        .task(id: store.recentList(hunt: hunt).loaded) {
            let list = store.recentList(hunt: hunt)
            if !list.loaded && list.error == nil { await store.loadRecent(hunt: hunt) }
        }
    }

    @ViewBuilder private var content: some View {
        let list = store.recentList(hunt: hunt)
        let matches = store.recentMatches(hunt: hunt)
        if matches.isEmpty {
            Group {
                if !list.loaded && list.error == nil {
                    CalmMessage(text: String(localized: "Loading listings…"), loading: true)
                } else if let error = list.error {
                    CalmMessage(text: error, action: (String(localized: "Try again"), {
                        Task { await store.loadRecent(hunt: hunt) }
                    }))
                } else {
                    CalmMessage(text: RecentlyViewedWords.empty())
                }
            }
            .padding(.top, 20)
            .plainRow()
        } else {
            // Over every search, each row names its search (unless the account has one).
            let names = hunt == nil && store.hunts.count > 1
            ForEach(matches) { match in
                ListingRow(match: match, store: store, hunt: names ? text(of: match) : nil) {
                    navigation.listingsPath.append(.match(match.id))
                }
            }
        }
    }

    private func text(of match: Match) -> HuntText? {
        store.card(match.huntID).map { HuntText($0, sites: store.siteNames) }
    }
}
