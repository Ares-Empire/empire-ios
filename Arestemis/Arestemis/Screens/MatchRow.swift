import SwiftUI

/// A match as a glass card: the photo if there is one, the rent big, the facts, where and when it was found, a
/// chevron; the accent "new" dot in the corner until the match has been opened.
struct MatchRow: View {
    let match: Match
    var showsNewDot = false
    /// Shows SAVED / APPLIED (the "All" list and the Hunt tab, where states mix).
    var showsState = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            if let url = match.listing.imageURL.flatMap(URL.init(string:)) {
                ListingPhoto(url: url).frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let rent = match.listing.shownRent {
                        Text(rent.amount).font(AppFont.number(20, weight: .bold)).foregroundStyle(Ink.primary)
                        Text(rent.label).font(AppFont.text(11)).foregroundStyle(Ink.muted)
                    } else {
                        Text("Rent not given").font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.secondary)
                    }
                    Spacer(minLength: 8)
                    if showsState, let word = match.state.word {
                        CapsLabel(text: word, size: 9.5, color: Ink.secondary.opacity(0.8))
                    }
                }
                .lineLimit(1)
                if !match.listing.facts.isEmpty {
                    Text(match.listing.facts).font(AppFont.text(13)).foregroundStyle(Ink.secondary).lineLimit(1)
                }
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(match.sourceLine(now: context.date)).font(AppFont.text(11)).foregroundStyle(Ink.muted).lineLimit(1)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
                .accessibilityHidden(true)
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
}

extension MatchState {
    /// The word a row shows for a state that is not obvious from the list it is in.
    var word: String? {
        switch self {
        case .saved: String(localized: "Saved")
        case .applied: String(localized: "Applied")
        case .new, .dismissed: nil
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

/// Shared by the Latest stack and the Listings list; the detail page uses these same state icons.
struct MatchRowActions: View {
    let match: Match
    let store: ArestemisStore

    var body: some View {
        if match.state == .new {
            Button { change(.saved) } label: { Label("Save", systemImage: "bookmark") }
        }
        if match.state != .applied && match.state != .dismissed {
            Button { change(.applied) } label: { Label("Mark applied", systemImage: "checkmark.circle") }
        }
        if match.state != .dismissed {
            Button { change(.dismissed) } label: { Label("Dismiss", systemImage: "xmark.circle") }
        }
    }

    private func change(_ state: MatchState) {
        Task { await store.setState(state, for: match.id) }
    }
}
