import Foundation

enum ChartAxis {
    static func ticks(_ points: [ChartPoint]) -> [Int] {
        if points.count <= 12 { return points.map(\.index) }
        return points.enumerated().filter {
            $0.offset.isMultiple(of: 5) || $0.offset == points.count - 1
        }.map(\.element.index)
    }

    /// The x range for a chart of one point (one month of data, or the first day): a line needs two points, so that one
    /// is drawn as a stem with a dot in the middle of the plot (`SeriesChart`). nil with more points or none: the
    /// chart's own range.
    static func singlePointDomain(_ points: [ChartPoint]) -> ClosedRange<Int>? {
        guard points.count == 1, let index = points.first?.index else { return nil }
        return (index - 1)...(index + 1)
    }
}
