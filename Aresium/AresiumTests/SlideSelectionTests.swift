import CoreGraphics
import Testing
@testable import Aresium

/// Brief 200: selecting by sliding a finger over the rows, Mail's and Photos' rule. Ticking down, unticking from a ticked
/// row, the way back giving each row its earlier state, a summed row as one, a covered row passed over, the list's start
/// and end; which row the finger is over; where a slide may start; the edges' scrolling. Everything is made up.
struct SlideSelectionTests {
    /// Six single rows a…f.
    private let six: [Set<String>] = ["a", "b", "c", "d", "e", "f"].map { [$0] }

    @Test func aSlideDownFromAnUntickedRowTicksEveryRowItPasses() throws {
        var slide = try #require(SlideSelection(rows: six, ticked: [], anchor: 0))
        #expect(slide.ticks)
        #expect(slide.ticked == ["a"], "the first row at once")
        slide.move(to: 4)
        #expect(slide.ticked == ["a", "b", "c", "d", "e"])
        // Upwards from a lower row too.
        var up = try #require(SlideSelection(rows: six, ticked: [], anchor: 5))
        up.move(to: 3)
        #expect(up.ticked == ["d", "e", "f"])
    }

    @Test func aSlideFromATickedRowUnticks() throws {
        var slide = try #require(SlideSelection(rows: six, ticked: ["a", "b", "c"], anchor: 1))
        #expect(!slide.ticks)
        #expect(slide.ticked == ["a", "c"])
        slide.move(to: 3)
        #expect(slide.ticked == ["a"], "b and c unticked; d was not ticked and stays so")
    }

    @Test func theWayBackGivesEachRowItsEarlierState() throws {
        // b and d were ticked before; the slide starts on a (not ticked), so it ticks.
        var slide = try #require(SlideSelection(rows: six, ticked: ["b", "d"], anchor: 0))
        slide.move(to: 4)
        #expect(slide.ticked == ["a", "b", "c", "d", "e"])
        slide.move(to: 1)
        #expect(slide.ticked == ["a", "b", "d"], "c and e unticked again, d stays ticked as it was")
        slide.move(to: 0)
        #expect(slide.ticked == ["a", "b", "d"])
        // Past the first row the other way: the rows above take the slide's state, the rows below are as before.
        var turn = try #require(SlideSelection(rows: six, ticked: ["e"], anchor: 3))
        turn.move(to: 5)
        #expect(turn.ticked == ["d", "e", "f"])
        turn.move(to: 1)
        #expect(turn.ticked == ["b", "c", "d", "e"], "f back to unticked, e ticked as before")
        // Unticking: the rows left again come back ticked.
        var untick = try #require(SlideSelection(rows: six, ticked: ["a", "b", "c", "d"], anchor: 0))
        untick.move(to: 3)
        #expect(untick.ticked.isEmpty)
        untick.move(to: 1)
        #expect(untick.ticked == ["c", "d"])
    }

    @Test func aSummedRowCountsAsOneRow() throws {
        let rows: [Set<String>] = [["p1", "p2", "p3"], ["p4"], ["p5"]]
        var slide = try #require(SlideSelection(rows: rows, ticked: [], anchor: 0))
        #expect(slide.ticked == ["p1", "p2", "p3"], "all its payments at once")
        slide.move(to: 1)
        #expect(slide.ticked == ["p1", "p2", "p3", "p4"])
        // Partly ticked reads as not ticked (as its circle shows it): the slide ticks it whole.
        let partly = try #require(SlideSelection(rows: rows, ticked: ["p1"], anchor: 0))
        #expect(partly.ticks && partly.ticked == ["p1", "p2", "p3"])
        // Wholly ticked: the slide unticks all its payments.
        var whole = try #require(SlideSelection(rows: rows, ticked: ["p1", "p2", "p3", "p5"], anchor: 0))
        whole.move(to: 2)
        #expect(!whole.ticks && whole.ticked.isEmpty)
        // Reached from another row, a summed row also goes whole.
        var fromBelow = try #require(SlideSelection(rows: rows, ticked: [], anchor: 2))
        fromBelow.move(to: 0)
        #expect(fromBelow.ticked == ["p1", "p2", "p3", "p4", "p5"])
    }

    @Test func aCoveredRowIsPassedOver() throws {
        let rows: [Set<String>] = [["a"], [], ["c"]]
        var slide = try #require(SlideSelection(rows: rows, ticked: [], anchor: 0))
        slide.move(to: 2)
        #expect(slide.ticked == ["a", "c"])
        slide.move(to: 1)
        #expect(slide.ticked == ["a"], "over the covered row: nothing of it ticked")
        #expect(SlideSelection(rows: rows, ticked: [], anchor: 1) == nil, "no slide starts on a covered row")
    }

