import SwiftUI

/// A price monitor's page under its card (brief 137): the chart large over 30 · 90 · 365 days while the history is on
/// (`PriceChartView`: steps, the stretches out of stock dashed, the alarm's limit; the lowest and highest price named
/// under it), what it should do (the form's switches, changeable right here and saved as they change, Patrik: "changeable
/// anytime in the app"; `MonitorSwitches` refuses turning off the last one with its line), and the alarms it found while
/// it has an alarm or found some. "Open in shop" stands beside Edit above (`HuntPage`). An everywhere monitor's page
/// (brief 157, the plan's sketch): the chart of the cheapest price, then its shops' offers cheapest first (`OffersCard`:
/// the shop, its price, the availability, the shipping when known and the comparison site it came from; each opens its
/// link; five, then "+ N more shops"), the switches, "Where it looks" with the sites on, opening `PriceSitesScreen`
/// (saved as they change), and the alarms.
struct MonitorSections: View {
    let card: HuntCard
    let search: PriceSearch
    let store: ArestemisStore
    let open: (Int) -> Void
    let showAll: () -> Void
    /// "Where it looks", pushed from its row (the page holds it: a destination inside the scroll view is not found).
    @Binding var showsSites: Bool

    @State private var days = Prices.windows[0]
    @State private var switches: MonitorSwitches
    /// The switches' line after a change that was refused or is held back (an alarm without a condition yet).
    @State private var line: String?
    /// An alarm without a condition is shown, not saved, until it has one; the server's search is not taken over then.
    @State private var holding = false
    /// Counts the refusals, so a switch that was turned off against the rule is drawn on again.
    @State private var refusals = 0

    /// The sections' places on the page, for screenshots (`-scrollTo history|offers|switches`).
    static let historyID = "history"
    static let offersID = "offers"
    static let switchesID = "switches"

    private var everywhere: Bool { search.mode == .everywhere }

    init(card: HuntCard, search: PriceSearch, store: ArestemisStore, open: @escaping (Int) -> Void,
         showAll: @escaping () -> Void, showsSites: Binding<Bool>) {
        self.card = card
        self.search = search
        self.store = store
        self.open = open
        self.showAll = showAll
        _showsSites = showsSites
        _switches = State(initialValue: MonitorSwitches(search))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if search.history {
                HuntSection(title: everywhere ? String(localized: "Cheapest price") : String(localized: "Price history")) {
                    history
                }
                .id(MonitorSections.historyID)
            }
            if everywhere {
                HuntSection(title: String(localized: "Shops")) { offers }
                    .id(MonitorSections.offersID)
            }
            HuntSection(title: String(localized: "What it should do")) {
                MonitorSwitchesCard(history: historyBinding, alarm: alarmBinding, below: belowBinding,
                                    backInStock: backBinding, line: line)
                    .id(refusals)
            }
            .id(MonitorSections.switchesID)
            if everywhere { sitesRow }
            if showsAlarms {
                HuntSection(title: String(localized: "Alarms")) {
                    if let matches = store.latest(hunt: card.id) {
                        LatestMatches(matches: matches, store: store,
                                      empty: "No alarm yet. It comes as a push the moment it rings.",
                                      open: open, showAll: showAll)
                    } else {
                        ProgressView().controlSize(.small).tint(Ink.muted).frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
            }
        }
        // The monitor changed elsewhere (its form, another device, the save's answer): the switches follow, unless an
        // alarm without a condition is held here.
        .onChange(of: search) { _, new in
            if !holding { switches = MonitorSwitches(new) }
        }
        // The limit is saved once typing pauses.
        .task(id: switches.below) {
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            apply(switches.setBelow(switches.below, in: search))
        }
        // An everywhere monitor's offers and sites, asked again after each new read.
        .task(id: MonitorRead(card)) { if everywhere { await store.loadOffers(hunt: card.id) } }
        .onAppear(perform: debugLaunch)
    }

    // MARK: everywhere: the shops and where it looks

    /// The offers of the sites switched on, cheapest first; a quiet line while there are none, a calm failure with Try
    /// again.
    @ViewBuilder private var offers: some View {
        let state = store.offers(hunt: card.id)
        if let loaded = state.offers {
            let shown = OfferList.shown(loaded.offers, off: search.sourcesOff)
            if shown.isEmpty {
                Text(verbatim: card.price?.read == .waiting || card.price == nil
                     ? String(localized: "The first look in the shops takes a few minutes.")
                     : String(localized: "No shop offers it right now."))
                    .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 4)
            } else {
                OffersCard(offers: shown)
            }
        } else if let error = state.error {
            CalmMessage(text: error, action: (String(localized: "Try again"), {
                Task { await store.loadOffers(hunt: card.id, force: true) }
            }))
        } else {
            ProgressView().controlSize(.small).tint(Ink.muted).frame(maxWidth: .infinity, minHeight: 60)
        }
    }

