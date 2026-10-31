import SwiftUI
import Charts
import UIKit

struct IconButton: View {
    let symbol: String
    let label: String
    let palette: Palette
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).headerButtonFace().foregroundStyle(palette.secondary)
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
}

/// How the header's buttons are drawn (brief 56, Patrik 2026-10-31: "remove their block outline, just have them on the
/// background"): the symbol alone on the wall, no card and no outline, every header alike (the back arrow, the gear, the
/// import button, red mode's X, a category's icon of adding up). Drawn in a 42 pt square that takes taps over 44 pt
/// (`minimumTapArea`); side by side 44 pt apart, as the bar buttons of iOS.
enum HeaderButtonLook {
    static let side: CGFloat = 42
    static let spacing: CGFloat = 2
    /// The symbols' size: about the title's, so they read on the wall without a box around them.
    static let symbolSize: CGFloat = 19
}

extension View {
    /// A header button's face: its symbol at the header's size in the 42 pt square, the whole square tappable and the
    /// tap area grown to 44 pt. Put it inside the button's label.
    func headerButtonFace() -> some View {
        font(.system(size: HeaderButtonLook.symbolSize, weight: .medium))
            .frame(width: HeaderButtonLook.side, height: HeaderButtonLook.side)
            .contentShape(Rectangle())
            .minimumTapArea()
    }
}

extension View {
    /// Apple's smallest tap area, 44 × 44 pt, around a control drawn smaller (brief 41: the import result's words, the
    /// header's 42 pt buttons): the area that takes the tap grows evenly around it, while the control keeps its drawn
    /// size and its place in the layout. Put it inside a button's label. Next to another control, the area stops where
    /// the screen's layout leaves room; where two would overlap, the later one takes the overlap.
    func minimumTapArea() -> some View { modifier(MinimumTapArea()) }
}

private struct MinimumTapArea: ViewModifier {
    static let side: CGFloat = 44
    /// The control's drawn size, measured: the area grows by what it lacks.
    @State private var size = CGSize(width: side, height: side)

    func body(content: Content) -> some View {
        let horizontal = max(0, (Self.side - size.width) / 2)
        let vertical = max(0, (Self.side - size.height) / 2)
        content
            .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
            .padding(.horizontal, horizontal).padding(.vertical, vertical)
            .contentShape(Rectangle())
            .padding(.horizontal, -horizontal).padding(.vertical, -vertical)
    }
}

/// A screen's header: Aresium's mark or the back arrow, the title in the middle, and the buttons on the right, each on the
/// wall without a box (brief 56, `HeaderButtonLook`): red mode's X first (so the others keep their places when it comes),
/// then the page's own button (the start screen's import, a category's icon of adding up, brief 53), then the gear.
/// Light and dark are chosen in Settings → General → Appearance (brief 42: the sun button that switched them is gone).
struct ScreenHeader: View {
    /// The category's icon of adding up: what it shows, and its tap.
    struct Sums {
        let on: Bool
        let toggle: () -> Void
    }

    /// The start screen's import button (brief 56: beside the gear on the title row; it was beside the range picker):
    /// its store (the busy state), whether the sample shows, and phone mode's menu (nil: server mode's file picker).
    struct Import {
        let store: ImportStore
        let sample: Bool
        let choices: ImportChoices?
    }

    let title: String
    var subtitle: String? = nil
    var category: Category? = nil
    let palette: Palette
    var back: (() -> Void)? = nil
    var sums: Sums? = nil
    var imports: Import? = nil
    /// Red mode's X, the way out of it (red is entered through the band).
    let leaveRed: () -> Void
    let openSettings: () -> Void
    var body: some View {
        HeaderLayout(spacing: 10) {
            if let back {
                IconButton(symbol: "chevron.left", label: String(localized: "Back"), palette: palette, action: back)
            } else {
                Image("Hermes").resizable().scaledToFit().frame(width: 38, height: 38)
                    .frame(width: HeaderButtonLook.side, height: HeaderButtonLook.side).accessibilityLabel("Aresium")
            }
            VStack(spacing: 2) {
                HStack(spacing: 7) {
                    if let category {
                        Image(systemName: CategorySymbol.name(for: category.icon))
                            .foregroundStyle(Color(hex: category.color)).font(.system(size: 17))
                    }
                    Text(title).font(AppFont.text(17, weight: .bold)).lineLimit(1)
                }
                if let subtitle { Text(subtitle).font(AppFont.text(12)).foregroundStyle(palette.muted).lineLimit(1) }
            }
            HStack(spacing: HeaderButtonLook.spacing) {
                if palette.red {
                    IconButton(symbol: "xmark", label: String(localized: "Exit Aresium mode"), palette: palette,
                               action: leaveRed)
                }
                if let sums {
                    SumCategoryButton(on: sums.on, palette: palette, action: sums.toggle)
                        .transition(.opacity)
                }
                if let imports {
                    ImportButton(store: imports.store, sample: imports.sample, palette: palette, choices: imports.choices)
                        .tourAnchor(.importButton)
                }
                IconButton(symbol: "gearshape", label: String(localized: "Settings"), palette: palette, action: openSettings)
                    .tourAnchor(.settings)
            }
        }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
    }
}

