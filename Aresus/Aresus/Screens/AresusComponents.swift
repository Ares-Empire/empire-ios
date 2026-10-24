import SwiftUI

/// Small pieces both tabs use, in the family look of Shared/Design (Aresium's header, the hub's quiet states).

/// The tab header: the bust on the left (38 pt, like Aresium's Hermes), the title centred, an optional button right.
struct AresusHeader<Trailing: View>: View {
    let bust: Image
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            bust.resizable().scaledToFit().frame(width: 38, height: 38)
                .shadow(color: .black.opacity(0.55), radius: 6, y: 4)
                .frame(width: 42, height: 42).accessibilityHidden(true)
            Text(title).font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary).lineLimit(1)
                .frame(maxWidth: .infinity).accessibilityAddTraits(.isHeader)
            trailing.frame(width: 42, height: 42)
        }
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
    }
}

extension AresusHeader where Trailing == Color {
    init(bust: Image, title: String) {
        self.init(bust: bust, title: title) { Color.clear }
    }
}

/// `GlassIconButton`'s look around a menu (Shared's button takes an action, a menu needs a label).
struct GlassMenuButton<Items: View>: View {
    let symbol: String
    let label: String
    @ViewBuilder var items: Items

    var body: some View {
        Menu {
            items
        } label: {
            Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(Ink.secondary)
                .frame(width: 42, height: 42)
                .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Ink.line))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// A section's heading with an optional quiet figure on the right ("ACTIVE ··· 3").
struct SectionTitle: View {
    let text: String
    var value: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeading(text: text)
            Spacer(minLength: 8)
            if let value {
                Text(value).font(AppFont.number(11, weight: .regular)).foregroundStyle(Ink.muted)
                    .contentTransition(.numericText())
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Empty, loading and error states: one calm sentence, centred, in muted ink, with one action if there is one.
struct CalmMessage: View {
    let text: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 16) {
            Text(text).font(AppFont.text(14)).lineSpacing(5).foregroundStyle(Ink.muted)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(AppFont.text(13, weight: .semibold)).foregroundStyle(Ink.primary)
                    .padding(.horizontal, 22).frame(minHeight: 42)
                    .background(Ink.card2, in: .capsule)
                    .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 36)
        .frame(maxWidth: .infinity)
    }
}

/// A quiet spinner where content is about to appear.
struct CalmLoading: View {
    var body: some View {
        ProgressView().tint(Ink.muted).controlSize(.regular)
            .frame(maxWidth: .infinity).accessibilityLabel("Loading")
    }
}

/// "checked 12 s ago" that keeps itself current.
struct LiveRelativeTime: View {
    let date: Date
    let clock: AresusClock
    var prefix: String = ""
    var font: Font = AppFont.number(12, weight: .regular)
    var color: Color = Ink.muted

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            Text(prefix + AresusFormat.relative(date, now: clock.now(context.date)))
                .font(font).foregroundStyle(color).lineLimit(1)
        }
    }
}

/// A thin bar for a share 0…1 (Aresium's row bar): the track in the grid ink, the share in `color`.
struct ShareBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            Capsule().fill(Ink.grid).overlay(alignment: .leading) {
                Capsule().fill(color).frame(width: geometry.size.width * max(0, min(1, fraction)))
            }
        }
        .frame(height: 3)
        .accessibilityHidden(true)
    }
}

/// Shared/Design's glass card with a single-colour edge instead of its light gradient (an issue box's faint red edge).
/// Candidate for Shared/Design as an `edge:` option on `GlassCard`.
struct EdgedGlassCard: ViewModifier {
    let edge: Color

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial).environment(\.colorScheme, .dark)
                    shape.fill(Ink.card)
                    shape.fill(RadialGradient(colors: [.white.opacity(0.07), .clear], center: .topLeading,
                                              startRadius: 0, endRadius: 220))
                }
            }
            .overlay { shape.strokeBorder(edge, lineWidth: 1) }
            .shadow(color: .black.opacity(0.55), radius: 22, y: 14)
    }
}

/// Rows inside one glass card, divided by hairlines (`Ink.line`).
struct CardRows<Item: Identifiable, Row: View>: View {
    let items: [Item]
    @ViewBuilder let row: (Item) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                if index > 0 { Rectangle().fill(Ink.line).frame(height: 1).padding(.horizontal, 16) }
                row(item)
            }
        }
        .glassCard()
    }
}

/// Lays out small pieces left to right, wrapping onto the next line (the run's count capsules).
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
