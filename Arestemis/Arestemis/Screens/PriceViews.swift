import Charts
import SwiftUI

/// A monitor's history as Aresium draws its lines (`SeriesChart`): the price in the accent, 2.6 pt with round ends, over
/// a faint fading area (fainter than Aresium's, as a price's axis does not start at zero); as steps, since a price holds
/// until the next read changes it (`.stepEnd`). A stretch out of stock is drawn dashed in muted ink, so it reads as such
/// without its colour, and on the page over a faint band, so a short one shows in a year too; the alarm's limit is a faint
/// dashed rule, the newest point is marked. `compact`: the card's small 30-day line without axes; else the page's chart
/// with its axes.
struct PriceChartView: View {
    let chart: PriceChart
    var compact = false
    /// The window shown (30, 90 or 365 days), for the axis's labels.
    var days = 30

    private var accent: Color { Look.accent.color }
    private var lineWidth: CGFloat { compact ? 2 : 2.6 }

    var body: some View {
        Chart {
            if !compact {
                ForEach(chart.stretches.filter(\.outOfStock)) { stretch in
                    if let first = stretch.points.first, let last = stretch.points.last, first.date < last.date {
                        RectangleMark(xStart: .value("Day", first.date), xEnd: .value("Day", last.date),
                                      yStart: .value("Price", chart.range.lowerBound),
                                      yEnd: .value("Price", chart.range.upperBound))
                            .foregroundStyle(Ink.grid)
                            .accessibilityHidden(true)
                    }
                }
            }
            ForEach(chart.points) { point in
                AreaMark(x: .value("Day", point.date), yStart: .value("Price", chart.range.lowerBound),
                         yEnd: .value("Price", point.price))
                    .interpolationMethod(.stepEnd)
                    .foregroundStyle(LinearGradient(colors: [accent.opacity(compact ? 0.16 : 0.14), accent.opacity(0)],
                                                    startPoint: .top, endPoint: .bottom))
                    .accessibilityHidden(true)
            }
            ForEach(chart.stretches) { stretch in
                ForEach(stretch.points) { point in
                    LineMark(x: .value("Day", point.date), y: .value("Price", point.price),
                             series: .value("Stretch", stretch.id))
                        .interpolationMethod(.stepEnd)
                        .foregroundStyle(stretch.outOfStock ? Ink.muted : accent)
                        .lineStyle(StrokeStyle(lineWidth: stretch.outOfStock ? lineWidth * 0.75 : lineWidth,
                                               lineCap: .round, lineJoin: .round,
                                               dash: stretch.outOfStock ? [4, 5] : []))
                        .accessibilityLabel(Text(verbatim: PriceChart.dayLabel(point.date, days: 30)))
                        .accessibilityValue(Text(verbatim: chart.spoken(point)))
                }
            }
            if let limit = chart.limit {
                RuleMark(y: .value("Alarm", limit))
                    .foregroundStyle(accent.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 4]))
                    .accessibilityLabel(Text("Alarm"))
                    .accessibilityValue(Text(verbatim: PriceWords.limit(limit)))
            }
            if let newest = chart.newest {
                PointMark(x: .value("Day", newest.date), y: .value("Price", newest.price))
                    .symbol {
                        Circle().fill(newest.outOfStock ? Ink.muted : accent)
                            .frame(width: compact ? 7 : 9, height: compact ? 7 : 9)
                            .overlay(Circle().stroke(Ink.background, lineWidth: 2))
                    }
                    .accessibilityHidden(true)
            }
        }
        .chartXScale(domain: chart.span)
        .chartYScale(domain: chart.range)
        .chartLegend(.hidden)
        .modifier(Axes(compact: compact, days: days, currency: chart.currency))
    }

    /// The page's axes in the app's inks (Aresium's: the prices on the left over faint grid lines, the days under the
    /// plot in small mono); none on the card.
    private struct Axes: ViewModifier {
        let compact: Bool
        let days: Int
        let currency: String

        func body(content: Content) -> some View {
            if compact {
                content.chartXAxis(.hidden).chartYAxis(.hidden)
            } else {
                content
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { value in
                            AxisValueLabel(anchor: .top) {
                                if let date = value.as(Date.self) {
                                    Text(verbatim: PriceChart.dayLabel(date, days: days))
                                        .font(AppFont.number(10)).foregroundStyle(Ink.muted)
                                }
                            }
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                            AxisGridLine().foregroundStyle(Ink.grid)
                            AxisValueLabel {
                                if let price = value.as(Double.self) {
                                    Text(verbatim: PriceChart.axisPrice(price, currency: currency))
                                        .font(AppFont.number(10)).foregroundStyle(Ink.muted)
                                }
                            }
                        }
                    }
            }
        }
    }
}