/// The header's three parts: the mark or the arrow at the leading edge, the buttons at the trailing edge, and the title
/// in the middle of the screen while it fits there, else as near the middle as the buttons let it stand (brief 56: the
/// start screen's two buttons on the right would have pushed "Aresium" off the middle in a plain row).
private struct HeaderLayout: Layout {
    let spacing: CGFloat

    private struct Parts {
        let leading: CGSize
        let title: CGSize
        let trailing: CGSize
    }

    private func parts(width: CGFloat, _ subviews: Subviews) -> Parts {
        let leading = subviews[0].sizeThatFits(.unspecified)
        let trailing = subviews[2].sizeThatFits(.unspecified)
        let room = max(0, width - leading.width - trailing.width - 2 * spacing)
        let title = subviews[1].sizeThatFits(ProposedViewSize(width: room, height: nil))
        return Parts(leading: leading, title: CGSize(width: min(title.width, room), height: title.height),
                     trailing: trailing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard subviews.count == 3 else { return .zero }
        let ideal = subviews.map { $0.sizeThatFits(.unspecified).width }.reduce(2 * spacing, +)
        let width = proposal.width ?? ideal
        let parts = parts(width: width, subviews)
        return CGSize(width: width, height: max(parts.leading.height, parts.title.height, parts.trailing.height))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard subviews.count == 3 else { return }
        let parts = parts(width: bounds.width, subviews)
        subviews[0].place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading,
                          proposal: ProposedViewSize(parts.leading))
        subviews[2].place(at: CGPoint(x: bounds.maxX, y: bounds.midY), anchor: .trailing,
                          proposal: ProposedViewSize(parts.trailing))
        let lowest = bounds.minX + parts.leading.width + spacing
        let highest = bounds.maxX - parts.trailing.width - spacing - parts.title.width
        let x = min(max(bounds.midX - parts.title.width / 2, lowest), max(lowest, highest))
        subviews[1].place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(parts.title))
    }
}

struct ValueRow: View {
    let title: String
    let category: Category
    let total: Double
    let maximum: Double
    let palette: Palette
    /// The amount written in place of the total, where the bar does not count it: a name's month with only money the
    /// other way, such as a refund ("+€80", brief 55).
    var amount: Text? = nil
    var body: some View {
        HStack(spacing: 12) {
            CategoryTile(icon: category.icon, color: category.color)
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                GeometryReader { geometry in
                    Capsule().fill(palette.grid).overlay(alignment: .leading) {
                        Capsule().fill(Color(hex: category.color))
                            .frame(width: geometry.size.width * (maximum > 0 ? min(1, total / maximum) : 0))
                    }
                }.frame(height: 3).accessibilityHidden(true)
            }
            (amount ?? Text(Money.total(total))).font(AppFont.number(13.5)).fixedSize()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
        }.foregroundStyle(palette.ink).padding(.horizontal, 12).padding(.vertical, 11)
            .contentShape(Rectangle())
    }
}

/// A category's mark as the dashboard's rows draw it (the website's `.cat-icon`): its icon in its colour on a faint tile
/// of the same colour. The category picker and the untick question use it too.
struct CategoryTile: View {
    let icon: String
    let color: String

    var body: some View {
        Image(systemName: CategorySymbol.name(for: icon))
            .font(.system(size: 19, weight: .medium))
            .foregroundStyle(Color(hex: color))
            .frame(width: 38, height: 38)
            .background(Color(hex: color).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: color).opacity(0.20)))
    }
}

/// The square that starts a payment row (the website's `.txn-day`): the day of the month in mono on the second card
/// colour (`DayWording`: "4." in German), or a summed row's count. The column check's first payments and the guide's
/// numbered steps use it too. The tile keeps its size at every text size: at the largest ones its words shrink into it
/// ("31." too) rather than turning into "…", clear of its edges (briefs 53 and 55).
struct DayTile<Label: View>: View {
    let palette: Palette
    @ViewBuilder let label: Label

    var body: some View {
        label.font(AppFont.number(15)).foregroundStyle(palette.secondary)
            .lineLimit(1).minimumScaleFactor(0.4).padding(.horizontal, 3)
            .frame(width: 38, height: 38)
            .background(palette.card2, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.line))
    }
}

