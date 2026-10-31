import Foundation
import os

/// Reading a graph by sliding over it (brief 56, Patrik 2026-10-31: "slowly sliding over the graph it shows each month's
/// number", as the website's tooltip): the point nearest the finger and what the chip above the plot says. Pure, so tests
/// pin it; `SeriesChart` draws it.
enum ChartReading {
    /// How long a finger rests on a graph before it reads it (brief 56): long enough that a scroll, a page swipe or the
    /// back swipe, which all begin by moving, are never taken; short enough to feel at once (Stocks and Health hold too).
    static let holdDuration: TimeInterval = 0.25
    /// How far the finger may wander during the hold and still read (UIKit's own default for a long press).
    static let holdMovement: CGFloat = 10
    #if DEBUG
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "graph")

    /// What the chip shows now (nil: it went), for the real-touch checks, which read it from the log (debug level,
    /// category `graph`).
    static func logReading(_ point: ChartPoint?) {
        let shown = point.map { line($0) } ?? "none"
        log.debug("reading \(shown, privacy: .public)")
    }
    #endif

    /// The point nearest to `x`, a place on the chart's index scale (what the chart reads at the finger): halfway between
    /// two points goes to the later one, and a finger beyond either end stays on the first or the last point. nil only
    /// for a graph without points.
    static func nearest(to x: Double, in points: [ChartPoint]) -> ChartPoint? {
        guard !x.isNaN else { return nil }
        return points.min { first, second in
            let one = abs(Double(first.index) - x), other = abs(Double(second.index) - x)
            return one == other ? first.index > second.index : one < other
        }
    }

    /// The chip's two parts: the point's day or month written out ("Mon 14 Sep", "Sep 2026") and its amount to the
    /// cent ("€1,234.50" / "1.234,50 €"), as the website's tooltip names the month and its amount.
    static func chip(_ point: ChartPoint, language: AppLanguage = .current) -> (title: String, amount: String) {
        (point.title, Money.precise(point.value, language: language))
    }

    /// The chip as one line of text (the real-touch checks log it): "Mon 14 Sep, €12.40".
    static func line(_ point: ChartPoint, language: AppLanguage = .current) -> String {
        let chip = chip(point, language: language)
        return chip.title + ", " + chip.amount
    }

    /// The days of a month (`key` "YYYY-MM") as the chip names them, the first day first: "Thu 1 Oct", "Fri 2 Oct", …
    /// / "Do. 1. Okt.", …; `count` of them (the dashboard's days of that month). The month's first day is read once, so a
    /// page's graph costs one date and one format, not one per day. The day numbers alone when the key is not a month.
    static func dayTitles(month key: String, count: Int, language: AppLanguage = .current) -> [String] {
        let calendar = WidgetFormatting.calendar
        guard count > 0 else { return [] }
        guard let first = WidgetFormatting.monthDate(key) else { return (1...count).map(String.init) }
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                     timeZone: calendar.timeZone).weekday(.abbreviated).day().month(.abbreviated)
        return (0..<count).map { offset in
            calendar.date(byAdding: .day, value: offset, to: first).map { $0.formatted(style) } ?? String(offset + 1)
        }
    }
}
