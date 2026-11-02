import SwiftUI

/// "Sent to the MacBook" on the Aresync tab (brief 91): the newest three drops in one glass card, then "Show all" when
/// there are more. Each row swipes left to Delete (brief 93, Mail's; `open` is the screen's open row) and its long press
/// offers Try again where it applies and Delete (`DropRow`).
struct DropsSection: View {
    let drops: DropsStore
    @Binding var open: String?
    let showAll: () -> Void
    static let limit = 3

    var body: some View {
        let items = drops.items
        VStack(alignment: .leading, spacing: 0) {
            SectionTitle(text: String(localized: "Sent to the MacBook")).padding(.bottom, 12)
            if let error = drops.errors[.drops] {
                Text("Not refreshed: \(error)").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    .lineLimit(2).padding(.bottom, 10)
            }
            VStack(spacing: 0) {
                DropRows(drops: drops, items: Array(items.prefix(Self.limit)), open: $open)
                if items.count > Self.limit {
                    RowDivider()
                    Button(action: showAll) {
                        HStack(spacing: 10) {
                            Text("Show all").font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.secondary)
                            Spacer(minLength: 8)
                            Text(verbatim: "\(items.count)").font(AppFont.number(12, weight: .regular))
                                .foregroundStyle(Ink.muted)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Ink.muted)
                        }
                        .padding(.horizontal, 16).frame(minHeight: 46)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressedRow())
                    .closesRowSwipeOnTap($open)
                }
            }
            .glassCard()
        }
    }
}

/// Every drop, by the day it was sent (the tab's "Show all"); each row swipes to Delete as on the tab.
struct DropsListScreen: View {
    let drops: DropsStore
    @State private var open: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let days = DropDay.group(drops.items)
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let error = drops.errors[.drops] {
                    Text("Not refreshed: \(error)").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .lineLimit(2).padding(.top, 14)
                }
                if days.isEmpty {
                    CalmMessage(text: String(localized: "Nothing sent to the MacBook yet.")).padding(.top, 170)
                }
                ForEach(days) { day in
                    SectionTitle(text: day.title).padding(.top, 26).padding(.bottom, 12)
                    VStack(spacing: 0) { DropRows(drops: drops, items: day.items, open: $open) }.glassCard()
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 36)
            // A tap between the cards closes an open row too (the rows catch their own taps).
            .background { Color.clear.closesRowSwipeOnTap($open) }
            .animation(reduceMotion ? nil : .smooth, value: drops.items.map(\.id))
        }
        .scrollIndicators(.hidden)
        .closesRowSwipe($open)
        .closesRowSwipe(when: drops.items, open: $open)
        .opensLaunchedSwipe(drops.items, open: $open)
        .refreshable { await drops.load(.drops) }
        .background { ProvinceWall(accent: .aresus) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("Sent to the MacBook").font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary)
            }
        }
    }
}

/// Drops as rows divided by hairlines, each with its swipe (Delete, brief 93) and its long-press actions (Try again where
/// it applies, Delete). A deleted row leaves its list at once (`DropsStore.remove`), with the list's own animation.
struct DropRows: View {
    let drops: DropsStore
    let items: [DropsItem]
    @Binding var open: String?

    var body: some View {
        let outbox = drops.outbox?.items ?? []
        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            if index > 0 { RowDivider() }
            let row = DropRow(item, local: DropRow.hidden(for: item, in: outbox))
            DropRowView(row: row)
                .contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous))
                .contextMenu {
                    if row.canRetry {
                        Button("Try again", systemImage: "arrow.clockwise") { Task { await drops.retry(item) } }
                    }
                    if row.canRemove {
                        Button("Delete", systemImage: "trash", role: .destructive) { delete(item) }
                    }
                }
                // The same for VoiceOver, where a long press is out of the way (Delete comes with the swipe's actions).
                .accessibilityActions {
                    if row.canRetry { Button("Try again") { Task { await drops.retry(item) } } }
                }
                .rowSwipe(row.canRemove ? [deleteAction(item)] : [], id: item.id, open: $open)
                // The swipe's Delete stands a little inside the card's edge, as iOS's own actions in a card do; the
                // row's content keeps its place (`DropRowView.inset`) and is cut off at the card's edge as it slides.
                .padding(.horizontal, DropRowView.swipeInset)
                .clipped()
        }
    }

    /// Mail's Delete: the trash over the word, in the soft red; a full swipe does it at once.
    private func deleteAction(_ item: DropsItem) -> RowSwipeAction {
        RowSwipeAction(label: String(localized: "Delete"), systemImage: "trash",
                       accessibilityName: String(localized: "Delete"), role: .destructive) { delete(item) }
    }

    private func delete(_ item: DropsItem) {
        Task { await drops.remove(item) }
    }

    /// Screenshots: `-swipeDrop <n>` shows the n-th drop (from 1) swiped open, on the tab or in Show all.
    static func launchedOpen(in items: [DropsItem]?) -> String? {
        #if DEBUG
        guard let items, let number = LaunchArguments.value("-swipeDrop").flatMap(Int.init),
              items.indices.contains(number - 1) else { return nil }
        return items[number - 1].id
        #else
        return nil
        #endif
    }
}

extension View {
    /// The open row closes when its drop has left the list (deleted here, or gone with a refresh), so the next tap is
    /// not spent on closing a row that is not there.
    func closesRowSwipe(when items: [DropsItem], open: Binding<String?>) -> some View {
        onChange(of: items.map(\.id)) { _, ids in
            if let id = open.wrappedValue, !ids.contains(id) { open.wrappedValue = nil }
        }
    }

    /// Screenshots: `-swipeDrop <n>` opens that row once the drops are there.
    @ViewBuilder func opensLaunchedSwipe(_ items: [DropsItem], open: Binding<String?>) -> some View {
        #if DEBUG
        modifier(LaunchedSwipe(items: items, open: open))
        #else
        self
        #endif
    }
}

#if DEBUG
private struct LaunchedSwipe: ViewModifier {
    let items: [DropsItem]
    @Binding var open: String?
    @State private var done = false

    func body(content: Content) -> some View {
        content.onChange(of: items.map(\.id), initial: true) { _, _ in
            guard !done, let id = DropRows.launchedOpen(in: items) else { return }
            done = true
            open = id
        }
    }
}
#endif

/// A drop: the kind of file's symbol, the name (one line, its middle cut), one quiet line for its state, and a landed
/// drop's note below in muted text.
struct DropRowView: View {
    let row: DropRow
    /// How far inside the card's edge a swiped row's Delete stands; the row's content keeps the card's 16 pt margin.
    static let swipeInset: CGFloat = 6

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: row.kind.symbol).font(.system(size: 16, weight: .regular)).foregroundStyle(Ink.muted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.name).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                    .lineLimit(1).truncationMode(.middle)
                Text(verbatim: row.line).font(AppFont.text(12.5)).foregroundStyle(color).lineSpacing(2).lineLimit(3)
                if let note = row.note {
                    Text(verbatim: note).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineSpacing(2).lineLimit(3)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16 - Self.swipeInset).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(row.isQuiet ? 0.7 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch row.tone {
        case .normal: Ink.secondary
        case .muted: Ink.muted
        case .warning: AresusInk.warning
        }
    }
}

/// The hairline between rows inside a card (`CardRows`'s).
struct RowDivider: View {
    var body: some View { Rectangle().fill(Ink.line).frame(height: 1).padding(.horizontal, 16) }
}
