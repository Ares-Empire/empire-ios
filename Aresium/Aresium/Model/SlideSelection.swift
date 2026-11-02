import CoreGraphics

// Selecting by sliding a finger over a category's month list while it selects (brief 200, Patrik 2026-11-02: "like mail
// so you can basically just slide your finger up and down and it keeps selecting statements or when going up deselecting
// them"). Mail's and Photos' rule, pure so tests pin it: where a slide may start, which rows it ticks, and how fast the
// list scrolls by itself while the finger is near its top or bottom edge. The gesture and the scrolling are
// `Screens/SlideSelect.swift`; what is ticked stays `PaymentSelection`'s.

/// One slide over a list's rows: the first row touched decides (not ticked: the slide ticks; ticked: it unticks); every
/// row from the first to the finger's takes that state, and every other row is as it was before the slide began, so the
/// rows the finger leaves again on the way back return to their earlier state.
nonisolated struct SlideSelection: Equatable {
    /// The list's rows in order, each the payments it stands for (a summed row all its payments, as one row); empty for a
    /// row that cannot be ticked (a withdrawal's covered row), which the slide passes over.
    let rows: [Set<String>]
    /// What was ticked when the slide began.
    let before: Set<String>
    /// The row the slide began on.
    let anchor: Int
    /// The slide ticks (its first row was not ticked) or unticks.
    let ticks: Bool
    /// The row under the finger now.
    private(set) var finger: Int

    /// A slide beginning on row `anchor`; nil on a row that cannot be ticked or outside the list.
    init?(rows: [Set<String>], ticked: Set<String>, anchor: Int) {
        guard rows.indices.contains(anchor), !rows[anchor].isEmpty else { return nil }
        self.rows = rows
        before = ticked
        self.anchor = anchor
        ticks = !rows[anchor].isSubset(of: ticked)
        finger = anchor
    }

    /// The finger over another row; beyond the list's start or end it stays at its first or last row.
    mutating func move(to row: Int) {
        finger = min(max(row, 0), rows.count - 1)
    }

    /// What is ticked now: the rows from the first to the finger's in the slide's state, every other row as before.
    var ticked: Set<String> {
        var result = before
        for index in min(anchor, finger)...max(anchor, finger) {
            if ticks { result.formUnion(rows[index]) } else { result.subtract(rows[index]) }
        }
        return result
    }
}

/// Which row the finger is over, from the rows' frames as the list laid them out (rows differ in height: a summed row, a
/// second line). A lazy list lays out only the rows near the screen, so `frames` holds those (by row index); a finger
/// beyond them is over the nearest one, and the slide's range still counts every row between by index.
nonisolated enum SlideRows {
    static func row(at y: CGFloat, frames: [Int: CGRect]) -> Int? {
        if let hit = frames.first(where: { $0.value.minY <= y && y < $0.value.maxY }) { return hit.key }
        return frames.min { distance(y, $0.value) < distance(y, $1.value) || (distance(y, $0.value) == distance(y, $1.value) && $0.key < $1.key) }?.key
    }

    private static func distance(_ y: CGFloat, _ frame: CGRect) -> CGFloat {
        y < frame.minY ? frame.minY - y : max(0, y - frame.maxY)
    }
}

/// Where a slide may start, decided within the touch's first points (`decision`), before the list's scrolling takes the
/// drag: on a row's circle column (the strip at the rows' left the slide made room for) a drag in any direction; elsewhere
/// on a row only a drag that starts clearly sideways (the row swipe's measure: the sideways part at least twice the
/// vertical), which may then turn up or down, as Photos selects. Anything else scrolls, as always.
nonisolated enum SlideStart {
    /// How far the finger moves before the slide or the scrolling decides (the row swipe's distance).
    static let decision: CGFloat = 6

    enum Place: Equatable {
        /// Not on a row that can be ticked: the touch is left to the list (taps, scrolling).
        case none
        /// On a row's circle column.
        case column
        /// On a row, outside its circle column.
        case row
    }

    /// Whether a drag that moved `dx`, `dy` from where it started begins a slide; nil while it has not moved `decision`
    /// points (still a tap, or not decided yet).
    static func begins(place: Place, dx: CGFloat, dy: CGFloat) -> Bool? {
        guard place != .none else { return false }
        guard hypot(dx, dy) >= decision else { return nil }
        switch place {
        case .none: return false
        case .column: return true
        case .row: return abs(dx) >= 2 * abs(dy)
        }
    }
}

/// The list scrolling by itself while a slide's finger is near the top or bottom edge of the list's visible part: the
/// closer to the edge (or past it), the faster; it stops at the list's start and end.
nonisolated enum SlideScroll {
    /// How far from the edge the scrolling starts: about one row.
    static let zone: CGFloat = 60
    /// The speed at the edge and beyond it, in points a second (about fifteen rows).
    static let fastest: CGFloat = 900

    /// The speed for a finger at `y` in a visible part reaching from `top` to `bottom` (all in one space): negative
    /// scrolls up (towards the list's start), positive down, 0 outside both zones. It grows with the square of how far
    /// into the zone the finger is, so the zone's edge creeps and the screen's edge runs.
    static func speed(fingerY y: CGFloat, top: CGFloat, bottom: CGFloat) -> CGFloat {
        let zone = min(Self.zone, max(0, (bottom - top) / 3))
        guard zone > 0 else { return 0 }
        if y < top + zone {
            let depth = min(1, (top + zone - y) / zone)
            return -fastest * depth * depth
        }
        if y > bottom - zone {
            let depth = min(1, (y - (bottom - zone)) / zone)
            return fastest * depth * depth
        }
        return 0
    }

    /// The offset after `seconds` at `speed`, kept between the list's start (`lowest`) and end (`highest`).
    static func step(offset: CGFloat, speed: CGFloat, seconds: Double, lowest: CGFloat, highest: CGFloat) -> CGFloat {
        let next = offset + speed * CGFloat(seconds)
        return min(max(next, lowest), max(lowest, highest))
    }
}