/// A monitor's lines on its card (the Hunts list) and its page, under its name and quiet line (`PriceCardText`): the
/// price large in the numbers' face with the availability's word beside it (an everywhere monitor's cheapest price with
/// its shop first, "at Amazon · in stock", the sketch's card); on the card the small 30-day line under it while the
/// history is on; else one quiet line (reading, or the server's note); then when it was last checked, following the
/// clock.
struct PriceLines: View {
    let state: PriceState?
    let compact: Bool
    /// The monitor looks for its product on every site (brief 157).
    var everywhere = false
    /// The card's 30-day line; nil without a history (or before it loaded).
    var chart: PriceChart? = nil

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            let text = PriceCardText(state, compact: compact, everywhere: everywhere, now: context.date)
            VStack(alignment: .leading, spacing: compact ? 6 : 8) {
                if let price = text.price {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: price).font(AppFont.number(compact ? 24 : 34, weight: .bold))
                            .foregroundStyle(Ink.primary).lineLimit(1).minimumScaleFactor(0.7)
                            .layoutPriority(1)
                        if let beside = [text.shop, text.availability].compactMap({ $0 }).joined(separator: " · ")
                            .nonEmpty {
                            Text(verbatim: beside).font(AppFont.text(13)).foregroundStyle(Ink.muted).lineLimit(1)
                                .minimumScaleFactor(0.9)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
                if compact, let chart, !chart.isEmpty {
                    PriceChartView(chart: chart, compact: true)
                        .frame(height: 44)
                        .padding(.vertical, 4)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text("Last 30 days"))
                        .accessibilityValue(Text(verbatim: chart.extremes() ?? ""))
                }
                if let note = text.note {
                    Text(note).font(AppFont.text(compact ? 13 : 14)).foregroundStyle(Ink.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let checked = text.checked {
                    Text(checked).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// What a monitor should do (the sketch's form, "Was er tun soll"), in the form and on its page: two switches, Record
/// the history ("Price and availability as a curve") and Alarm ("A push when it happens"); the alarm opens its two
/// conditions under it, a little in: Price under [ € ] (empty: no price condition) and Back in stock. One quiet line
/// under the card says what keeps it from being saved (`line`).
struct MonitorSwitchesCard: View {
    @Binding var history: Bool
    @Binding var alarm: Bool
    @Binding var below: Double?
    @Binding var backInStock: Bool
    let line: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormCard {
                Toggle(isOn: $history) {
                    label("Record the history", "Price and availability as a curve")
                }
                .toggleStyle(EmpireSwitchStyle(accent: Look.accent))
                .frame(minHeight: 60)
                Hairline()
                Toggle(isOn: $alarm) {
                    label("Alarm", "A push when it happens")
                }
                .toggleStyle(EmpireSwitchStyle(accent: Look.accent))
                .frame(minHeight: 60)
                if alarm {
                    VStack(spacing: 0) {
                        Hairline()
                        FormRow(label: String(localized: "Price under")) {
                            NumberField(value: $below, prefix: Euro.prefix, suffix: Euro.suffix, placeholder: "–",
                                        width: 112, label: String(localized: "Alarm when the price is under, in euros"))
                        }
                        Hairline()
                        Toggle(isOn: $backInStock) {
                            Text("Back in stock").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        }
                        .toggleStyle(EmpireSwitchStyle(accent: Look.accent))
                        .frame(minHeight: 50)
                    }
                    .padding(.leading, 16)
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: alarm)
            if let line {
                Caption(text: line).padding(.leading, 4)
            }
        }
    }

    private func label(_ title: LocalizedStringKey, _ line: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
            Text(line).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private extension String {
    /// Nil for an empty string.
    var nonEmpty: String? { isEmpty ? nil : self }
}
