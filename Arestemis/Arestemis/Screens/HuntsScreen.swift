import SwiftUI

/// The first tab ("Suche"): every hunt as a card, oldest first, then New search (its page, brief 135), the portals and
/// the latest matches across all hunts, and the ARESTEMIS band at the end of the scroll (`WordmarkScrollView`). A card
/// opens the hunt's page; its long press offers Rename, Pause or Start and Delete (`huntCardMenu`). The stack also holds
/// New search, the matches' pages and the search forms (`HuntRoute`).
struct HuntsScreen: View {
    @Bindable var store: ArestemisStore
    @Bindable var navigation: AppNavigation
    var scrollsToBottom = false
    /// Screenshots (`-scrollToHunt <id>`): the list starts at this hunt's card.
    var scrollsToHunt: Int? = nil
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $navigation.huntPath) {
            ScrollViewReader { reader in
                WordmarkScrollView(word: "ARESTEMIS") {
                    VStack(spacing: 0) {
                        AppHeader(title: "Arestemis") {
                            GlassIconButton(symbol: "gearshape", label: String(localized: "Settings")) { navigation.sheet = .settings }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            if let error = store.overviewError {
                                Text(error).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.bottom, 10)
                            }
                            if store.hunts.isEmpty {
                                NoHuntCard { navigation.startNewSearch() }
                            } else {
                                hunts
                            }
                            if let sources = store.overview?.sources, !sources.isEmpty {
                                HuntSection(title: String(localized: "Portals")) { PortalsCard(sources: sources) }
                            }
                            if !store.hunts.isEmpty {
                                HuntSection(title: String(localized: "Latest")) {
                                    LatestMatches(matches: store.latest, store: store,
                                                  open: { navigation.huntPath.append(.match($0)) },
                                                  showAll: { navigation.showListings() })
                                }
                            }
                        }
                        .padding(.horizontal, Look.side).padding(.top, 10)
                    }
                }
                .scrollIndicators(.hidden)
                .edgeFade(top: 16)
                .refreshable { await store.reloadOverview() }
                .onAppear {
                    if scrollsToBottom { DispatchQueue.main.async { reader.scrollToWordmark() } }
                    if let id = scrollsToHunt {
                        DispatchQueue.main.async { reader.scrollTo(Self.cardID(id), anchor: .top) }
                    }
                }
            }
            .provinceWall()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: HuntRoute.self) { route in
                switch route {
                case .hunt(let id): HuntPage(id: id, store: store, navigation: navigation)
                case .match(let id): MatchDetailScreen(id: id, store: store, navigation: navigation)
                case .newSearch: NewSearchScreen(store: store, navigation: navigation)
                case .form(.flat, let id, let example):
                    FlatSearchScreen(store: store, navigation: navigation, huntID: id, example: example)
                case .form(.item, let id, let example):
                    ItemSearchScreen(store: store, navigation: navigation, huntID: id, example: example)
                case .form(.price, let id, let example):
                    PriceSearchScreen(store: store, navigation: navigation, huntID: id, example: example)
                case .form(.watch, let id, let example):
                    WatchSearchScreen(store: store, navigation: navigation, huntID: id, example: example)
                }
            }
            .task(id: scenePhase) { await keepFresh() }
        }
        .undoBar(visibleUndo, accent: Look.accent)
    }

    /// Only the visible tab owns the shared offer's timer; cancelling a hidden tab must not clear it.
    private var visibleUndo: Binding<UndoOffer?> {
        // Read the offer here so Observation redraws the bar when the store changes it.
        _ = store.undo
        return Binding(get: { navigation.tab == .hunt ? store.undo : nil }, set: { offer in
            if navigation.tab == .hunt { store.undo = offer }
        })
    }

    private var hunts: some View {
        VStack(spacing: Look.rowGap) {
            ForEach(store.hunts) { card in
                HuntListCard(card: card, sites: store.siteNames, chart: monitorChart(card),
                             busy: store.isChanging(hunt: card.id),
                             open: { navigation.huntPath.append(.hunt(card.id)) },
                             toggle: { active in Task { await store.setActive(id: card.id, active: active) } })
                    .huntCardMenu(card, store: store, navigation: navigation)
                    .id(Self.cardID(card.id))
                    // A monitor's 30-day line, asked again after each new read (a new point).
                    .task(id: MonitorRead(card)) { await store.loadPrices(hunt: card.id, days: 30) }
            }
            NewSearchButton { navigation.startNewSearch() }
        }
    }

    private static func cardID(_ hunt: Int) -> String { "hunt-\(hunt)" }

    /// A monitor's 30-day line on its card, while its history is on and has loaded.
    private func monitorChart(_ card: HuntCard) -> PriceChart? {
        guard let search = card.hunt.search.price, search.history,
              let prices = store.prices(hunt: card.id, days: 30).prices else { return nil }
        return PriceChart(prices, limit: search.alarm?.below, days: 30)
    }

    /// While the tab is on screen and the app is active, the cards and figures follow the server every minute.
    private func keepFresh() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await store.reloadOverview(quiet: true)
        }
    }
}

/// Without a hunt: today's empty state, with New search.
private struct NoHuntCard: View {
    let newSearch: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("No search yet").font(AppFont.text(20, weight: .semibold)).foregroundStyle(Ink.primary)
            Text("Set what you are looking for: a flat, or something to buy. Arestemis then watches the portals and tells you the moment a listing fits.")
                .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)
            Button("New search", action: newSearch).buttonStyle(.accent).padding(.top, 20)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: Look.accent, raised: true)
    }
}

/// Under the hunts' cards: a quiet full-width button with a thin outline (as "Filtered out" on Listings).
private struct NewSearchButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                Text("New search")
            }
            .font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.secondary)
            .frame(maxWidth: .infinity, minHeight: 48)
            .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.line))
            .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        }
        .buttonStyle(CardPressStyle())
    }
}

/// What a monitor's history depends on: its last read and whether the history is on (other kinds: nothing).
struct MonitorRead: Hashable {
    let hunt: Int
    let checked: String?
    let history: Bool

    init(_ card: HuntCard) {
        hunt = card.id
        checked = card.price?.checked
        history = card.hunt.search.price?.history ?? false
    }
}
