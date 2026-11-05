import SwiftUI

/// A match as a glass card: the photo if there is one, the rent big, the facts, where and when it was found, a
/// chevron; the accent "new" dot in the corner until the match has been opened. A thing for sale shows its price big
/// (with "VB" or how far it lies over the maximum beside it; an auction its current bid, "bid" and the time left), its
/// title, one facts line (condition · shipping or pickup with the distance · place), and "Online at start" for one found
/// when the hunt started. A change on a watched page (brief 131) has no figure: the server's summary is its title, then
/// the host and when it was found ("Already true when the watch started" for one the start read found). A price
/// monitor's alarm (brief 137) is its sentence, "Nintendo Switch 2: €449.00 (was €483.99)" or "… is back in stock", then
/// the shop and when. In the search
/// over listings of every search, the search it belongs to stands over it (its kind's mark and name, brief 133).
struct MatchRow: View {
    let match: Match
    /// What the match is (`ArestemisStore.kind(of:)`): a flat, a thing for sale or a watched page's change.
    var kind: SearchKind = .flat
    var showsNewDot = false
    /// Shows SAVED / APPLIED (the "All" list and the Hunt tab, where states mix).
    var showsState = false
    /// With `showsState`, NEW too (the search over listings, where every state shows).
    var showsNewState = false
    /// The search the match belongs to, over it (the search over every search's listings).
    var hunt: HuntText? = nil
    /// An everywhere monitor's alarm names the shop of the cheapest offer (`ArestemisStore.alarmShop(of:)`, brief 157).
    var alarmShop: String? = nil

    private var thing: Bool { kind == .item }
    private var stateWord: String? {
        showsState ? match.state.word(thing: thing, includingNew: showsNewState) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let hunt { huntLine(hunt) }
            HStack(alignment: .center, spacing: 14) {
                if kind == .watch {
                    change
                } else if kind == .price {
                    alarm
                } else {
                    listing
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
                    .accessibilityHidden(true)
            }
        }
        .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .overlay(alignment: .topTrailing) {
            Circle().fill(Look.accent.color).frame(width: 7, height: 7)
                .shadow(color: Look.accent.color.opacity(0.6), radius: 4)
                .padding(11)
                .opacity(showsNewDot ? 1 : 0)
                .animation(.easeOut(duration: 0.6), value: showsNewDot)
                .accessibilityHidden(true)
        }
        .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityValue(showsNewDot ? "New" : "")
        .accessibilityAddTraits(.isButton)
    }

    /// The search the match belongs to: its kind's small mark and its name, quiet.
    private func huntLine(_ hunt: HuntText) -> some View {
        HStack(spacing: 5) {
            if let kind = hunt.kind {
                Image(systemName: kind.symbol).font(.system(size: 10, weight: .semibold))
            }
            Text(hunt.title).font(AppFont.text(11.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(Ink.muted)
    }

    /// A watched page's change: the summary, then the host and when.
    private var change: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(match.watchTitle).font(AppFont.text(16, weight: .semibold)).foregroundStyle(Ink.primary)
                    .lineSpacing(2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let word = stateWord {
                    CapsLabel(text: word, size: 9.5, color: Ink.secondary.opacity(0.8))
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(match.watchSourceLine(now: context.date))
                    .font(AppFont.text(11)).foregroundStyle(Ink.muted).lineLimit(1)
            }
        }
    }

    /// A monitor's alarm: its sentence, then the shop and when.
    private var alarm: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: match.priceTitle(shop: alarmShop, includingShippingNote: false))
                        .font(AppFont.text(16, weight: .semibold)).foregroundStyle(Ink.primary)
                        .lineSpacing(2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    if match.listing.priceChange?.shippingUnknown == true {
                        Text(verbatim: PriceWords.shippingUnknown()).font(AppFont.text(13)).foregroundStyle(Ink.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: match.priceTitle(shop: alarmShop)))
                Spacer(minLength: 8)
                if let word = stateWord {
                    CapsLabel(text: word, size: 9.5, color: Ink.secondary.opacity(0.8))
                }
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(match.priceSourceLine(now: context.date))
                    .font(AppFont.text(11)).foregroundStyle(Ink.muted).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var listing: some View {
        if let url = match.listing.imageURL.flatMap(URL.init(string:)) {
            ListingPhoto(url: url).frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous))
        }
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if thing { price } else { rent }
                Spacer(minLength: 8)
                if let word = stateWord {
                    CapsLabel(text: word, size: 9.5, color: Ink.secondary.opacity(0.8))
                }
            }
            .lineLimit(1)
            if thing {
                Text(match.listing.title).font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.primary)
                    .lineLimit(1)
            }
            let facts = thing ? match.listing.itemRowFacts() : match.listing.facts
            if !facts.isEmpty {
                Text(facts).font(AppFont.text(13)).foregroundStyle(Ink.secondary).lineLimit(1)
            }
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text(thing ? match.itemSourceLine(now: context.date) : match.sourceLine(now: context.date))
                    .font(AppFont.text(11)).foregroundStyle(Ink.muted).lineLimit(1)
            }
        }
    }

    @ViewBuilder private var rent: some View {
        if let rent = match.listing.shownRent {
            Text(rent.amount).font(AppFont.number(20, weight: .bold)).foregroundStyle(Ink.primary)
            Text(rent.label).font(AppFont.text(11)).foregroundStyle(Ink.muted)
        } else {
            Text("Rent not given").font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.secondary)
        }
    }

    @ViewBuilder private var price: some View {
        if match.listing.item?.auctionEnd != nil {
            // An auction's time left follows the clock.
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(alignment: .firstTextBaseline, spacing: 6) { price(now: context.date) }
            }
        } else {
            price(now: .now)
        }
    }

    @ViewBuilder private func price(now: Date) -> some View {
        if let price = match.itemPrice(now: now) {
            if let amount = price.amount {
                Text(amount).font(AppFont.number(20, weight: .bold)).foregroundStyle(Ink.primary)
                if let label = price.label { Text(label).font(AppFont.text(11)).foregroundStyle(Ink.muted) }
            } else if let label = price.label {
                // "Free", "VB", "Price on request": the word is the figure.
                Text(label).font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary)
            }
        } else {
            Text("Price not given").font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.secondary)
        }
    }
}

/// A listing's photo, with a quiet tile while it loads or when it fails.
struct ListingPhoto: View {
    let url: URL
    var radius: CGFloat = Ink.rowRadius

    var body: some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.25))) { phase in
            if let image = phase.image {
                image.resizable().scaledToFill()
            } else {
                Rectangle().fill(Ink.card2)
            }
        }
        .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(Ink.line))
        .accessibilityHidden(true)
    }
}

/// Shared by the Latest stack and the Listings tab's lists; the detail page uses these same state icons. A thing's seller is
/// asked, not applied to; a watched page's change and a monitor's alarm are only saved or dismissed.
struct MatchRowActions: View {
    let match: Match
    let store: ArestemisStore

    var body: some View {
        if match.state == .new {
            Button { change(.saved) } label: { Label("Save", systemImage: "bookmark") }
        }
        if match.state != .applied && match.state != .dismissed && store.kind(of: match).appliesOrAsks {
            Button { change(.applied) } label: {
                if store.isThing(match) { Label("Mark asked", systemImage: "checkmark.circle") }
                else { Label("Mark applied", systemImage: "checkmark.circle") }
            }
        }
        if match.state != .dismissed {
            Button { change(.dismissed) } label: { Label("Dismiss", systemImage: "xmark.circle") }
        }
    }

    private func change(_ state: MatchState) {
        Task { await store.setState(state, for: match.id) }
    }
}