    @Test func theListsStartAndEndHoldTheFinger() throws {
        var slide = try #require(SlideSelection(rows: six, ticked: [], anchor: 2))
        slide.move(to: -3)
        #expect(slide.finger == 0 && slide.ticked == ["a", "b", "c"])
        slide.move(to: 99)
        #expect(slide.finger == 5 && slide.ticked == ["c", "d", "e", "f"])
        #expect(SlideSelection(rows: six, ticked: [], anchor: 6) == nil)
        #expect(SlideSelection(rows: [], ticked: [], anchor: 0) == nil)
    }

    // MARK: the finger's row

    @Test func theFingersRowComesFromTheRowsFrames() {
        // Rows of different heights (a summed row, a second line), as the list laid them out.
        let frames: [Int: CGRect] = [0: CGRect(x: 0, y: 0, width: 378, height: 60),
                                     1: CGRect(x: 0, y: 60, width: 378, height: 74),
                                     2: CGRect(x: 0, y: 134, width: 378, height: 60)]
        #expect(SlideRows.row(at: 10, frames: frames) == 0)
        #expect(SlideRows.row(at: 60, frames: frames) == 1, "a row's top edge is its own")
        #expect(SlideRows.row(at: 133.5, frames: frames) == 1)
        #expect(SlideRows.row(at: 150, frames: frames) == 2)
        #expect(SlideRows.row(at: -40, frames: frames) == 0, "above the list: its first row")
        #expect(SlideRows.row(at: 900, frames: frames) == 2, "below it: its last row")
        // A lazy list laid out rows 10 to 12 only: above them the finger is over the nearest of them.
        let lazy: [Int: CGRect] = [10: CGRect(x: 0, y: 600, width: 378, height: 60),
                                   11: CGRect(x: 0, y: 660, width: 378, height: 60),
                                   12: CGRect(x: 0, y: 720, width: 378, height: 60)]
        #expect(SlideRows.row(at: 580, frames: lazy) == 10)
        #expect(SlideRows.row(at: 700, frames: lazy) == 11)
        #expect(SlideRows.row(at: 800, frames: [:]) == nil)
    }

    // MARK: where a slide starts

    @Test func onTheCircleColumnAnyDragSlides() {
        #expect(SlideStart.begins(place: .column, dx: 0, dy: 3) == nil, "not decided before 6 pt: still a tap")
        #expect(SlideStart.begins(place: .column, dx: 0, dy: 6) == true, "straight down")
        #expect(SlideStart.begins(place: .column, dx: 1, dy: -8) == true, "straight up")
        #expect(SlideStart.begins(place: .column, dx: 7, dy: 0) == true, "sideways")
    }

    @Test func elsewhereOnARowOnlyASidewaysStartSlides() {
        #expect(SlideStart.begins(place: .row, dx: 8, dy: 2) == true, "sideways, then it may turn")
        #expect(SlideStart.begins(place: .row, dx: -8, dy: 3) == true, "to the left too")
        #expect(SlideStart.begins(place: .row, dx: 1, dy: 8) == false, "vertical: the list scrolls")
        #expect(SlideStart.begins(place: .row, dx: 8, dy: 5) == false, "slanted: the list scrolls")
        #expect(SlideStart.begins(place: .row, dx: 2, dy: 2) == nil)
        #expect(SlideStart.begins(place: .none, dx: 0, dy: 0) == false, "off the rows: never")
    }

    // MARK: the edges

    @Test func theListScrollsFasterTheCloserTheFingerIsToAnEdge() {
        let top: CGFloat = 0, bottom: CGFloat = 660, zone = SlideScroll.zone
        #expect(SlideScroll.speed(fingerY: 330, top: top, bottom: bottom) == 0, "in the middle: still")
        #expect(SlideScroll.speed(fingerY: bottom - zone, top: top, bottom: bottom) == 0, "at the zone's edge: still")
        #expect(SlideScroll.speed(fingerY: bottom - zone / 2, top: top, bottom: bottom) == SlideScroll.fastest / 4)
        #expect(SlideScroll.speed(fingerY: bottom, top: top, bottom: bottom) == SlideScroll.fastest)
        #expect(SlideScroll.speed(fingerY: bottom + 80, top: top, bottom: bottom) == SlideScroll.fastest, "past the edge")
        #expect(SlideScroll.speed(fingerY: zone / 2, top: top, bottom: bottom) == -SlideScroll.fastest / 4, "up")
        #expect(SlideScroll.speed(fingerY: -50, top: top, bottom: bottom) == -SlideScroll.fastest)
        let near = SlideScroll.speed(fingerY: bottom - 10, top: top, bottom: bottom)
        let far = SlideScroll.speed(fingerY: bottom - 40, top: top, bottom: bottom)
        #expect(near > far && far > 0)
        // A short visible part: each zone at most a third of it, so its middle stays still.
        #expect(SlideScroll.speed(fingerY: 45, top: 0, bottom: 90) == 0)
        #expect(SlideScroll.speed(fingerY: 0, top: 0, bottom: 0) == 0)
    }

