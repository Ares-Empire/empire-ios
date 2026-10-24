import SwiftUI
import Charts

struct IconButton: View {
    let symbol: String
    let label: String
    let palette: Palette
    var active = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .medium))
                .frame(width: 42, height: 42)
                .foregroundStyle(active ? palette.ink : palette.secondary)
                .background(active ? palette.card2 : palette.card, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(active ? palette.muted : palette.line))
        }.buttonStyle(.plain).accessibilityLabel(label).accessibilityAddTraits(active ? .isSelected : [])
    }
}

struct ScreenHeader: View {
    let title: String
    var subtitle: String? = nil
    var category: Category? = nil
    let palette: Palette
    var back: (() -> Void)? = nil
    let toggleTheme: () -> Void
    let openSettings: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            if let back {
                IconButton(symbol: "chevron.left", label: String(localized: "Back"), palette: palette, action: back)
            } else {
                Image("Hermes").resizable().scaledToFit().frame(width: 38, height: 38)
                    .frame(width: 42, height: 42).accessibilityLabel("Aresium")
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
            }.frame(maxWidth: .infinity)
            HStack(spacing: 8) {
                IconButton(symbol: palette.red ? "xmark" : palette.dark ? "sun.max.fill" : "moon.fill",
                           label: palette.red ? String(localized: "Exit Aresium mode") : String(localized: "Toggle theme"), palette: palette, action: toggleTheme)
                IconButton(symbol: "gearshape", label: String(localized: "Settings"), palette: palette, action: openSettings)
            }
        }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
    }
}

struct ValueRow: View {
    let title: String
    let category: Category
    let total: Double
    let maximum: Double
    let palette: Palette
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: CategorySymbol.name(for: category.icon))
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(Color(hex: category.color))
                .frame(width: 38, height: 38)
                .background(Color(hex: category.color).opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Color(hex: category.color).opacity(0.20)))
            VStack(alignment: .leading, spacing: 7) {
                Text(title).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                GeometryReader { geometry in
                    Capsule().fill(palette.grid).overlay(alignment: .leading) {
                        Capsule().fill(Color(hex: category.color))
                            .frame(width: geometry.size.width * (maximum > 0 ? min(1, total / maximum) : 0))
                    }
                }.frame(height: 3).accessibilityHidden(true)
            }
            Text(Money.total(total)).font(AppFont.number(13.5)).fixedSize()
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
        }.foregroundStyle(palette.ink).padding(.horizontal, 12).padding(.vertical, 11)
            .contentShape(Rectangle())
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
    let points: [ChartPoint]
    let color: Color
    let palette: Palette
    let xTitle: String
    var onPick: ((Int) -> Void)? = nil
    var body: some View {
        Chart(points) { point in
            AreaMark(x: .value(xTitle, point.index), y: .value("EUR", point.value))
                .foregroundStyle(LinearGradient(colors: [color.opacity(0.36), color.opacity(0)], startPoint: .top, endPoint: .bottom))
            LineMark(x: .value(xTitle, point.index), y: .value("EUR", point.value))
                .foregroundStyle(color).lineStyle(StrokeStyle(lineWidth: 2.6, lineCap: .round, lineJoin: .round))
                .accessibilityLabel(point.label).accessibilityValue(Money.total(point.value))
        }
        .chartXScale(range: .plotDimension(padding: 16))
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
            if let onPick {
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(SpatialTapGesture().onEnded { event in
                            guard let frame = proxy.plotFrame else { return }
                            let plot = geometry[frame]
                            guard plot.contains(event.location),
                                  let value: Double = proxy.value(atX: event.location.x - plot.minX) else { return }
                            let index = Int(value.rounded())
                            if points.contains(where: { $0.index == index }) { onPick(index) }
                        })
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
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
