import SwiftUI

/// Not checked in time (brief 187; the server's brief 186): the thing listings of every search (from the row in New) or
/// of one (from the row on its listings) that the server could not check within 24 hours, kept 7 days so nothing
/// vanishes unseen. One quiet line on top says what they are, then the listings, the newest first (the server's order),
/// each in a quiet outlined row (`NotCheckedRow`): no photo, no swipes, no star, since they are not matches. A tap opens
/// the listing on its site as a listing's Open does; one without a link opens nothing. Over every search each row names
/// its search (unless the account has one). Loading, empty and failure as Recently viewed; pull to refresh.
struct NotCheckedListingsPage: View {
    let hunt: Int?
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation

    var body: some View {
        List {
            Text(NotCheckedWords.line())
                .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4).padding(.bottom, 6)
                .plainRow()
            content
        }
        .listingsList()
        .refreshable {
            async let list: Void = store.loadNotChecked(hunt: hunt)
            async let overview: Void = store.reloadOverview(quiet: true)
            _ = await (list, overview)
        }
        .provinceWall()
        .navigationTitle(NotCheckedWords.title())
        .navigationBarTitleDisplayMode(.inline)
        // Loaded with New or the search's listings; asked again as the page opens, so it shows what the server keeps now
        // (the count on the row that opened it may be newer than the list).
        .task { await store.loadNotChecked(hunt: hunt) }
    }

    @ViewBuilder private var content: some View {
        let list = store.notChecked(hunt: hunt)
        if list.items.isEmpty {
            Group {
                if let error = list.error {
                    CalmMessage(text: error, action: (String(localized: "Try again"), {
                        Task { await store.loadNotChecked(hunt: hunt) }
                    }))
                } else if !list.loaded {
                    CalmMessage(text: String(localized: "Loading listings…"), loading: true)
                } else {
                    CalmMessage(text: NotCheckedWords.empty())
                }
            }
            .padding(.top, 20)
            .plainRow()
        } else {
            // Over every search, each row names its search (unless the account has one).
            let names = hunt == nil && store.hunts.count > 1
            ForEach(list.items) { item in
                NotCheckedRow(item: item, hunt: names ? text(of: item) : nil)
                    .plainRow(vertical: Look.rowGap / 2)
            }
        }
    }

    private func text(of item: NotChecked) -> HuntText? {
        store.card(item.huntID).map { HuntText($0, sites: store.siteNames) }
    }
}

/// One listing not checked in time: the search it belongs to (over every search), the title (muted "Untitled" when the
/// site gave none) with an arrow when it opens, and one quiet line with the price, the site and when its search first saw
/// it. Drawn in the quiet rows' outline (`QuietLinkRow`) rather than as a glass card, so it sits beside the listings
/// without passing for one. A tap opens the listing on its site in the browser, as a listing's Open on <site> does.
struct NotCheckedRow: View {
    let item: NotChecked
    /// The search it belongs to, over it (the list of every search).
    var hunt: HuntText? = nil
    @Environment(\.openURL) private var openURL

    var body: some View {
        if let link = item.link {
            Button { openURL(link) } label: { label(opens: true) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("Opens the listing on \(item.sourceName)"))
        } else {
            label(opens: false)
        }
    }

    private func label(opens: Bool) -> some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 6) {
                if let hunt {
                    HStack(spacing: 5) {
                        if let kind = hunt.kind {
                            Image(systemName: kind.symbol).font(.system(size: 10, weight: .semibold))
                        }
                        Text(hunt.title).font(AppFont.text(11.5, weight: .medium)).lineLimit(1)
                    }
                    .foregroundStyle(Ink.muted)
                }
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(item.shownTitle()).font(AppFont.text(15, weight: .semibold))
                        .foregroundStyle(item.hasTitle ? Ink.primary : Ink.muted)
                        .lineLimit(2).multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if opens {
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.muted)
                    }
                }
                Text(item.line(now: context.date)).font(AppFont.text(12.5)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            .padding(.leading, 16).padding(.trailing, 14).padding(.vertical, 13)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.line))
            .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: [hunt?.title, item.spoken(now: context.date)].compactMap { $0 }
                .joined(separator: ", ")))
        }
    }
}
