import SwiftUI

/// "Did you mean…" / "Meintest du …" over one chip per suggestion, a tap taking that one: the Überall form's product
/// names (brief 164) and a thing search's corrected words (brief 178), one look in both forms. Each chip is the
/// suggestion as it would be used, in quiet ink on the field's colour, a long one wrapping inside its capsule.
struct DidYouMeanChips: View {
    let names: [String]
    /// The heading's inset: 4 under a field's card (the lines there start so), 0 inside a card.
    var headingInset: CGFloat = 4
    /// The tapped chip's place in `names`.
    let choose: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Did you mean…").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                .padding(.leading, headingInset)
            ChoiceChipsLayout {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    Button { choose(index) } label: {
                        Text(verbatim: name).font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 12).padding(.vertical, 7).frame(minHeight: 32)
                            .background(Ink.field, in: Capsule())
                            .overlay(Capsule().strokeBorder(Ink.line.opacity(1.6)))
                            .padding(.vertical, 6).contentShape(Rectangle()).padding(.vertical, -6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// The chips' spacing, measuring each constrained chip's full height so a long name can wrap.
private struct ChoiceChipsLayout: Layout {
    private func positions(_ subviews: Subviews, width: CGFloat) -> [(CGPoint, CGSize)] {
        var result: [(CGPoint, CGSize)] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let natural = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(natural.width, width), height: nil))
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + 8
                rowHeight = 0
            }
            result.append((CGPoint(x: x, y: y), size))
            x += size.width + 8
            rowHeight = max(rowHeight, size.height)
        }
        return result
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let positions = positions(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? positions.map { $0.0.x + $0.1.width }.max() ?? 0,
                      height: positions.map { $0.0.y + $0.1.height }.max() ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, placement) in zip(subviews, positions(subviews, width: bounds.width)) {
            view.place(at: CGPoint(x: bounds.minX + placement.0.x, y: bounds.minY + placement.0.y),
                       proposal: ProposedViewSize(placement.1))
        }
    }
}