struct DashboardStatus: View {
    let store: DashboardStore
    let palette: Palette
    var body: some View {
        if store.isLoading {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading dashboard…").font(AppFont.text(12))
            }.foregroundStyle(palette.secondary).padding(8)
        }
        if let error = store.error {
            HStack(alignment: .top) {
                Text(error).font(AppFont.text(12)).frame(maxWidth: .infinity, alignment: .leading)
                Button("Retry") { Task { await store.reload() } }.font(AppFont.text(12, weight: .bold))
                    .disabled(store.isLoading)
            }.foregroundStyle(palette.ink).padding(12).background(palette.card2, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal, 14).accessibilityElement(children: .contain)
        }
    }
}

struct SeriesChart: View {
    /// The graph's height on the start screen and on a category's page (the same on both, brief 42).
    static let dashboardHeight: CGFloat = 235

    let points: [ChartPoint]
    let color: Color
    let palette: Palette
    let xTitle: String
    /// A tap on a point opens it (the month graphs: Overview's month page, a category's month, a name's month); nil: the
    /// graph only shows its numbers (the day graphs).
    var onPick: ((Int) -> Void)? = nil
    /// The point a finger reads now (brief 56): a guide line and a dot on it, and the chip with its day or month and its
    /// amount above the plot; nil while no finger holds the graph.
    @State private var reading: Int?
    /// The chip's width, measured, so it stays inside the graph at either end.
    @State private var chipWidth: CGFloat = 0
    /// The overlay's size and the plot's frame in it, kept as they change (they do not while the graph scrolls with its
    /// list), for the finger's place and the marks.
    @State private var layout = ChartLayout()

    var body: some View {
        // One point (only one month of data so far): a line and its area need two, so they would draw nothing and leave
        // an empty plot. That point stands as a stem from zero with a dot, in the middle of the plot.
        if let domain = ChartAxis.singlePointDomain(points) {
            chart.chartXScale(domain: domain, range: .plotDimension(padding: 16))
        } else {
            chart.chartXScale(range: .plotDimension(padding: 16))
        }
    }

