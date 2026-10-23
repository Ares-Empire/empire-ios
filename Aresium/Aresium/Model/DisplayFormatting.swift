import Foundation

enum ChartAxis {
    static func ticks(_ points: [ChartPoint]) -> [Int] {
        if points.count <= 12 { return points.map(\.index) }
        return points.enumerated().filter {
            $0.offset.isMultiple(of: 5) || $0.offset == points.count - 1
        }.map(\.element.index)
    }
}
