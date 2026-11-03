import SwiftUI

/// One match. A flat or a thing reads like a listing on its site (brief 142): the figure big (a flat's rent: warm, else
/// cold; a thing's price with "VB" or how far it lies over the maximum, an auction's current bid and the time left), the
/// title, the site and when it was found; then one card of facts as a portal lists them (`Listing.detailFacts`,
/// `itemDetailFacts`: every fact the search asks about, a quiet "–" where the listing does not say) with the AI's
/// warnings at its foot as short notes "To check"; then the description in full, and when it is only the site's preview
/// one quiet line that opens the listing. At the bottom "Open on <site>" in the accent fill, the main button; a flat's
/// application text under it as the quiet second one (`ListingButton`). Why the AI let it through is not on the page:
/// it fits because of the search. The menu sets the state; a thing's seller is "Asked", not applied to. A change on a
/// watched page (brief 131): the server's summary as the title, "Now: …", the host and when, then the lines that came
/// and went (the removed ones labelled and struck through, not told apart by colour alone), and "Open page" (the watched
/// address) as the one main button; its menu only saves or dismisses. A monitor's alarm (brief 137): the new price big
/// with the old one beside it ("was €483.99"; "back in stock" when it came back), the product, the shop and when, and
/// "Open in shop" as the one main button; its menu only saves or dismisses.
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
        .tourSpotlight()
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
                if kind == .price {
                    priceHero(match)
                } else if kind == .watch {
                    watchHero(match)
                    if let change = listing.page, !change.added.isEmpty || !change.removed.isEmpty {
                        SectionHeading(text: String(localized: "What changed")).padding(.leading, 4)
                            .padding(.top, Look.sectionGap)
                        ChangedLines(change: change).padding(.top, Look.headingGap)
                    }
                } else {
                    let thing = kind == .item
                    hero(match, thing: thing)
                    // The facts the listing's search asks about are always there (`detailFacts(search:)`).
                    let search = store.card(match.huntID)?.hunt.search
                    let facts = thing ? listing.itemDetailFacts(search: search?.item)
                        : listing.detailFacts(search: search?.flat)
                    FactsCard(facts: facts, checks: match.checks).tourAnchor(.listingFacts).padding(.top, 22)
                    if !listing.description.isEmpty {
                        SectionHeading(text: String(localized: "Description")).padding(.leading, 4).padding(.top, Look.sectionGap)
                        // The whole text, never cut: what the site gave is all there is to read here.
                        Text(listing.description).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                            .padding(.top, Look.headingGap).padding(.horizontal, 4)
                        if let line = listing.previewLine() {
                            PreviewLine(text: line) { if let url = listing.portalURL { openURL(url) } }
                                .disabled(listing.portalURL == nil)
                                .padding(.top, 6)
                        }
                    }
                }
            }
            .padding(.horizontal, Look.side).padding(.top, 6).padding(.bottom, 28)
        }
          .scrollIndicators(.hidden)
          .tourScrollsToTarget()
          // Scrolled, the listing fades out under the bar with the back button and the menu (brief 139: its title ran
          // on under them), as the tabs' lists do under their headers: the wall's fade, not iOS's own edge effect, which
          // shows a blurred copy of the content in the bar that no wall covers.
          .scrollEdgeEffectHidden(true, for: .top)
          .edgeFade(top: 14, bottom: 22, underBar: true)
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
                // The other rent is the first fact (`detailFacts`), with a dash when the listing does not give it.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(rent.amount).font(AppFont.number(34, weight: .bold)).foregroundStyle(Ink.primary)
                        .minimumScaleFactor(0.7)
                    Text(rent.label).font(AppFont.text(13)).foregroundStyle(Ink.muted)
                }
                .lineLimit(1)
            } else {
                Text("Rent not given").font(AppFont.text(22, weight: .semibold)).foregroundStyle(Ink.secondary)
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

    /// A monitor's alarm: the new price big, the old one beside it (or "back in stock"), the product, the shop and when.
    private func priceHero(_ match: Match) -> some View {
        let change = match.listing.priceChange
        return VStack(alignment: .leading, spacing: 0) {
            if let change {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: PriceWords.money(change.new, currency: change.currency))
                        .font(AppFont.number(34, weight: .bold)).foregroundStyle(Ink.primary).minimumScaleFactor(0.7)
                    Text(verbatim: PriceWords.alarmLabel(change)).font(AppFont.text(13)).foregroundStyle(Ink.muted)
                }
                .lineLimit(1)
            }
            Text(match.listing.title).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
            HStack(spacing: 10) {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(match.priceSourceLine(now: context.date)).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
                if let word = match.state.word() {
                    Text("·").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    CapsLabel(text: word, size: 10, color: Ink.secondary)
                }
            }
            .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: match.priceTitle(shop: store.alarmShop(of: match))))
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

    /// "Open on <site>" (or the page, or the shop) in the accent fill, the main button; a flat's application text under
    /// it as the quiet second one, named for what it gives.
    private func actions(_ match: Match) -> some View {
        let buttons = ListingButton.buttons(for: store.kind(of: match), site: match.listing.sourceName)
        return VStack(spacing: 2) {
            ForEach(buttons, id: \.self) { button in
                if button.opensListing {
                    Button(button.title()) { if let url = match.listing.portalURL { openURL(url) } }
                        .buttonStyle(.accent)
                        .disabled(match.listing.portalURL == nil)
                } else {
                    Button { navigation.sheet = .application(match.id) } label: {
                        Label(button.title(), systemImage: button.symbol ?? "doc.text")
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.quiet)
                }
            }
        }
        .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 2)
    }

    private func stateMenu(_ match: Match) -> some View {
        Menu {
            Toggle(isOn: stateBinding(match, .saved)) { Label("Save", systemImage: "bookmark") }
            if store.kind(of: match).appliesOrAsks {
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

/// The listing's facts as two columns of label over value, a quiet "–" for each the listing does not state; at the foot,
/// after a hairline, what the check could not confirm ("To check"), each with a light question mark, never an alarm
/// colour.
private struct FactsCard: View {
    let facts: [ListingFact]
    let checks: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !facts.isEmpty { grid }
            if !checks.isEmpty {
                if !facts.isEmpty { Hairline().padding(.vertical, 18) }
                toCheck
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    private var grid: some View {
        let rows = stride(from: 0, to: facts.count, by: 2).map { Array(facts[$0..<min($0 + 2, facts.count)]) }
        return Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 18) {
            ForEach(rows, id: \.first?.id) { row in
                GridRow {
                    ForEach(row) { fact in cell(fact) }
                    if row.count == 1 { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                }
            }
        }
    }

    private func cell(_ fact: ListingFact) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            CapsLabel(text: fact.label)
            if let value = fact.value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value)
                        .font(fact.numeric ? AppFont.number(15, weight: .medium) : AppFont.text(15, weight: .medium))
                    if let unit = fact.unit { Text(unit).font(AppFont.text(14)).foregroundStyle(Ink.secondary) }
                }
                .foregroundStyle(Ink.primary).lineLimit(2)
            } else {
                Text(verbatim: ListingFact.dash).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.muted)
                    .accessibilityLabel(Text(verbatim: ListingFact.notStated()))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var toCheck: some View {
        VStack(alignment: .leading, spacing: 10) {
            CapsLabel(text: String(localized: "To check"))
            ForEach(checks, id: \.self) { check in
                HStack(alignment: .firstTextBaseline, spacing: 9) {
                    Image(systemName: "questionmark.circle").font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Ink.muted)
                    Text(check).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Check: \(check)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Under a description that is only the site's preview: one quiet line, which opens the listing on the site.
private struct PreviewLine: View {
    let text: String
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(text).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
            }
            .font(AppFont.text(13)).foregroundStyle(Ink.muted)
            .padding(.horizontal, 4).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isLink)
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
