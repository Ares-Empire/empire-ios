import SwiftUI
import Charts
import WidgetKit

/// Shared with the app's rendering tests so the images exercise the actual widget content.
struct SpendingWidgetView: View {
    let snapshot: WidgetSnapshot?
    let theme: AppTheme
    let date: Date
    var calendar: Calendar = .current
    var locked = false
    private var palette: Palette { Palette(theme: theme) }

    var body: some View {
        Group {
            if locked {
                LockedWidgetView(palette: palette)
            } else if let snapshot, let note = WidgetMonthNote(snapshot: snapshot, now: date, calendar: calendar) {
                WidgetMonthNoteView(note: note, palette: palette, compact: false)
            } else if let snapshot {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(snapshot.monthLabel).font(AppFont.text(14))
                        Spacer(minLength: 8)
                        Text(Money.precise(snapshot.expense)).privacySensitive().font(AppFont.number(20))
                            .minimumScaleFactor(0.7).lineLimit(1)
                    }.foregroundStyle(palette.ink)
                    Chart(Array(snapshot.dayExpenseRunning.enumerated()), id: \.offset) { point in
                        LineMark(x: .value("Day", point.offset + 1), y: .value("Spent", point.element))
                            .foregroundStyle(palette.expenseText)
                            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    }
                    .chartXScale(domain: 1...snapshot.daysInMonth)
                    .chartYScale(domain: .automatic(includesZero: true))
                    .chartXAxis {
                        AxisMarks(values: [1, snapshot.daysInMonth]) { value in
                            AxisValueLabel(anchor: value.as(Int.self) == 1 ? .topLeading : .topTrailing,
                                           collisionResolution: .disabled) {
                                if let day = value.as(Int.self) {
                                    Text(String(day)).font(AppFont.number(9, weight: .regular))
                                        .foregroundStyle(palette.muted)
                                }
                            }
                        }
                    }
                    .chartYAxis(.hidden)
                    .accessibilityLabel("This month's spending")
                    .accessibilityValue(Money.precise(snapshot.expense))
                    .privacySensitive()
                    HStack {
                        Text(verbatim: "ARESIUM").tracking(2).font(AppFont.text(8))
                        Spacer()
                        if let freshness = WidgetFormatting.freshness(snapshot.newestTransactionDate) {
                            Text(freshness).font(AppFont.text(10))
                        }
                    }.foregroundStyle(palette.secondary)
                }
            } else { EmptyWidgetView(palette: palette) }
        }
        .widgetURL(AresiumURL.start.url)
    }
}

struct CategoriesWidgetView: View {
    let snapshot: WidgetSnapshot?
    let firstCategory: String?
    let secondCategory: String?
    let theme: AppTheme
    let date: Date
    var calendar: Calendar = .current
    var locked = false
    private var palette: Palette { Palette(theme: theme) }

    var body: some View {
        Group {
            if locked {
                LockedWidgetView(palette: palette)
            } else if let snapshot, let note = WidgetMonthNote(snapshot: snapshot, now: date, calendar: calendar) {
                WidgetMonthNoteView(note: note, palette: palette, compact: true)
            } else if let snapshot {
                VStack(alignment: .leading, spacing: 10) {
                    Text(snapshot.monthLabel).font(AppFont.text(12)).foregroundStyle(palette.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    let defaults = snapshot.defaultCategoryNames
                    let first = snapshot.category(named: firstCategory) ?? snapshot.category(named: defaults.first)
                    let second = snapshot.category(named: secondCategory) ?? snapshot.category(named: defaults.dropFirst().first)
                    if let first { row(first) }
                    if first != nil && second != nil { Rectangle().fill(palette.line).frame(height: 1) }
                    if let second { row(second) }
                    if first == nil && second == nil {
                        Text("No spending categories", tableName: "AresiumShared").font(AppFont.text(12)).foregroundStyle(palette.secondary)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else { EmptyWidgetView(palette: palette) }
        }
        .widgetURL(AresiumURL.start.url)
    }

    private func row(_ category: WidgetSnapshot.SpendCategory) -> some View {
        Link(destination: AresiumURL.category(category.name).url) {
            HStack(spacing: 8) {
                Image(systemName: CategorySymbol.name(for: category.icon))
                    .font(.system(size: 17, weight: .medium)).frame(width: 21)
                VStack(alignment: .leading, spacing: 2) {
                    Text(CategoryName.shown(category.name)).font(AppFont.text(11)).lineLimit(1).minimumScaleFactor(0.7)
                    Text(Money.precise(category.total)).privacySensitive().font(AppFont.number(16)).lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color(hex: category.color))
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct WidgetMonthNoteView: View {
    let note: WidgetMonthNote
    let palette: Palette
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(note.monthLabel).font(AppFont.text(compact ? 12 : 14))
                .foregroundStyle(compact ? palette.secondary : palette.ink)
                .lineLimit(1).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            Text(note.message).font(AppFont.text(13)).foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                if !compact {
                    Text(verbatim: "ARESIUM").tracking(2).font(AppFont.text(8))
                    Spacer()
                }
                if let lastData = note.lastData {
                    Text(lastData).font(AppFont.text(10))
                }
            }.foregroundStyle(palette.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// While Aresium's lock is on: no numbers, only the name and that it is locked (the empty state's layout).
private struct LockedWidgetView: View {
    let palette: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Aresium").font(AppFont.text(15)).foregroundStyle(palette.ink)
            Label {
                Text("Locked", tableName: "AresiumShared")
            } icon: {
                Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold))
            }
            .font(AppFont.text(13)).foregroundStyle(palette.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private struct EmptyWidgetView: View {
    let palette: Palette
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(verbatim: "Aresium").font(AppFont.text(15)).foregroundStyle(palette.ink)
            Text("Open Aresium to load your data", tableName: "AresiumShared").font(AppFont.text(13))
                .foregroundStyle(palette.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
