import SwiftUI

/// "Sent to the MacBook" on the Aresync tab (brief 91): the newest three drops in one glass card, then "Show all" when
/// there are more. Each row's long press offers Try again and Remove where they apply (`DropRow`).
struct DropsSection: View {
    let drops: DropsStore
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
                DropRows(drops: drops, items: Array(items.prefix(Self.limit)))
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
                }
            }
            .glassCard()
        }
    }
}

/// Every drop, by the day it was sent (the tab's "Show all").
struct DropsListScreen: View {
    let drops: DropsStore
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
                    VStack(spacing: 0) { DropRows(drops: drops, items: day.items) }.glassCard()
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 36)
            .animation(reduceMotion ? nil : .smooth, value: drops.items.map(\.id))
        }
        .scrollIndicators(.hidden)
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

/// Drops as rows divided by hairlines, each with its long-press actions.
private struct DropRows: View {
    let drops: DropsStore
    let items: [DropsItem]

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
                        Button("Remove", systemImage: "trash", role: .destructive) { Task { await drops.remove(item) } }
                    }
                }
                // The same for VoiceOver, where a long press is out of the way.
                .accessibilityActions {
                    if row.canRetry { Button("Try again") { Task { await drops.retry(item) } } }
                    if row.canRemove { Button("Remove") { Task { await drops.remove(item) } } }
                }
        }
    }
}

/// A drop: the kind of file's symbol, the name (one line, its middle cut), one quiet line for its state, and a landed
/// drop's note below in muted text.
struct DropRowView: View {
    let row: DropRow

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
        .padding(.horizontal, 16).padding(.vertical, 12)
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