    @Test func theEdgesScrollingStopsAtTheListsStartAndEnd() {
        #expect(SlideScroll.step(offset: 100, speed: 600, seconds: 0.5, lowest: 0, highest: 1000) == 400)
        #expect(SlideScroll.step(offset: 900, speed: 600, seconds: 0.5, lowest: 0, highest: 1000) == 1000, "the end")
        #expect(SlideScroll.step(offset: 100, speed: -600, seconds: 0.5, lowest: 0, highest: 1000) == 0, "the start")
        #expect(SlideScroll.step(offset: 0, speed: 600, seconds: 0.5, lowest: 0, highest: -20) == 0,
                "a list shorter than the screen does not scroll")
    }
}

/// The slide on a list's rows as the screen measures them (`SlideTracker`): the touch's place, the first row, the finger's
/// row from the rows' frames, and what it ticks through the list's selection. No scroll view (the edges stay still).
@MainActor
struct SlideTrackerTests {
    /// Five rows of 60 pt (the third a summed row of two payments, the fourth a covered row) and the selection they tick.
    private func tracker(ticked: Set<String> = []) -> (SlideTracker, () -> Set<String>) {
        let tracker = SlideTracker()
        let rows: [SlideTracker.Row] = [("r1", ["a"]), ("r2", ["b"]), ("sum", ["c1", "c2"]), ("covered", []), ("r5", ["e"])]
        tracker.shownRows = { rows }
        for (index, row) in rows.enumerated() {
            tracker.frames[row.id] = CGRect(x: 12, y: 8 + CGFloat(index) * 60, width: 378, height: 60)
        }
        var selection = ticked
        tracker.ticked = { selection }
        tracker.tick = { selection = $0 }
        return (tracker, { selection })
    }

    @Test func theTouchesPlace() {
        let (tracker, _) = tracker()
        #expect(tracker.place(at: CGPoint(x: 30, y: 30)) == .column)
        #expect(tracker.place(at: CGPoint(x: -6, y: 30)) == .column, "the list's margin left of the rows")
        #expect(tracker.place(at: CGPoint(x: 12 + SelectionLook.column - 1, y: 30)) == .column)
        #expect(tracker.place(at: CGPoint(x: 12 + SelectionLook.column + 1, y: 30)) == .row)
        #expect(tracker.place(at: CGPoint(x: 30, y: 8 + 3 * 60 + 20)) == .none, "a covered row")
        #expect(tracker.place(at: CGPoint(x: 30, y: 400)) == .none, "below the rows")
        tracker.ticked = { nil }
        #expect(tracker.place(at: CGPoint(x: 30, y: 30)) == .none, "not selecting")
    }

    @Test func aSlideTicksThroughTheRowsFramesAndTheWayBackRestores() {
        let (tracker, selection) = tracker(ticked: ["e"])
        let start = CGPoint(x: 30, y: 38)
        _ = tracker.place(at: start)
        tracker.begin(start: start, list: CGPoint(x: 30, y: 44), viewport: CGPoint(x: 30, y: 44))
        #expect(tracker.isSliding && selection() == ["a", "e"])
        tracker.move(list: CGPoint(x: 32, y: 8 + 2 * 60 + 30), viewport: .zero)
        #expect(selection() == ["a", "b", "c1", "c2", "e"], "the summed row whole")
        tracker.move(list: CGPoint(x: 32, y: 8 + 4 * 60 + 30), viewport: .zero)
        #expect(selection() == ["a", "b", "c1", "c2", "e"], "the covered row passed over, e was ticked already")
        tracker.move(list: CGPoint(x: 32, y: 8 + 60 + 10), viewport: .zero)
        #expect(selection() == ["a", "b", "e"], "back up: the summed row unticked again")
        tracker.end()
        #expect(!tracker.isSliding && selection() == ["a", "b", "e"], "what is ticked stays")
    }

    @Test func aSlideEndsWhenTheListChangesUnderIt() {
        let (tracker, selection) = tracker()
        let start = CGPoint(x: 30, y: 38)
        _ = tracker.place(at: start)
        tracker.begin(start: start, list: start, viewport: start)
        #expect(selection() == ["a"])
        tracker.shownRows = { [("r2", ["b"]), ("r1", ["a"])] }
        tracker.move(list: CGPoint(x: 30, y: 8 + 60 + 10), viewport: .zero)
        #expect(!tracker.isSliding && selection() == ["a"])
    }
}