    /// "Where it looks" with the sites switched on; it opens them.
    private var sitesRow: some View {
        let sites = store.offers(hunt: card.id).offers?.sites
        let value = sites.map { EverywhereWords.sites(PriceSites.onCount($0, off: search.sourcesOff)) }
        return Button { showsSites = true } label: {
            SettingsRow(title: String(localized: "Where it looks"), value: value)
        }
        .buttonStyle(SettingsRowStyle())
        .glassCard()
        .padding(.top, Look.sectionGap)
    }


    /// The alarms show while the alarm is on, or once it found some (a history alone never finds any).
    private var showsAlarms: Bool {
        let counts = card.counts
        return search.alarm != nil || counts.new + counts.saved + counts.today > 0
            || !(store.latest(hunt: card.id) ?? []).isEmpty
    }

    // MARK: the chart

    private var history: some View {
        let loaded = store.prices(hunt: card.id, days: days)
        return VStack(alignment: .leading, spacing: 14) {
            Picker("Days", selection: $days) {
                ForEach(Prices.windows, id: \.self) { window in Text(verbatim: PriceWords.window(window)).tag(window) }
            }
            .pickerStyle(.segmented)
            if let prices = loaded.prices {
                let chart = PriceChart(prices, limit: search.alarm?.below, days: days)
                if chart.isEmpty {
                    Text("The curve starts with the next read.")
                        .font(AppFont.text(13)).foregroundStyle(Ink.muted)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    PriceChartView(chart: chart, days: days)
                        .frame(height: 190)
                    VStack(alignment: .leading, spacing: 6) {
                        if let extremes = chart.extremes() {
                            Text(verbatim: extremes).font(AppFont.text(12)).foregroundStyle(Ink.secondary)
                        }
                        if chart.hasOutOfStock { OutOfStockKey() }
                    }
                    .padding(.leading, 2)
                }
            } else if let error = loaded.error {
                CalmMessage(text: error, action: (String(localized: "Try again"), {
                    Task { await store.loadPrices(hunt: card.id, days: days, force: true) }
                }))
            } else {
                ProgressView().controlSize(.small).tint(Ink.muted).frame(maxWidth: .infinity, minHeight: 190)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .task(id: MonitorWindow(read: MonitorRead(card), days: days)) {
            await store.loadPrices(hunt: card.id, days: days)
        }
    }

    // MARK: the switches

    private var historyBinding: Binding<Bool> {
        Binding(get: { switches.history }, set: { apply(switches.setHistory($0, in: search)) })
    }
    private var alarmBinding: Binding<Bool> {
        Binding(get: { switches.alarm }, set: { on in
            apply(switches.setAlarm(on, in: search, price: card.price?.price, currency: card.price?.currency))
        })
    }
    /// Typed: kept here, saved once typing pauses (the task above).
    private var belowBinding: Binding<Double?> {
        Binding(get: { switches.below }, set: { switches.below = $0.flatMap { $0 > 0 ? $0 : nil } })
    }
    private var backBinding: Binding<Bool> {
        Binding(get: { switches.backInStock }, set: { apply(switches.setBackInStock($0, in: search)) })
    }

    /// A change's outcome: saved at once (nothing is sent when it is the monitor as saved), or held or refused with the
    /// line.
    private func apply(_ outcome: MonitorSwitches.Outcome) {
        line = MonitorSwitches.line(outcome)
        switch outcome {
        case .save(let changed):
            holding = false
            guard changed != search else { return }
            Task { await store.saveMonitor(id: card.id, search: changed) }
        case .hold:
            holding = true
        case .refused:
            refusals += 1
        }
    }

    /// Screenshots (sample mode, DEBUG): `-priceDays 30|90|365` (the chart's window), `-monitorLine refused|hold` (the
    /// switches' line, as after turning off the last switch or every condition), `-openSites` ("Where it looks").
    private func debugLaunch() {
        #if DEBUG
        guard store.isSample else { return }
        if everywhere, LaunchArguments.current.contains("-openSites") {
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                showsSites = true
            }
        }
        if let asked = LaunchArguments.value("-priceDays").flatMap(Int.init), Prices.windows.contains(asked) { days = asked }
        switch LaunchArguments.value("-monitorLine") {
        case "refused": apply(.refused)
        case "hold":
            switches.alarm = true
            switches.below = nil
            switches.backInStock = false
            apply(.hold(PriceSearch.Alarm()))
        default: break
        }
        #endif
    }
}

/// The key under the chart while it shows a stretch out of stock: the dashed line and its words.
private struct OutOfStockKey: View {
    var body: some View {
        HStack(spacing: 8) {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 1))
                path.addLine(to: CGPoint(x: 22, y: 1))
            }
            .stroke(Ink.muted, style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [4, 5]))
            .frame(width: 22, height: 2)
            Text("Out of stock").font(AppFont.text(12)).foregroundStyle(Ink.muted)
        }
        .accessibilityElement(children: .combine)
    }
}

