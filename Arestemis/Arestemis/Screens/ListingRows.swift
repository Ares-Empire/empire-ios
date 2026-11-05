import SwiftUI

/// The rows the Listings tab's lists share (brief 133): New, one search's listings, Recently viewed and the search over
/// listings.

/// A match as a row of a list: a tap opens its page, a swipe right makes a new one a favorite (the state `saved`, brief
/// 180), a swipe left dismisses it (with Undo in the bar), the long press offers the same.
struct ListingRow: View {
    let match: Match
    let store: ArestemisStore
    /// FAVORITE / APPLIED on the row (lists where states mix).
    var showsState = false
    /// NEW too (the search over listings).
    var showsNewState = false
    /// The search it belongs to, over it (the search over every search's listings).
    var hunt: HuntText? = nil
    /// What the tour may point at here (New's rows, brief 139).
    var spot: TourSpot? = nil
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            MatchRow(match: match, kind: store.kind(of: match), showsNewDot: store.showsNewDot(match),
                     showsState: showsState, showsNewState: showsNewState, hunt: hunt,
                     alarmShop: store.alarmShop(of: match))
                .tourAnchor(spot)
        }
        .buttonStyle(.plain)
        .contextMenu { MatchRowActions(match: match, store: store) }
        .plainRow(vertical: Look.rowGap / 2)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if match.state == .new {
                Button { Task { await store.setState(.saved, for: match.id) } } label: {
                    Label("Favorite", systemImage: "star")
                }
                .tint(Look.accent.deep)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button { Task { await store.setState(.dismissed, for: match.id) } } label: {
                Label("Dismiss", systemImage: "xmark")
            }
            .tint(Color(hex: 0x4B4E58))
        }
        .accessibilityAction(named: "Favorite") { Task { await store.setState(.saved, for: match.id) } }
        .accessibilityAction(named: "Dismiss") { Task { await store.setState(.dismissed, for: match.id) } }
    }
}

/// The heading over one search's new listings in New: its kind's mark and name, how many of them are unread (brief 180:
/// a listing opened stays in the group without its dot, and leaves the count), a chevron; a tap opens that search's
/// listings at New. At the accessibility text sizes the count goes under the name, which keeps the width.
struct NewGroupHeading: View {
    let kind: SearchKind?
    let title: String
    let count: Int
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: open) {
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        HuntTitle(kind: kind, title: title, size: 15)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            NewCount(count: count)
                            chevron
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        HuntTitle(kind: kind, title: title, size: 15)
                        Spacer(minLength: 8)
                        NewCount(count: count)
                        chevron
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(minHeight: 36)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        // Every listing of the group read: its name alone, as the count shows nothing then.
        .accessibilityLabel(Text(verbatim: count > 0 ? "\(title), \(String(localized: "\(count) new"))" : title))
        .accessibilityAddTraits([.isHeader, .isButton])
        .accessibilityHint("Shows these listings")
    }

    private var chevron: some View {
        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Ink.muted)
    }
}

/// One search in Searches, as a glass card: its kind's mark and name with the new count beside it (under it at the
/// accessibility text sizes), favorites and applied (asked) in a quiet line, a chevron. A tap opens its listings.
struct SearchRowCard: View {
    let row: SearchRow
    let open: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Button(action: open) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    if typeSize.isAccessibilitySize {
                        HuntTitle(text: row.text, size: 16)
                        if let count = row.newCount, count > 0 { NewCount(count: count) }
                    } else {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            HuntTitle(text: row.text, size: 16)
                            Spacer(minLength: 8)
                            if let count = row.newCount { NewCount(count: count) }
                        }
                    }
                    if let line = row.line {
                        Text(line).font(AppFont.text(13)).foregroundStyle(Ink.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Ink.muted)
            }
            .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 15)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: row.spoken()))
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Shows these listings")
    }
}

/// The quiet row at the end of a list (`QuietLink`, brief 182): Recently viewed and Filtered out, of every search or of
/// one, in one look: an outline, the symbol, the words and the count in muted ink, a chevron; a tap opens those listings.
struct QuietLinkRow: View {
    let link: QuietLink
    /// What the tour may point at here (Filtered out, brief 139).
    var spot: TourSpot? = nil
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            HStack(spacing: 6) {
                Image(systemName: link.symbol).font(.system(size: 12, weight: .medium))
                    .frame(width: 18, alignment: .leading)
                Text(verbatim: "\(link.title()) ·")
                Text(verbatim: link.countText).font(AppFont.number(13, weight: .regular))
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
            }
            .font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.muted)
            .padding(.horizontal, 16).frame(minHeight: 46)
            .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.line))
            .contentShape(Rectangle())
            .tourAnchor(spot)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: link.spoken()))
        // Room above each, none under: two of them stand together as a pair at the list's end.
        .plainRow(top: 10, bottom: 0)
    }
}

/// While a list has more pages: a small spinner that asks for the next one as it comes into view, or the failure with
/// Try again.
struct MoreRow: View {
    let error: String?
    /// The list's last id: a new page starts a new request.
    let last: Int?
    let load: () async -> Void

    var body: some View {
        Group {
            if let error {
                CalmMessage(text: error, action: (String(localized: "Try again"), { Task { await load() } }))
            } else {
                ProgressView().controlSize(.small).tint(Ink.muted)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .plainRow()
        .task(id: last) {
            guard error == nil else { return }
            await load()
        }
    }
}

extension View {
    /// A list row without the list's look: no background, no separator, the app's side margins.
    func plainRow(vertical: CGFloat = 0) -> some View {
        plainRow(top: vertical, bottom: vertical)
    }

    /// The same with its own room above and under. The section's separator goes too: a plain list draws one under its
    /// last row (brief 182: a line under Filtered out at the end of New).
    func plainRow(top: CGFloat, bottom: CGFloat) -> some View {
        listRowInsets(EdgeInsets(top: top, leading: Look.side, bottom: bottom, trailing: Look.side))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listSectionSeparator(.hidden)
    }

    /// The Listings tab's lists: plain, on the wall, their top fading under what stands above them.
    func listingsList() -> some View {
        listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollIndicators(.hidden)
            .contentMargins(.top, 10, for: .scrollContent)
            .contentMargins(.bottom, 24, for: .scrollContent)
            .edgeFade(top: 14)
    }
}
