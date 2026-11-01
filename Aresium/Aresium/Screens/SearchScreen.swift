import SwiftUI

/// The search (brief 77): pushed on the dashboard's stack from the magnifying glass in the start screen's header (phone
/// mode), under the header with its arrow (the back swipe works too). The field at the top in Apple's search field
/// look, in the app's ink, with the keyboard up as the page opens. Before typing: one quiet line on what it finds and
/// the names of the newest payments, so the likely ones are a tap away. While typing: the names brief 76 ranks best
/// first (`DashboardStore.searchNames`), each a row that opens the name's page; back from it the query is still there.
/// Nothing matches: one quiet line.
struct SearchScreen: View {
    let store: DashboardStore
    let palette: Palette
    let band: AresiumBand
    /// A name's page, pushed on the dashboard's stack.
    let pick: (DashboardRoute) -> Void
    #if DEBUG
    /// Screenshots: `-searchText <text>` types it.
    @State private var query = LaunchArguments.value("-searchText") ?? ""
    #else
    @State private var query = ""
    #endif
    @FocusState private var focused: Bool
    /// The keyboard comes up once, as the page opens; back from a name's page it stays down, the results in view.
    @State private var focusedOnce = false

    var body: some View {
        VStack(spacing: 0) {
            DashboardStatus(store: store, palette: palette)
            SearchField(text: $query, prompt: SearchPage.prompt(), palette: palette, focused: $focused)
                .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 8)
            WordmarkScrollView {
                content.padding(.top, 4)
            } band: { _ in band }
            .scrollBounceBehavior(.always)
            .scrollDismissesKeyboard(.immediately)
        }
        .task {
            guard !focusedOnce else { return }
            focusedOnce = true
            #if DEBUG
            if LaunchArguments.current.contains("-searchKeyboardDown") { return }
            #endif
            focused = true
        }
    }

    @ViewBuilder private var content: some View {
        let typed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if typed.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: SearchPage.hint()).font(AppFont.text(13)).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 18)
                let latest = store.latestNames()
                if !latest.isEmpty {
                    Text(verbatim: SearchPage.latestHeading().uppercased()).font(AppFont.text(11, weight: .semibold))
                        .tracking(1.3).foregroundStyle(palette.muted)
                        .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 2)
                        .accessibilityAddTraits(.isHeader)
                    rows(latest)
                }
            }
        } else {
            let results = store.searchNames(typed)
            if results.isEmpty {
                EmptyMessage(text: SearchPage.noMatch(typed), palette: palette)
            } else {
                rows(results)
            }
        }
    }

    private func rows(_ results: [NameSearchResult]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(results) { result in
                Button { open(result) } label: {
                    NameResultRow(result: result, store: store, palette: palette)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
    }

    /// A result: its name's page (the keyboard goes first, so it is down when the page comes back).
    private func open(_ result: NameSearchResult) {
        focused = false
        pick(DashboardRoute(name: PaymentNameRoute(key: result.key, title: result.shownName)))
    }
}

/// A search field as Apple draws one (a capsule with the magnifying glass, the prompt and, once something is typed,
/// the clear button), in the app's inks: the second card's fill and the line, the cursor in ink, never the system blue.
struct SearchField: View {
    @Binding var text: String
    let prompt: String
    let palette: Palette
    var focused: FocusState<Bool>.Binding

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .medium))
                .foregroundStyle(palette.muted).accessibilityHidden(true)
            TextField(text: $text, prompt: Text(verbatim: prompt).foregroundStyle(palette.muted)) {
                Text(verbatim: prompt)
            }
            .font(AppFont.text(16)).foregroundStyle(palette.ink)
            .focused(focused)
            .textInputAutocapitalization(.never).autocorrectionDisabled()
            .submitLabel(.search)
            .onSubmit { focused.wrappedValue = false }
            .accessibilityIdentifier("searchField")
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(palette.muted)
                        .minimumTapArea()
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 44)
        .background(palette.card2, in: Capsule())
        .overlay(Capsule().strokeBorder(palette.line))
        .contentShape(Capsule())
        .onTapGesture { focused.wrappedValue = true }
        .tint(palette.ink)
    }
}

/// A result of the search: the newest payment's category's tile, the shown name with its money out (and in, under it),
/// a quiet line with the count, the newest day and the category, and when it was found by another of its names, that
/// name in a second quiet line ("Bank's name: …", "Your name: …"). A chevron, as every row that opens a page.
private struct NameResultRow: View {
    let result: NameSearchResult
    let store: DashboardStore
    let palette: Palette

    var body: some View {
        let lines = SearchPage.Row(result, group: store.dashboard?.nameGroups?[result.key])
        let category = store.categoryLook(named: result.categoryName)
        HStack(spacing: 12) {
            CategoryTile(icon: category?.icon ?? "Tag", color: category?.color ?? SearchPage.noCategoryColor)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: lines.title).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                    Spacer(minLength: 0)
                    amount(lines.moneyOut ?? lines.moneyIn, income: lines.moneyOut == nil)
                }
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: lines.line).font(AppFont.text(12.5)).foregroundStyle(palette.muted).lineLimit(1)
                    Spacer(minLength: 0)
                    if lines.moneyOut != nil { amount(lines.moneyIn, income: true) }
                }
                // The name it was found by, whole: two lines rather than cut off where the match may be.
                if let match = lines.match {
                    Text(verbatim: match).font(AppFont.text(12.5)).foregroundStyle(palette.secondary).lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
                .accessibilityHidden(true)
        }
        .foregroundStyle(palette.ink).padding(.horizontal, 12).padding(.vertical, 11)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: lines.spoken))
    }

    @ViewBuilder private func amount(_ text: String?, income: Bool) -> some View {
        if let text {
            Text(verbatim: text).font(AppFont.number(14)).foregroundStyle(income ? palette.income : palette.expenseText)
                .fixedSize()
        }
    }
}
