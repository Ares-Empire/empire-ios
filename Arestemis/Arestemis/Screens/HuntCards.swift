import SwiftUI

/// One hunt on the Hunts tab: today's hunt card made compact. The kind's mark and the hunt's name with the new count
/// beside it, what it looks for in one or two lines, "checked less often" when the server reads it less often, then the
/// status line (the pulse while it runs, PAUSED otherwise) beside its Start / Pause, smaller. A watch shows its host under
/// its name, then what the page says now as its main fact (or a quiet line: reading, or why the page cannot be read) and
/// when it was checked and changed (`WatchLines`). A price monitor (brief 137, the sketch's card) shows the product, the
/// host and what it does ("Alarm under €450", "History only") under its name, then the price large with its
/// availability, the small 30-day line while the history is on, and when it was checked (`PriceLines`). Tapping the card
/// opens the hunt's page; the button is its own (beside the card's, not inside it). A hunt of a kind this build does not
/// know shows its name and "Needs a newer app", nothing else.
struct HuntListCard: View {
    let card: HuntCard
    /// The server's names for a thing hunt's sites.
    let sites: SiteNames
    /// A monitor's 30-day line; nil without a history (or before it loaded).
    var chart: PriceChart? = nil
    var offer: Offer? = nil
    let busy: Bool
    let open: () -> Void
    let toggle: (Bool) -> Void

    var body: some View {
        let text = HuntText(card, sites: sites)
        let known = text.kind != nil
        ZStack(alignment: .bottomTrailing) {
            Button(action: open) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        HuntTitle(text: text, size: 17)
                        Spacer(minLength: 0)
                        if known { NewCount(count: card.counts.new) }
                    }
                    if let line = text.details ?? text.newerApp {
                        Text(line).font(AppFont.text(13)).foregroundStyle(Ink.secondary).lineSpacing(2)
                            .lineLimit(text.kind == .watch ? 1 : 2).fixedSize(horizontal: false, vertical: true)
                            .padding(.top, 5)
                    }
                    if text.kind == .watch {
                        WatchLines(page: card.page, compact: true).padding(.top, 10)
                    }
                    if text.kind == .price {
                        PriceLines(state: card.price, compact: true,
                                   everywhere: card.hunt.search.price?.mode == .everywhere, chart: chart,
                                   offer: offer, delivery: card.hunt.search.price?.delivery)
                            .padding(.top, 10)
                    }
                    if card.slowed && known {
                        SlowedLine().padding(.top, 6)
                    }
                    if known {
                        // The status line; its button sits on this row's right, outside this label.
                        HuntStatus(active: card.hunt.active, kind: text.kind, stopped: card.isStopped)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
            }
            .buttonStyle(CardPressStyle())
            .accessibilityHint(text.kind == .watch ? Text("Opens the watch")
                               : text.kind == .price ? Text("Opens the price monitor") : Text("Opens the search"))
            if known {
                StartPauseButton(active: card.hunt.active, kind: text.kind, busy: busy, height: 36, toggle: toggle)
                    .fixedSize()
                    .padding(18)
            }
        }
        .glassCard(raised: true)
        .animation(.easeOut(duration: 0.2), value: card.hunt.active)
    }
}

/// The hunt's card on its page: today's hunt card for any kind. Status, the name in big (the page puts it there: as a
/// button that renames it in place, or its field, brief 135), what it looks for (every search word of a thing hunt
/// with several, brief 149; a watch: its host, what the page says
/// now and when it was checked and changed), and the one button (Start hunting / Start watching / Pause); for a kind this
/// build does not know only its name and "Needs a newer app". While the name is edited the button takes no taps (a tap
/// there ends the editing, `HuntPage`).
struct HuntHeroCard<Title: View>: View {
    let card: HuntCard
    let sites: SiteNames
    let busy: Bool
    var editing = false
    var offer: Offer? = nil
    let toggle: (Bool) -> Void
    @ViewBuilder let title: (HuntText) -> Title

