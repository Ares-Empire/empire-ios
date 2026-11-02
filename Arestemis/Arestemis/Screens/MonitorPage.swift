import SwiftUI

/// A price monitor's page under its card (brief 137): the chart large over 30 · 90 · 365 days while the history is on
/// (`PriceChartView`: steps, the stretches out of stock dashed, the alarm's limit; the lowest and highest price named
/// under it), what it should do (the form's switches, changeable right here and saved as they change, Patrik: "changeable
/// anytime in the app"; `MonitorSwitches` refuses turning off the last one with its line), and the alarms it found while
/// it has an alarm or found some. "Open in shop" stands beside Edit above (`HuntPage`).
struct MonitorSections: View {
    let card: HuntCard
    let search: PriceSearch
    let store: ArestemisStore
    let open: (Int) -> Void
    let showAll: () -> Void

    @State private var days = Prices.windows[0]
    @State private var switches: MonitorSwitches
    /// The switches' line after a change that was refused or is held back (an alarm without a condition yet).
    @State private var line: String?
    /// An alarm without a condition is shown, not saved, until it has one; the server's search is not taken over then.
    @State private var holding = false
    /// Counts the refusals, so a switch that was turned off against the rule is drawn on again.
    @State private var refusals = 0

    /// The sections' places on the page, for screenshots (`-scrollTo history|switches`).
    static let historyID = "history"
    static let switchesID = "switches"

    init(card: HuntCard, search: PriceSearch, store: ArestemisStore, open: @escaping (Int) -> Void,
         showAll: @escaping () -> Void) {
        self.card = card
        self.search = search
        self.store = store
        self.open = open
        self.showAll = showAll
        _switches = State(initialValue: MonitorSwitches(search))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if search.history {
                HuntSection(title: String(localized: "Price history")) { history }
                    .id(MonitorSections.historyID)
            }
            HuntSection(title: String(localized: "What it should do")) {
                MonitorSwitchesCard(history: historyBinding, alarm: alarmBinding, below: belowBinding,
                                    backInStock: backBinding, line: line)
                    .id(refusals)
            }
            .id(MonitorSections.switchesID)
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
        .onAppear(perform: debugLaunch)
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
    /// switches' line, as after turning off the last switch or every condition).
    private func debugLaunch() {
        #if DEBUG
        guard store.isSample else { return }
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
