import SwiftUI

/// Arestemis's look on top of Shared/Design (DESIGN.md of the 2026-10-24 build): the province wall and glass in
/// moonlight violet, the accent only on the selected tab, the one primary button of a screen and small highlights.
enum Look {
    static let accent = AppAccent.arestemis
    static let onAccent = Color(hex: 0x141617)          // text on the accent fill (the login button's dark ink)
    static let amber = Color(hex: 0xE0B15A)             // warnings ("Rent may be cold rent")
    static let side: CGFloat = 18                       // side margins
    static let rowGap: CGFloat = 12                     // between rows and cards
    static let sectionGap: CGFloat = 28                 // between sections
    static let headingGap: CGFloat = 10                 // a section heading to its card
    static let well = Color.white.opacity(0.045)        // input fields inside a card
    static let wellEdge = Color.white.opacity(0.10)
    static let buttonRadius: CGFloat = 12
}

// MARK: - header

/// The top of a tab (Aresium's ScreenHeader in the province register): the bust on the left, the title centred,
/// one glass button or nothing on the right.
struct AppHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        ZStack {
            Text(title).font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Image("Bust").resizable().scaledToFit().frame(width: 38, height: 38)
                    .shadow(color: .black.opacity(0.5), radius: 6, y: 4)
                    .accessibilityHidden(true)
                Spacer()
                trailing
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 6)
    }
}

extension AppHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

// MARK: - buttons

/// The app's two button looks: `.accent` (the screen's one primary action: accent fill, dark ink) and `.glass`
/// (everything else: translucent, ink). `.quiet` is a text-only action.
struct ProvinceButtonStyle: ButtonStyle {
    enum Kind { case accent, glass, quiet, destructive }
    var kind: Kind = .glass
    var height: CGFloat = 50
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: Look.buttonRadius, style: .continuous)
        configuration.label
            .font(AppFont.text(kind == .destructive ? 14 : 15, weight: kind == .destructive ? .medium : .semibold))
            .lineLimit(1).minimumScaleFactor(0.8)
            .foregroundStyle(foreground)
            .padding(.horizontal, kind == .quiet ? 4 : 16)
            .frame(maxWidth: kind == .quiet ? nil : .infinity, minHeight: kind == .quiet ? 36 : height)
            .background {
                switch kind {
                case .accent where isEnabled: shape.fill(Look.accent.color)
                case .accent, .glass: shape.fill(Color.white.opacity(0.06))
                case .quiet, .destructive: EmptyView()
                }
            }
            .overlay {
                if kind == .glass || (kind == .accent && !isEnabled) { shape.strokeBorder(Color.white.opacity(0.12)) }
            }
            .contentShape(shape)
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : (kind == .accent ? 1 : 0.38))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .accent: isEnabled ? Look.onAccent : Ink.muted
        case .glass: Ink.primary
        case .quiet: Ink.secondary
        case .destructive: StatusTone.issue.color(Look.accent).opacity(0.75)
        }
    }
}

extension ButtonStyle where Self == ProvinceButtonStyle {
    static var accent: ProvinceButtonStyle { ProvinceButtonStyle(kind: .accent) }
    static var glassy: ProvinceButtonStyle { ProvinceButtonStyle(kind: .glass) }
    static var quiet: ProvinceButtonStyle { ProvinceButtonStyle(kind: .quiet) }
    static var destructiveQuiet: ProvinceButtonStyle { ProvinceButtonStyle(kind: .destructive) }
}

// MARK: - chips

/// A choice or a value as a capsule: selected = accent edge and text on a faint accent fill; otherwise glass with a
/// hairline. `onRemove` adds a small ×.
struct Chip: View {
    let text: String
    var selected = false
    var symbol: String? = nil
    var onRemove: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
            }
            Text(text).font(AppFont.text(14, weight: selected ? .semibold : .medium)).lineLimit(1)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Ink.muted).frame(width: 22, height: 22).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(text)")
                .padding(.trailing, -6)
            }
        }
        .foregroundStyle(selected ? Look.accent.color : Ink.primary)
        .padding(.horizontal, 13).frame(minHeight: 34)
        .background(selected ? Look.accent.color.opacity(0.14) : Color.white.opacity(0.04), in: Capsule())
        .overlay(Capsule().strokeBorder(selected ? Look.accent.color.opacity(0.75) : Ink.line.opacity(1.6)))
        .contentShape(Capsule())
    }
}