/// What the page's chart depends on: the monitor's last read and the window.
private struct MonitorWindow: Hashable {
    let read: MonitorRead
    let days: Int
}

/// An everywhere monitor's offers as rows in one glass card, cheapest first (the plan's sketch): the shop and its quiet
/// line (availability, shipping, the comparison site it came from) on the left, the price on the right, each row opening
/// the offer's link (the external mark, as Settings' links); the first five, then "+ N more shops", which shows the rest.
struct OffersCard: View {
    let offers: [Offer]
    @State private var showsAll = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        let shown = showsAll ? offers : Array(offers.prefix(OfferList.firstRows))
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, offer in
                if index > 0 { SettingsDivider() }
                Button { if let link = offer.link { openURL(link) } } label: { row(offer) }
                    .buttonStyle(SettingsRowStyle())
                    .disabled(offer.link == nil)
            }
            if offers.count > shown.count {
                SettingsDivider()
                Button { withAnimation(.easeOut(duration: 0.2)) { showsAll = true } } label: {
                    Text(verbatim: OfferList.more(offers.count - shown.count))
                        .font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.secondary)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity, minHeight: 46, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SettingsRowStyle())
            }
        }
        .glassCard()
    }

    private func row(_ offer: Offer) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: offer.shop).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                    .lineLimit(1)
                if let line = OfferList.line(offer) {
                    Text(verbatim: line).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            Spacer(minLength: 10)
            if let price = offer.price {
                Text(verbatim: PriceWords.money(price, currency: offer.currency))
                    .font(AppFont.number(15, weight: .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                    .fixedSize()
            } else {
                Text(verbatim: "–").font(AppFont.number(15)).foregroundStyle(Ink.muted)
            }
            Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.muted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .frame(minHeight: 58)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens the shop"))
    }
}

/// An everywhere monitor's "Where it looks" from its page: its sites as last loaded, and the switches saved at once with
/// the whole search, as the page's switches are (`ArestemisStore.saveMonitor`: shown at once, put back with a notice on
/// a refusal).
struct MonitorSitesPage: View {
    let id: Int
    let store: ArestemisStore

    var body: some View {
        let monitor = store.card(id)?.hunt.search.price
        PriceSitesScreen(product: store.card(id)?.price?.product ?? monitor?.identity?.name,
                         sites: store.offers(hunt: id).offers?.sites, off: off, store: store)
            .task { await store.loadOffers(hunt: id) }
    }

    private var off: Binding<[String]> {
        Binding(get: { store.card(id)?.hunt.search.price?.sourcesOff ?? [] }, set: { off in
            guard var changed = store.card(id)?.hunt.search.price else { return }
            changed.sourcesOff = off
            Task { await store.saveMonitor(id: id, search: changed) }
        })
    }
}
