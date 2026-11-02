import SwiftUI

/// One match: the rent big, the title, the facts grid, why the AI let it through (and what to check), the
/// description; at the bottom "Open on <portal>" and "Application". The menu sets the state. A thing for sale: its
/// price big (with "VB" or how far it lies over the maximum; an auction its current bid and the time left), its facts
/// (an auction's bids and end, condition, delivery, shipping cost, distance, seller, place, posted), and only "Open on
/// <site>" (the server's name: "Open on eBay"), as the one main button; its seller is "Asked", not applied to. A change
/// on a watched page (brief 131): the server's summary as the title, "Now: …", the host and when, then the lines that
/// came and went (the removed ones labelled and struck through, not told apart by colour alone), and "Open page" (the
/// watched address) as the one main button; its menu only saves or dismisses.
struct MatchDetailScreen: View {
    let id: Int
    let store: ArestemisStore
    let navigation: AppNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let match = store.match(id) {
                page(match)
            } else if let error = store.matchErrors[id] {
                CalmMessage(text: error, action: (String(localized: "Try again"), { Task { await store.loadMatch(id) } }))
                    .frame(maxHeight: .infinity)
            } else {
                CalmMessage(text: String(localized: "Loading the listing…"), loading: true).frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .provinceWall()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let match = store.match(id), match.state != .dismissed {
                ToolbarItem(placement: .topBarTrailing) { stateMenu(match) }
            }
        }
        .task {
            await store.loadMatch(id)
            try? await Task.sleep(for: .milliseconds(400))
            store.markSeen(id)
        }
    }

    private func page(_ match: Match) -> some View {
        let listing = match.listing
        return VStack(spacing: 0) {
          ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let url = listing.imageURL.flatMap(URL.init(string:)) {
                    Color.clear.aspectRatio(16 / 10, contentMode: .fit)
                        .overlay { ListingPhoto(url: url, radius: Ink.cardRadius) }
                        .clipShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
                        .padding(.bottom, 22)
                }
                let kind = store.kind(of: match)
                if kind == .watch {
                    watchHero(match)
                    if let change = listing.page, !change.added.isEmpty || !change.removed.isEmpty {
                        SectionHeading(text: String(localized: "What changed")).padding(.leading, 4)
                            .padding(.top, Look.sectionGap)
                        ChangedLines(change: change).padding(.top, Look.headingGap)
                    }
                } else {
                    let thing = kind == .item
                    hero(match, thing: thing)
                    let facts = thing ? listing.itemDetailFacts() : listing.detailFacts()
                    if !facts.isEmpty { FactsGrid(facts: facts).padding(.top, 22) }
                    SectionHeading(text: String(localized: "Why it fits")).padding(.leading, 4).padding(.top, Look.sectionGap)
                    WhyItFits(reason: match.reason, warnings: match.warnings).padding(.top, Look.headingGap)
                    if !listing.description.isEmpty {
                        SectionHeading(text: String(localized: "Description")).padding(.leading, 4).padding(.top, Look.sectionGap)
                        ExpandableText(text: listing.description).padding(.top, Look.headingGap).padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, Look.side).padding(.top, 6).padding(.bottom, 28)
        }
          .scrollIndicators(.hidden)
          .edgeFade(bottom: 22)
          actions(match)
        }
    }

    private func hero(_ match: Match, thing: Bool) -> some View {
        let listing = match.listing
        return VStack(alignment: .leading, spacing: 0) {
            if thing {
                if listing.item?.auctionEnd != nil {
                    // An auction's time left follows the clock.
                    TimelineView(.periodic(from: .now, by: 30)) { context in thingPrice(match, now: context.date) }
                } else {
                    thingPrice(match, now: .now)
                }
            } else if let rent = listing.shownRent {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rent.amount).font(AppFont.number(34, weight: .bold)).foregroundStyle(Ink.primary)
                        .minimumScaleFactor(0.7)
                    Text(rent.label).font(AppFont.text(13)).foregroundStyle(Ink.muted)
                }
                .lineLimit(1)
                if listing.rentWarm != nil, let cold = listing.rentCold {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(Format.money(cold)).font(AppFont.number(13, weight: .regular))
                        Text("cold").font(AppFont.text(13))
                    }
                    .foregroundStyle(Ink.muted)
                    .padding(.top, 2)
                }
            }
            Text(listing.title).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(thing ? match.itemSourceLine(now: context.date) : match.sourceLine(now: context.date))
                        .font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
                if let word = match.state.word(thing: thing) {
                    Text("·").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    CapsLabel(text: word, size: 10, color: Ink.secondary)
                }
            }
            .padding(.top, 6)
        }
        .accessibilityElement(children: .combine)
    }

    /// A watched page's change: the summary as the title, what the page says now, the host and when it was found.
    private func watchHero(_ match: Match) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(match.watchTitle).font(AppFont.text(22, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            if let now = match.watchNowLine() {
                Text(now).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(match.watchSourceLine(now: context.date)).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let word = match.state.word() {
                    Text("·").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    CapsLabel(text: word, size: 10, color: Ink.secondary)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func thingPrice(_ match: Match, now: Date) -> some View {
        if let price = match.itemPrice(now: now) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let amount = price.amount {
                    Text(amount).font(AppFont.number(34, weight: .bold)).foregroundStyle(Ink.primary)
                        .minimumScaleFactor(0.7)
                    if let label = price.label { Text(label).font(AppFont.text(13)).foregroundStyle(Ink.muted) }
                } else if let label = price.label {
                    Text(label).font(AppFont.text(28, weight: .bold)).foregroundStyle(Ink.primary)
                        .minimumScaleFactor(0.7)
                }
            }
            .lineLimit(1)
        }
    }

    private func actions(_ match: Match) -> some View {
        let kind = store.kind(of: match)
        return HStack(spacing: 10) {
            Group {
                if kind == .watch {
                    Button("Open page") { if let url = match.listing.portalURL { openURL(url) } }
                } else {
                    Button("Open on \(match.listing.sourceName)") { if let url = match.listing.portalURL { openURL(url) } }
                }
            }
            .buttonStyle(ProvinceButtonStyle(kind: kind == .flat ? .glass : .accent))
            .disabled(match.listing.portalURL == nil)
            if kind == .flat {
                Button("Application") { navigation.sheet = .application(match.id) }
                    .buttonStyle(.accent)
                    .frame(width: 142)
            }
        }
        .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 6)
    }

    private func stateMenu(_ match: Match) -> some View {
        Menu {
            Toggle(isOn: stateBinding(match, .saved)) { Label("Save", systemImage: "bookmark") }
            if store.kind(of: match) != .watch {
                Toggle(isOn: stateBinding(match, .applied)) {
                    if store.isThing(match) { Label("Mark asked", systemImage: "checkmark.circle") }
                    else { Label("Mark applied", systemImage: "checkmark.circle") }
                }
            }
            Toggle(isOn: stateBinding(match, .dismissed)) { Label("Dismiss", systemImage: "xmark.circle") }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(Ink.primary)
        .accessibilityLabel("Listing state")
    }

    /// Checked = the current state; choosing another state sets it (dismissing also goes back to the list).
    private func stateBinding(_ match: Match, _ state: MatchState) -> Binding<Bool> {
        Binding(get: { store.match(id)?.state == state }, set: { on in
            guard on else { return }
            Task { await store.setState(state, for: match.id) }
            if state == .dismissed { dismiss() }
        })
    }
}

/// Two columns of label over value.
private struct FactsGrid: View {
    let facts: [ListingFact]

    var body: some View {
        let rows = stride(from: 0, to: facts.count, by: 2).map { Array(facts[$0..<min($0 + 2, facts.count)]) }
        Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 18) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { fact in cell(fact) }
                    if row.count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private func cell(_ fact: ListingFact) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            CapsLabel(text: fact.label)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(fact.value)
                    .font(fact.numeric ? AppFont.number(15, weight: .medium) : AppFont.text(15, weight: .medium))
                if let unit = fact.unit { Text(unit).font(AppFont.text(14)).foregroundStyle(Ink.secondary) }
            }
            .foregroundStyle(Ink.primary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A watched page's change: the lines that came ("Added") and the lines that went ("Removed", muted and struck
/// through), each group under its label, so they are told apart by more than colour; selectable, to copy a line.
private struct ChangedLines: View {
    let change: PageChange

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !change.added.isEmpty {
                group(String(localized: "Added"), change.added, removed: false)
            }
            if !change.added.isEmpty && !change.removed.isEmpty {
                Hairline().padding(.vertical, 16)
            }
            if !change.removed.isEmpty {
                group(String(localized: "Removed"), change.removed, removed: true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .textSelection(.enabled)
    }

    private func group(_ label: String, _ lines: [String], removed: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            CapsLabel(text: label)
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(AppFont.text(14)).foregroundStyle(removed ? Ink.muted : Ink.primary)
                    .strikethrough(removed, color: Ink.muted)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// The AI's reason, and each thing to check with an amber triangle; the card has the accent edge.
private struct WhyItFits: View {
    let reason: String
    let warnings: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(reason).font(AppFont.text(15)).foregroundStyle(Ink.primary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(warnings, id: \.self) { warning in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Look.amber)
                    Text(warning).font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Check: \(warning)")
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: Look.accent)
    }
}

/// Six lines of text; "More" shows the rest (only when there is more).
struct ExpandableText: View {
    let text: String
    var lines = 6
    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var shortHeight: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            styled(Text(text))
                .lineLimit(expanded ? nil : lines)
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { if !expanded { shortHeight = $0 } }
                .background {
                    // The whole text, measured off screen, tells whether there is more to show.
                    styled(Text(text)).fixedSize(horizontal: false, vertical: true).hidden()
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fullHeight = $0 }
                }
                .textSelection(.enabled)
            if !expanded && fullHeight > shortHeight + 1 {
                Button("More") { withAnimation(.easeOut(duration: 0.25)) { expanded = true } }
                    .buttonStyle(.quiet)
            }
        }
    }

    private func styled(_ text: Text) -> some View {
        text.font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(4)
    }
}