/// Lays out chips in rows, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = arrange(subviews, width: width)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let used = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? used, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                                      proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row { var indices: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let itemWidth = min(size.width, width)
            if !row.indices.isEmpty, row.width + spacing + itemWidth > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + itemWidth
            row.height = max(row.height, size.height)
            row.indices.append(index)
        }
        if !row.indices.isEmpty { rows.append(row) }
        return rows
    }
}

// MARK: - small pieces

/// Tracked capitals for a figure's or a field's label ("NEW", "SIZE").
struct CapsLabel: View {
    let text: String
    var size: CGFloat = 10
    var color: Color = Ink.muted

    var body: some View {
        Text(text.uppercased()).font(AppFont.text(size, weight: .semibold)).tracking(size * 0.14)
            .foregroundStyle(color).lineLimit(1)
    }
}

/// A thin line between rows inside a card.
struct Hairline: View {
    var body: some View { Rectangle().fill(Ink.line).frame(height: 1) }
}

/// The hunt's status dot: accent with a soft pulse while hunting (still with Reduce Motion), grey when paused.
struct StatusDot: View {
    let active: Bool
    var size: CGFloat = 8
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    var body: some View {
        let color = active ? Look.accent.color : Ink.muted
        Circle().fill(color).frame(width: size, height: size)
            .background {
                if active && !reduceMotion {
                    Circle().fill(color.opacity(0.55))
                        .scaleEffect(pulsing ? 2.6 : 1)
                        .opacity(pulsing ? 0 : 0.9)
                }
            }
            .onAppear { updatePulse() }
            .onChange(of: active) { _, _ in updatePulse() }
            .onChange(of: reduceMotion) { _, _ in updatePulse() }
            .accessibilityHidden(true)
    }

    private func updatePulse() {
        pulsing = false
        guard active && !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) { pulsing = true }
    }
}

/// Empty, loading and error states: one calm sentence in muted ink, centred, and at most one action.
struct CalmMessage: View {
    let text: String
    var action: (title: String, run: () -> Void)? = nil
    var loading = false

    var body: some View {
        VStack(spacing: 14) {
            if loading { ProgressView().tint(Ink.muted) }
            Text(text).font(AppFont.text(14)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
            if let action {
                Button(action.title, action: action.run)
                    .buttonStyle(ProvinceButtonStyle(kind: .glass, height: 44))
                    .frame(maxWidth: 240).padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30).padding(.vertical, 36)
    }
}

/// A failed action, shown briefly over the tabs (the change itself was rolled back).
struct NoticeBanner: View {
    let text: String
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.circle").font(.system(size: 14, weight: .medium))
                .foregroundStyle(Look.amber).padding(.top, 1)
            Text(text).font(AppFont.text(13)).foregroundStyle(Ink.primary).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.muted)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(.leading, 14).padding(.trailing, 8).padding(.vertical, 10)
        .glassCard(raised: true)
        .padding(.horizontal, Look.side)
        .accessibilityElement(children: .combine)
    }
}

/// Ends typing in whichever field has the keyboard (the keyboard's Done; number pads have no return key).
@MainActor
func endTyping() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

extension View {
    /// The wall every Arestemis screen stands on.
    func provinceWall() -> some View {
        background { ProvinceWall(accent: Look.accent) }
    }

    private func fadeFreeEdges(top: CGFloat, bottom: CGFloat) -> Edge.Set {
        var edges: Edge.Set = []
        if top == 0 { edges.insert(.top) }
        if bottom == 0 { edges.insert(.bottom) }
        return edges
    }

    /// Scrolling content fades out at a fixed header (`top`) or bottom bar (`bottom`) instead of running under it, so
    /// the wall stays one surface. An edge without a fade lets the content run under the system bars as usual.
    func edgeFade(top: CGFloat = 0, bottom: CGFloat = 0) -> some View {
        mask {
            VStack(spacing: 0) {
                if top > 0 {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: top)
                }
                Rectangle()
                if bottom > 0 {
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: bottom)
                }
            }
            .ignoresSafeArea(edges: fadeFreeEdges(top: top, bottom: bottom))
        }
    }
}