    private var chart: some View {
        Chart(points) { point in
            if points.count == 1 {
                RuleMark(x: .value(xTitle, point.index), yStart: .value("EUR", 0), yEnd: .value("EUR", point.value))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round))
                PointMark(x: .value(xTitle, point.index), y: .value("EUR", point.value))
                    .foregroundStyle(color).symbolSize(90)
                    .accessibilityLabel(point.label).accessibilityValue(Money.total(point.value))
            } else {
                AreaMark(x: .value(xTitle, point.index), y: .value("EUR", point.value))
                    .foregroundStyle(LinearGradient(colors: [color.opacity(0.36), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value(xTitle, point.index), y: .value("EUR", point.value))
                    .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                    .accessibilityLabel(point.label).accessibilityValue(Money.total(point.value))
            }
        }
        .chartYScale(domain: .automatic(includesZero: true))
        .chartXAxis {
            AxisMarks(values: ChartAxis.ticks(points)) { value in
                AxisValueLabel(anchor: .top) {
                    if let index = value.as(Int.self), let point = points.first(where: { $0.index == index }) {
                        Text(point.label).font(AppFont.number(10)).foregroundStyle(palette.muted)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(palette.grid)
                AxisValueLabel {
                    if let number = value.as(Double.self) {
                        Text(Money.total(number)).font(AppFont.number(10)).foregroundStyle(palette.muted)
                    }
                }
            }
        }
        .chartXAxisLabel(xTitle, alignment: .center).chartYAxisLabel("EUR", position: .topLeading)
        .chartOverlay { proxy in
            ZStack(alignment: .topLeading) {
                // The finger's layer: a hold reads the graph (`ChartHold`), a tap opens a month where one opens.
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .gesture(ChartHold { location in read(location, proxy: proxy) })
                    .gesture(SpatialTapGesture().onEnded { event in
                        guard let onPick, reading == nil,
                              let index = index(at: event.location, proxy: proxy, insidePlot: true) else { return }
                        onPick(index)
                    }, isEnabled: onPick != nil)
                if let reading, let point = points.first(where: { $0.index == reading }) {
                    readingMarks(point, proxy: proxy)
                }
            }
            .onGeometryChange(for: ChartLayout.self) { geometry in
                ChartLayout(size: geometry.size, plot: proxy.plotFrame.map { geometry[$0] } ?? .zero)
            } action: { layout = $0 }
            .accessibilityHidden(true)            // VoiceOver reads the points themselves
        }
        .sensoryFeedback(.selection, trigger: reading) { _, new in new != nil }
        #if DEBUG
        .task(id: points.count) {
            // Screenshots: `-readGraph <index>` shows the chip on that point, as a held finger would.
            if let index = LaunchArguments.value("-readGraph").flatMap(Int.init),
               points.contains(where: { $0.index == index }) { reading = index }
        }
        #endif
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    /// The point under a place in the overlay: the nearest one along the plot (`ChartReading.nearest`); with
    /// `insidePlot`, only for a place inside the plot (a tap on the axes opens nothing).
    private func index(at location: CGPoint, proxy: ChartProxy, insidePlot: Bool) -> Int? {
        let plot = layout.plot
        guard !plot.isEmpty else { return nil }
        if insidePlot && !plot.contains(location) { return nil }
        guard let x: Double = proxy.value(atX: location.x - plot.minX) else { return nil }
        return ChartReading.nearest(to: x, in: points)?.index
    }

    /// The finger held, moved or let go (nil): the point it reads, set only when it changes (one haptic tick per point).
    private func read(_ location: CGPoint?, proxy: ChartProxy) {
        let index = location.flatMap { self.index(at: $0, proxy: proxy, insidePlot: false) }
        guard index != reading else { return }
        reading = index
        #if DEBUG
        ChartReading.logReading(index.flatMap { index in points.first { $0.index == index } })
        #endif
    }

    /// The website's hover marks in the app's inks: a dashed guide from the plot's foot up to the chip, a dot on the line
    /// ringed in the wall's colour, and the chip just above the plot, over the axis's "EUR", inside the graph's width.
    @ViewBuilder
    private func readingMarks(_ point: ChartPoint, proxy: ChartProxy) -> some View {
        let plot = layout.plot
        if !plot.isEmpty, let px = proxy.position(forX: point.index), let py = proxy.position(forY: point.value) {
            let x = plot.minX + px, y = plot.minY + py
            let chipBottom = plot.minY - 2
            Path { path in
                path.move(to: CGPoint(x: x, y: plot.maxY))
                path.addLine(to: CGPoint(x: x, y: chipBottom))
            }
            .stroke(palette.guide, style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            Circle().fill(color).frame(width: 9, height: 9)
                .overlay(Circle().stroke(palette.background, lineWidth: 2))
                .position(x: x, y: y)
            // The chip's foot on a point just above the plot (an overlay of a point, so its height needs no measuring);
            // sideways it follows the finger and stops at the graph's edges.
            let half = chipWidth / 2
            Color.clear.frame(width: 1, height: 1)
                .overlay(alignment: .bottom) {
                    ChartChip(point: point, color: color, palette: palette)
                        .fixedSize()
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { chipWidth = $0 }
                }
                .position(x: min(max(half, x), max(half, layout.size.width - half)), y: chipBottom)
        }
    }
}

/// Where a graph's plot lies in its overlay (`SeriesChart.layout`).
private nonisolated struct ChartLayout: Equatable, Sendable {
    var size = CGSize.zero
    var plot = CGRect.zero
}

/// The chip of a graph read by a finger (the website's `.chart-tip`, one line on the phone): the day or month in muted
/// mono, a dot in the line's colour and the amount to the cent in ink, on the second card over the wall with its
/// hairline and the cards' shadow (`ChartReading.chip`).
private struct ChartChip: View {
    let point: ChartPoint
    let color: Color
    let palette: Palette

    var body: some View {
        let chip = ChartReading.chip(point)
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        HStack(spacing: 7) {
            Text(verbatim: chip.title).font(AppFont.number(11, weight: .bold)).foregroundStyle(palette.muted)
            Circle().fill(color).frame(width: 6, height: 6)
            Text(verbatim: chip.amount).font(AppFont.number(12.5, weight: .semibold)).foregroundStyle(palette.ink)
        }
        .lineLimit(1)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background { shape.fill(palette.background).overlay(shape.fill(palette.card2)) }
        .overlay(shape.strokeBorder(palette.line))
        .shadow(color: Ink.shadow.opacity(0.7), radius: 5, y: 2)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)        // a chip, as the axes' labels: it must stay one line
        .allowsHitTesting(false)
    }
}

/// The hold that starts reading a graph (brief 56): UIKit's own long press, a finger held still for a moment and then
/// followed, as Apple's Stocks and Health read their graphs. A finger that moves before the moment is up is never
/// taken: it stays the scroll's, the pages' and the back swipe's, which begin by moving; once the hold has begun, they
/// give way to it until the finger lifts. A short tap ends before it and stays a tap.
private struct ChartHold: UIGestureRecognizerRepresentable {
    /// Where the finger is while it reads; nil when it lifts or the hold is cancelled.
    let moved: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = ChartReading.holdDuration
        recognizer.allowableMovement = ChartReading.holdMovement
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed: moved(context.converter.localLocation)
        default: moved(nil)
        }
    }
}

struct EmptyMessage: View {
    let text: String
    let palette: Palette
    var body: some View {
        Text(text).font(AppFont.text(14)).foregroundStyle(palette.muted)
            .frame(maxWidth: .infinity).padding(30)
    }
}
