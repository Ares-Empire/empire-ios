import SwiftUI

/// One hunt on the Hunts tab: today's hunt card made compact. The kind's mark and the hunt's name with the new count
/// beside it, what it looks for in one or two lines, "checked less often" when the server reads it less often, then the
/// status line (the pulse while it runs, PAUSED otherwise) beside its Start / Pause, smaller. A watch shows its host under
/// its name, then what the page says now as its main fact (or a quiet line: reading, or why the page cannot be read) and
/// when it was checked and changed (`WatchLines`). Tapping the card opens the hunt's page; the button is its own (beside
/// the card's, not inside it). A hunt of a kind this build does not know shows its name and "Needs a newer app", nothing
/// else.
struct HuntListCard: View {
    let card: HuntCard
    /// The server's names for a thing hunt's sites.
    let sites: SiteNames
    let busy: Bool
    let open: () -> Void
    let toggle: (Bool) -> Void

    var body: some View {
        let text = HuntText(card.hunt, page: card.page, sites: sites)
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
                    if card.slowed && known {
                        SlowedLine().padding(.top, 6)
                    }
                    if known {
                        // The status line; its button sits on this row's right, outside this label.
                        HuntStatus(active: card.hunt.active, kind: text.kind)
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .padding(.top, 12)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
            }
            .buttonStyle(CardPressStyle())
            .accessibilityHint(text.kind == .watch ? Text("Opens the watch") : Text("Opens the search"))
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

/// The hunt's card on its page: today's hunt card for any kind. Status, the name in big, what it looks for (a watch: its
/// host, what the page says now and when it was checked and changed), and the one button (Start hunting / Start watching
/// / Pause); for a kind this build does not know only its name and "Needs a newer app".
struct HuntHeroCard: View {
    let card: HuntCard
    let sites: SiteNames
    let busy: Bool
    let toggle: (Bool) -> Void

    var body: some View {
        let text = HuntText(card.hunt, page: card.page, sites: sites)
        VStack(alignment: .leading, spacing: 0) {
            if text.kind != nil {
                HuntStatus(active: card.hunt.active, kind: text.kind).padding(.bottom, 14)
            }
            HuntTitle(text: text, size: 20)
            if let line = text.details ?? text.newerApp {
                Text(line).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            if text.kind == .watch {
                WatchLines(page: card.page, compact: false).padding(.top, 14)
            }
            if card.slowed && text.kind != nil {
                SlowedLine().padding(.top, 8)
            }
            if text.kind != nil {
                StartPauseButton(active: card.hunt.active, kind: text.kind, busy: busy, height: 50, toggle: toggle)
                    .padding(.top, 20)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: Look.accent, raised: true)
        .animation(.easeOut(duration: 0.2), value: card.hunt.active)
    }
}

/// "● HUNTING" (a watch: "● WATCHING") with the pulse, or "● PAUSED" in grey.
struct HuntStatus: View {
    let active: Bool
    var kind: SearchKind? = nil

    var body: some View {
        HStack(spacing: 9) {
            StatusDot(active: active)
            StatusLabel(text: HuntWords(kind).status(active: active), tone: active ? .accent : .inactive,
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

/// The kind's small mark (a house, a tag; muted ink) and the hunt's name.
struct HuntTitle: View {
    let text: HuntText
    let size: CGFloat

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: size > 18 ? 9 : 7) {
            if let kind = text.kind {
                Image(systemName: kind.symbol).font(.system(size: size * 0.72, weight: .medium))
                    .foregroundStyle(Ink.muted)
                    .accessibilityLabel(Text(verbatim: kind == .flat ? String(localized: "Flat") : kind.choiceTitle()))
            }
            Text(text.title).font(AppFont.text(size, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
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
/// them; or one quiet line while there are none.
struct LatestMatches: View {
    let matches: [Match]
    let store: ArestemisStore
    let open: (Int) -> Void
    let showAll: () -> Void

    var body: some View {
        if matches.isEmpty {
            Text("No listings yet. They appear here the moment they're found.")
                .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 4)
        } else {
            VStack(spacing: Look.rowGap) {
                ForEach(matches) { match in
                    Button { open(match.id) } label: {
                        MatchRow(match: match, kind: store.kind(of: match), showsNewDot: store.showsNewDot(match),
                                 showsState: true)
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