    var body: some View {
        let text = HuntText(card, sites: sites, allWords: true)
        VStack(alignment: .leading, spacing: 0) {
            if text.kind != nil {
                HuntStatus(active: card.hunt.active, kind: text.kind, stopped: card.isStopped).padding(.bottom, 14)
            }
            title(text)
            if let line = text.details ?? text.newerApp {
                Text(line).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            if text.kind == .watch {
                WatchLines(page: card.page, compact: false).padding(.top, 14)
            }
            if text.kind == .price {
                PriceLines(state: card.price, compact: false, everywhere: card.hunt.search.price?.mode == .everywhere,
                           offer: offer, delivery: card.hunt.search.price?.delivery)
                    .padding(.top, 14)
            }
            if card.slowed && text.kind != nil {
                SlowedLine().padding(.top, 8)
            }
            if text.kind != nil {
                StartPauseButton(active: card.hunt.active, kind: text.kind, busy: busy, height: 50, toggle: toggle)
                    .allowsHitTesting(!editing)
                    .padding(.top, 20)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: Look.accent, raised: true)
        .animation(.easeOut(duration: 0.2), value: card.hunt.active)
    }
}

/// "● HUNTING" (a watch: "● WATCHING") with the pulse, or "● PAUSED" in grey; a blocked watch "● STOPPED" in grey, as
/// the server reads its page no more.
struct HuntStatus: View {
    let active: Bool
    var kind: SearchKind? = nil
    var stopped = false

    var body: some View {
        let running = active && !stopped
        HStack(spacing: 9) {
            StatusDot(active: running)
            StatusLabel(text: HuntWords(kind).status(active: active, stopped: stopped), tone: running ? .accent : .inactive,
                        accent: Look.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

/// A watch's lines under its name and host (`WatchCardText`): what the page says now about the change, the card's main
/// fact in ink; or instead one quiet line in muted ink (reading the page, or the server's note on why it cannot be read,
/// as the greyed sites say why: no alarm colour); then when it was checked and when the page last changed, following the
/// clock. `compact` on the Hunts list, larger on the watch's page.
struct WatchLines: View {
    let page: PageState?
    let compact: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let text = WatchCardText(page, now: context.date)
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                if let fact = text.fact {
                    Text(fact).font(AppFont.text(compact ? 15 : 17, weight: .medium)).foregroundStyle(Ink.primary)
                        .lineSpacing(2).lineLimit(compact ? 2 : 4).fixedSize(horizontal: false, vertical: true)
                }
                if let note = text.note {
                    Text(note).font(AppFont.text(compact ? 13 : 14)).foregroundStyle(Ink.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let times = text.times {
                    Text(times).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }
}

/// The kind's small mark (a house, a tag, a falling line, an eye; muted ink) and the hunt's name.
struct HuntTitle: View {
    let kind: SearchKind?
    let title: String
    let size: CGFloat

    init(text: HuntText, size: CGFloat) {
        self.init(kind: text.kind, title: text.title, size: size)
    }

    init(kind: SearchKind?, title: String, size: CGFloat) {
        self.kind = kind
        self.title = title
        self.size = size
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size > 18 ? 9 : 7) {
            if let kind {
                Image(systemName: kind.symbol).font(.system(size: size * 0.72, weight: .medium))
                    .foregroundStyle(Ink.muted)
                    .accessibilityLabel(Text(verbatim: kind.choiceTitle()))
            }
            Text(title).font(AppFont.text(size, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A small pen after a name that is edited where it stands (Aresium's `PenButton`): SF `pencil` in muted ink, growing
/// with the text size, a 44 pt tap area.
struct PenButton: View {
    let label: Text
    let action: () -> Void
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 15

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil").font(.system(size: size, weight: .medium)).foregroundStyle(Ink.muted)
                .frame(width: 44, height: 44).contentShape(Rectangle())
                .padding(-12)                   // the 44 pt area, drawn small beside the name
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// The long press on a search's card (the Hunts list, Listings → Searches; brief 135): Rename (the search's page on the
/// Hunts tab, its name's field ready), Pause or Start, Delete (asks first, as on its page). A search this build cannot
/// read offers Delete alone (`HuntPageActions`).
private struct HuntCardMenu: ViewModifier {
    let card: HuntCard
    let store: ArestemisStore
    let navigation: AppNavigation
    @State private var confirmDelete = false

    func body(content: Content) -> some View {
        let actions = HuntPageActions(card.hunt)
        let words = HuntWords(SearchKind(card.hunt.kind))
        let busy = store.isChanging(hunt: card.id)
        content
            .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
            .contextMenu {
                if actions.rename {
                    Button { navigation.rename(card.id) } label: { Label("Rename", systemImage: "pencil") }
                        .disabled(busy)
                }
                if actions.startPause {
                    if card.hunt.active {
                        Button { setActive(false) } label: { Label("Pause", systemImage: "pause") }.disabled(busy)
                    } else {
                        Button { setActive(true) } label: { Label("Start", systemImage: "play") }.disabled(busy)
                    }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                    .disabled(busy)
            }
            .confirmationDialog(words.deleteQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
                Button(words.delete, role: .destructive) {
                    navigation.leaveDeleted(card.id)
                    Task { await store.deleteHunt(id: card.id) }
                }
            } message: {
                Text(words.deleteMessage)
            }
    }

    private func setActive(_ active: Bool) {
        Task { await store.setActive(id: card.id, active: active) }
    }
}

extension View {
    /// A search's card with its long press (`HuntCardMenu`).
    func huntCardMenu(_ card: HuntCard, store: ArestemisStore, navigation: AppNavigation) -> some View {
        modifier(HuntCardMenu(card: card, store: store, navigation: navigation))
    }
}

/// The quiet line of a hunt the server reads less often for now (a site's budget or refusals).
struct SlowedLine: View {
    var body: some View {
        Text("Checked less often right now").font(AppFont.text(12)).foregroundStyle(Ink.muted)
    }
}

/// "● 4 NEW" (the accent dot as on the figures), nothing at 0.
struct NewCount: View {
    let count: Int

    var body: some View {
        if count > 0 {
            HStack(spacing: 6) {
                Circle().fill(Look.accent.color).frame(width: 5, height: 5)
                Text(verbatim: "\(count)").font(AppFont.number(13, weight: .semibold)).foregroundStyle(Ink.primary)
                CapsLabel(text: String(localized: "New"))
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(count) new"))
        }
    }
}

/// Start hunting / Start watching (the accent, the one primary action) or Pause (glass).
struct StartPauseButton: View {
    let active: Bool
    var kind: SearchKind? = nil
    let busy: Bool
    let height: CGFloat
    let toggle: (Bool) -> Void

    var body: some View {
        Group {
            if active {
                Button("Pause") { toggle(false) }.buttonStyle(ProvinceButtonStyle(kind: .glass, height: height))
            } else {
                Button(HuntWords(kind).start) { toggle(true) }
                    .buttonStyle(ProvinceButtonStyle(kind: .accent, height: height))
            }
        }
        .disabled(busy)
    }
}

/// A card that opens a page: a faint shade while pressed (as the rows of iOS's own lists).
struct CardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
                    .fill(configuration.isPressed ? Ink.press : .clear)
            }
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The figures under a hunt's card (`HuntPageActions.figures`): New, Today, Applied (Asked for things, Saved for a
/// watch); each opens those listings. Under them when the hunt was last read, unless the card says it (a watch's
/// "Checked …": `showsLastScan` false).
struct HuntFigures: View {
    let figures: [HuntFigure]
    let lastScan: String?
    var showsLastScan = true
    let show: (MatchFilter) -> Void

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                ForEach(Array(figures.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { divider }
                    figure(item.label, item.value, highlight: item.filter == .new && item.value > 0) { show(item.filter) }
                }
            }
            .padding(.vertical, 16)
            .glassCard()
            if showsLastScan {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    Text(lastScan.flatMap { Format.relative($0, now: context.date) }.map { String(localized: "Last scan \($0)") }
                         ?? String(localized: "No scan yet"))
                        .font(AppFont.number(11, weight: .regular)).foregroundStyle(Ink.muted)
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private func figure(_ label: String, _ value: Int, highlight: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(verbatim: "\(value)").font(AppFont.number(22, weight: .semibold)).foregroundStyle(Ink.primary)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.snappy, value: value)
                HStack(spacing: 5) {
                    if highlight { Circle().fill(Look.accent.color).frame(width: 5, height: 5) }
                    CapsLabel(text: label)
                }
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(label): \(value)"))
        .accessibilityHint("Shows these listings")
    }

    private var divider: some View {
        Rectangle().fill(Ink.line).frame(width: 1, height: 34)
    }
}

/// One row per portal: a status dot, the name, the server's note.
struct PortalsCard: View {
    let sources: [SourceStatus]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                if index > 0 { Hairline().padding(.leading, 34) }
                HStack(spacing: 12) {
                    Circle().fill(color(source.state)).frame(width: 6, height: 6)
                    Text(source.name).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                    Spacer(minLength: 10)
                    if let note = source.note {
                        Text(note).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .padding(.horizontal, 16).frame(minHeight: 48)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([source.name, word(source.state), source.note].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .glassCard()
    }

    private func color(_ state: SourceStatus.State) -> Color {
        switch state {
        case .ok: StatusTone.active.color(Look.accent)
        case .blocked, .error: StatusTone.issue.color(Look.accent)
        case .idle: StatusTone.inactive.color(Look.accent)
        }
    }

    private func word(_ state: SourceStatus.State) -> String {
        switch state {
        case .ok: String(localized: "working")
        case .blocked: String(localized: "blocked")
        case .error: String(localized: "not answering")
        case .idle: String(localized: "idle")
        }
    }
}

/// A few matches as cards (the Hunts tab's Latest, a hunt's page), each opening its page, with "All listings" under
/// them; or one quiet line while there are none (`empty`; a monitor's says its alarms).
struct LatestMatches: View {
    let matches: [Match]
    let store: ArestemisStore
    var empty: LocalizedStringKey = "No listings yet. They appear here the moment they're found."
    let open: (Int) -> Void
    let showAll: () -> Void

    var body: some View {
        if matches.isEmpty {
            Text(empty)
                .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        } else {
            VStack(spacing: Look.rowGap) {
                ForEach(matches) { match in
                    Button { open(match.id) } label: {
                        MatchRow(match: match, kind: store.kind(of: match), showsNewDot: store.showsNewDot(match),
                                 showsState: true, alarmShop: store.alarmShop(of: match))
                    }
                    .buttonStyle(.plain)
                    .contextMenu { MatchRowActions(match: match, store: store) }
                }
            }
            Button(action: showAll) {
                HStack(spacing: 5) {
                    Text("All listings")
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
                .font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.secondary)
                .frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 36)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
        }
    }
}

/// A titled part of the Hunts tab or a hunt's page.
struct HuntSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Look.headingGap) {
            SectionHeading(text: title).padding(.leading, 4)
            content
        }
        .padding(.top, Look.sectionGap)
    }
}
