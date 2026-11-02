import SwiftUI

/// The search over the found listings (brief 133; the server ranks, brief 132): pushed from the magnifying glass on the
/// Listings tab (every search's listings) or on one search's page (only its listings, its name as the title). The field
/// on its glass card as the place search's, the keyboard up as the page opens (once: back from a match it stays down and
/// the words stay). From two letters, once typing pauses, the server's best matches, its order kept: each row as
/// elsewhere, with its state (NEW, SAVED, APPLIED or ASKED) and, over every search, the search it belongs to; a tap opens
/// the match, the swipes save and dismiss. Nothing found, or a failure with Try again, is one calm line. The field is the
/// list's first row and scrolls with it (a scroll puts the keyboard away).
struct ListingSearchPage: View {
    let hunt: Int?
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    @State private var search: ListingSearch
    @State private var text = ""
    @FocusState private var focused: Bool
    /// The keyboard comes up once, as the page opens.
    @State private var opened = false

    init(hunt: Int?, store: ArestemisStore, navigation: AppNavigation) {
        self.hunt = hunt
        self.store = store
        self.navigation = navigation
        _search = State(initialValue: store.listingSearch(hunt: hunt))
    }

    private var huntText: HuntText? {
        hunt.flatMap(store.card).map { HuntText($0.hunt, page: $0.page, sites: store.siteNames) }
    }

    var body: some View {
        // The field is the list's first row, as in the place search: above the list, the list's faded top edge would
        // cut through the field card's soft shadow on the light wall.
        List {
            SearchBox(text: $text, prompt: ListingSearchWords.prompt(), busy: search.isSearching, clears: true,
                      focused: $focused)
                .listRowInsets(EdgeInsets(top: 0, leading: Look.side, bottom: Look.rowGap / 2, trailing: Look.side))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            content
        }
        .listingsList()
        .scrollDismissesKeyboard(.immediately)
        .provinceWall()
        .navigationTitle(ListingSearchWords.title(hunt: hunt == nil ? nil : huntText))
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: text) { _, new in
            let limited = String(new.prefix(ListingSearch.maximumLength))
            if limited != new { text = limited } else { search.update(new) }
        }
        .task {
            guard !opened else { return }
            opened = true
            // Screenshots (`-search <words>`): the words typed, the keyboard down so the results show.
            let words = navigation.findQuery
            navigation.findQuery = ""
            if words.isEmpty { focused = true } else { text = words }
        }
    }

    @ViewBuilder private var content: some View {
        switch search.phase {
        case .typing:
            Caption(text: ListingSearchWords.hint())
                .padding(.horizontal, 4).padding(.top, 2)
                .plainRow()
        case .searching:
            EmptyView()
        case .found:
            let shown = results
            if shown.isEmpty, let words = search.searched {
                nothingFound(words)
            } else {
                // Over every search, each row names its search (unless the account has one).
                let names = hunt == nil && store.hunts.count > 1
                ForEach(shown) { match in
                    ListingRow(match: match, store: store, showsState: true, showsNewState: true,
                               hunt: names ? text(of: match) : nil) {
                        focused = false
                        navigation.listingsPath.append(.match(match.id))
                    }
                }
                if search.more {
                    Caption(text: ListingSearchWords.more())
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                        .padding(.top, 6)
                        .plainRow()
                }
            }
        case .nothingFound(let words):
            nothingFound(words)
        case .failed(let error):
            CalmMessage(text: error, action: (String(localized: "Try again"), { search.retry() }))
                .padding(.top, 20)
                .plainRow()
        }
    }

    /// The server's results as they are now (a swipe here or elsewhere changes them; a dismissed one leaves).
    private var results: [Match] {
        search.results.map { store.match($0.id) ?? $0 }.filter { $0.state != .dismissed }
    }

    private func text(of match: Match) -> HuntText? {
        store.card(match.huntID).map { HuntText($0.hunt, page: $0.page, sites: store.siteNames) }
    }

    private func nothingFound(_ words: String) -> some View {
        CalmMessage(text: ListingSearchWords.nothingFound(words))
            .padding(.top, 20)
            .plainRow()
    }
}
