import SwiftUI
import UIKit
import os

// Selecting by sliding a finger over the rows (brief 200, Patrik 2026-11-02, Mail's slide in its Edit mode): while a
// category's month list selects, a drag that starts on a row's circle column ticks the row it started on and every row
// the finger passes on its way; going back unticks the rows it leaves again (back to how they were before). A drag that
// starts sideways elsewhere on a row and then turns up or down does the same (Photos'); a vertical drag there scrolls,
// as always. Near the list's top or bottom edge the list scrolls by itself, faster the closer the finger is, and the
// rows coming into view are ticked as they pass under it. The rule is `Model/SlideSelection.swift`.
//
// The pieces: the rows report their frames in the list's own layout (`slideRow`, never a fixed height); one UIKit pan
// over the whole list (`SlideSelectRecognizer`, in the row swipe's manner: SwiftUI's own drag fought the scroll view
// there, and a plain recognizer got no moves inside it) decides within its first points and, while it decides, holds
// the list's scrolling back; `SlideTracker` turns its points into rows, ticks them and scrolls at the edges (SwiftUI's
// `ScrollPosition`, a display link while the finger is in an edge zone). VoiceOver is unchanged: the rows stay
// selectable one by one; the slide is a shortcut.

/// The coordinate spaces the slide measures in: the list's rows (they move with the list as it scrolls) and the scroll
/// view's frame (it stays where it is).
nonisolated enum SlideSpace {
    static let list = "slideSelectList"
    static let viewport = "slideSelectViewport"
}

/// One list's slide between frames: the rows (their payments, in order) and their frames, the scroll view's geometry, the
/// slide under way and the finger. Kept by the list's screen (`@State`), read and written by the gesture and the rows'
/// frames, never drawn: nothing here makes the list draw again; a slide changes the list's selection through `tick`.
@MainActor
final class SlideTracker {
    /// One row of the list: its id and the payments it stands for (empty: not tickable).
    typealias Row = (id: String, members: Set<String>)

    /// The list's rows in order, as the list shows them now.
    var shownRows: () -> [Row] = { [] }
    /// The rows' frames in the list's space, as last laid out (a lazy list lays out the rows near the screen only).
    var frames: [String: CGRect] = [:]
    /// The scroll view's geometry, as last scrolled or laid out.
    var geometry: ScrollGeometry?
    /// What is ticked now; nil while the list does not select.
    var ticked: () -> Set<String>? = { nil }
    /// A slide's new ticked set for the list's selection (the screen also gives a light haptic for it).
    var tick: (Set<String>) -> Void = { _ in }
    /// Scrolls the list to a content offset (the edges' scrolling).
    var scrollTo: (CGFloat) -> Void = { _ in }

    /// The rows as the touch went down.
    private var rows: [Row] = []
    /// The slide under way.
    private var slide: SlideSelection?
    /// The rows' ids as the slide began: a list that changes meanwhile ends it.
    private var slideRows: [String] = []
    /// The finger: in the list's space (its row) and in the scroll view's (the edges'). While the edges scroll, the finger
    /// stays put in the scroll view and moves through the list by what was scrolled.
    private var finger: (list: CGPoint, viewport: CGPoint)?
    /// The content offset as the slide last knew or set it.
    private var offset: CGFloat = 0
    private var link: CADisplayLink?
    private var linkTarget: DisplayLinkTarget?
    private var lastTick: CFTimeInterval?
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "slide")

    var isSliding: Bool { slide != nil }

    /// Where a touch at this point of the list starts: a row's circle column (from the list's margin to where the row's
    /// day tile starts), elsewhere on a tickable row, or nothing a slide starts from (no row there, a covered row, the
    /// list not selecting).
    func place(at point: CGPoint) -> SlideStart.Place {
        rows = shownRows()
        guard ticked() != nil, let index = rowIndex(containing: point.y), !rows[index].members.isEmpty,
              let frame = frames[rows[index].id] else { return .none }
        return point.x < frame.minX + SelectionLook.column ? .column : .row
    }

    /// The slide begins: on the row under `start` (where the touch went down), the finger now at `list`.
    func begin(start: CGPoint, list: CGPoint, viewport: CGPoint) {
        guard let ticked = ticked(), let anchor = rowIndex(containing: start.y),
              let slide = SlideSelection(rows: rows.map(\.members), ticked: ticked, anchor: anchor) else { return }
        self.slide = slide
        slideRows = rows.map(\.id)
        offset = geometry?.contentOffset.y ?? 0
        Self.log.debug("slide begins on row \(anchor, privacy: .public), \(slide.ticks ? "ticking" : "unticking", privacy: .public)")
        apply(slide.ticked)
        move(list: list, viewport: viewport)
    }

    /// The finger moved.
    func move(list: CGPoint, viewport: CGPoint) {
        guard slide != nil else { return }
        guard slideRows == shownRows().map(\.id) else { return end() }    // the list changed under the finger
        finger = (list, viewport)
        follow()
        edges()
    }

    /// The finger lifted, or the slide was cancelled: what is ticked stays.
    func end() {
        if let slide { Self.log.debug("slide ends on row \(slide.finger, privacy: .public)") }
        slide = nil
        finger = nil
        stopScrolling()
    }

    // MARK: rows

    /// The row whose frame holds `y` (list space), by index; nil between or beyond the rows.
    private func rowIndex(containing y: CGFloat) -> Int? {
        rows.firstIndex { row in frames[row.id].map { $0.minY <= y && y < $0.maxY } ?? false }
    }

    /// The rows laid out now, by index.
    private var laidOut: [Int: CGRect] {
        var result: [Int: CGRect] = [:]
        for (index, row) in rows.enumerated() { if let frame = frames[row.id] { result[index] = frame } }
        return result
    }

    /// The slide follows the finger's row.
    private func follow() {
        guard var slide, let finger, let row = SlideRows.row(at: finger.list.y, frames: laidOut) else { return }
        let before = slide.ticked
        slide.move(to: row)
        self.slide = slide
        let now = slide.ticked
        if now != before { apply(now) }
    }

    private func apply(_ ticked: Set<String>) {
        if ticked != self.ticked() { tick(ticked) }
    }

    // MARK: the edges

    /// The visible part of the list in the scroll view's space: below its top inset and above the bar and the home
    /// indicator (`ScrollGeometry`'s insets).
    private var visible: (top: CGFloat, bottom: CGFloat)? {
        guard let geometry else { return nil }
        return (geometry.contentInsets.top, geometry.contentInsets.top + geometry.containerSize.height)
    }

    /// Starts or stops scrolling as the finger enters or leaves an edge's zone.
    private func edges() {
        guard let finger, let visible else { return stopScrolling() }
        if SlideScroll.speed(fingerY: finger.viewport.y, top: visible.top, bottom: visible.bottom) == 0 {
            stopScrolling()
        } else if link == nil {
            let target = DisplayLinkTarget { [weak self] link in
                guard let self else { return link.invalidate() }          // the list's screen is gone
                scrollStep(link)
            }
            let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
            linkTarget = target
            lastTick = nil
        }
    }

    private func stopScrolling() {
        link?.invalidate()
        link = nil
        linkTarget = nil
        lastTick = nil
    }

    /// One frame of the edges' scrolling: the list moves under the still finger, so the finger is over the rows further
    /// on, which the slide then takes.
    private func scrollStep(_ link: CADisplayLink) {
        defer { lastTick = link.timestamp }
        guard let last = lastTick else { return }
        guard slide != nil, var finger, let visible, let limits = scrollLimits(visible: visible) else { return stopScrolling() }
        let speed = SlideScroll.speed(fingerY: finger.viewport.y, top: visible.top, bottom: visible.bottom)
        guard speed != 0 else { return stopScrolling() }
        let next = SlideScroll.step(offset: offset, speed: speed, seconds: min(link.timestamp - last, 1.0 / 30),
                                    lowest: limits.lowest, highest: limits.highest)
        guard next != offset else { return }
        finger.list.y += next - offset
        offset = next
        self.finger = finger
        scrollTo(next)
        follow()
    }

    /// How far the edges may scroll: from the content's top to where the list's last row stands just above the visible
    /// part's bottom (the band after the list is not scrolled to); until the last row is laid out, the content's end.
    private func scrollLimits(visible: (top: CGFloat, bottom: CGFloat)) -> (lowest: CGFloat, highest: CGFloat)? {
        guard let geometry, let finger else { return nil }
        let lowest = -geometry.contentInsets.top
        // The content's end under the visible part's bottom (the scroll view's own furthest offset).
        let contentEnd = geometry.contentSize.height - visible.bottom
        // The list's top in the content: where the finger is in the content, less where it is in the list.
        let listTop = finger.viewport.y + offset - finger.list.y
        guard let last = rows.last, let frame = frames[last.id] else { return (lowest, max(lowest, contentEnd)) }
        let lastRow = listTop + frame.maxY - visible.bottom + 8
        return (lowest, max(lowest, min(contentEnd, lastRow)))
    }
}

/// A display link's target (it holds its target strongly, so the tracker is not it).
private final class DisplayLinkTarget: NSObject {
    let action: (CADisplayLink) -> Void
    init(_ action: @escaping (CADisplayLink) -> Void) { self.action = action }
    @objc func step(_ link: CADisplayLink) { action(link) }
}

extension View {
    /// A row of a list that selects by sliding: its frame in the list's space, for the tracker.
    func slideRow(_ id: String, in tracker: SlideTracker) -> some View {
        onGeometryChange(for: CGRect.self) { $0.frame(in: .named(SlideSpace.list)) } action: { tracker.frames[id] = $0 }
    }

    /// The list selects by sliding while `enabled`. Put it on the rows' container with its margins, so a drag from the
    /// margin left of the rows starts on the circle column too. Its space is the list's (`SlideSpace.list`), around the
    /// gesture, so the gesture's points and the rows' frames are measured in the same place.
    func slideSelects(_ tracker: SlideTracker, enabled: Bool) -> some View {
        contentShape(Rectangle())
            .gesture(SlideSelectGesture(tracker: tracker, enabled: enabled))
            .coordinateSpace(.named(SlideSpace.list))
    }

    /// The scroll view around a list that selects by sliding: its geometry and its position for the edges' scrolling.
    func slideViewport(_ tracker: SlideTracker, position: Binding<ScrollPosition>) -> some View {
        coordinateSpace(.named(SlideSpace.viewport))
            .scrollPosition(position)
            .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, geometry in tracker.geometry = geometry }
    }
}

/// The slide's pan over the whole list (`SlideSelectRecognizer`), its points turned into the list's and the scroll view's
/// spaces for the tracker.
private struct SlideSelectGesture: UIGestureRecognizerRepresentable {
    let tracker: SlideTracker
    let enabled: Bool

    final class Coordinator {
        let converter: CoordinateSpaceConverter
        init(converter: CoordinateSpaceConverter) { self.converter = converter }
    }

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(converter: converter) }

    func makeUIGestureRecognizer(context: Context) -> SlideSelectRecognizer {
        let recognizer = SlideSelectRecognizer()
        recognizer.maximumNumberOfTouches = 1
        let coordinator = context.coordinator
        recognizer.place = { [tracker] window in
            tracker.place(at: coordinator.converter.convert(globalPoint: window, to: .named(SlideSpace.list)))
        }
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: SlideSelectRecognizer, context: Context) {
        recognizer.isEnabled = enabled
        if !enabled { tracker.end() }
    }

    func handleUIGestureRecognizerAction(_ recognizer: SlideSelectRecognizer, context: Context) {
        let converter = context.coordinator.converter
        let window = recognizer.location(in: nil)
        let list = converter.convert(globalPoint: window, to: .named(SlideSpace.list))
        let viewport = converter.convert(globalPoint: window, to: .named(SlideSpace.viewport))
        switch recognizer.state {
        case .began:
            let start = recognizer.start.map { converter.convert(globalPoint: $0, to: .named(SlideSpace.list)) } ?? list
            tracker.begin(start: start, list: list, viewport: viewport)
        case .changed:
            tracker.move(list: list, viewport: viewport)
        case .ended, .cancelled, .failed:
            tracker.end()
        default:
            break
        }
    }
}

/// A one-finger pan that is only a slide over the rows (`SlideStart`): at the touch's start it asks where it is (`place`)
/// and fails at once off the rows; within its first points it begins (the circle column: any direction; elsewhere on a
/// row: clearly sideways) or fails, leaving the touch to the list's scrolling and the rows' taps. A pan, as the row
/// swipe's (`RowSwipeRecognizer`): a plain recognizer got no moves inside the scroll view. The list's scrolling waits for
/// it to decide (`shouldBeRequiredToFail`), so a drag on the circle column never scrolls instead; a vertical drag
/// elsewhere is decided after 6 pt and scrolls as before.
final class SlideSelectRecognizer: UIPanGestureRecognizer {
    /// Where a touch at this window point starts (asked once, as it goes down).
    var place: ((CGPoint) -> SlideStart.Place)?
    /// Where the touch went down, in the window.
    private(set) var start: CGPoint?
    private var startPlace = SlideStart.Place.none

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        guard start == nil, let point = touches.first?.location(in: nil) else { return }
        start = point
        startPlace = place?(point) ?? .none
        if startPlace == .none { state = .failed }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        if state == .possible, let start, let point = touches.first?.location(in: nil) {
            switch SlideStart.begins(place: startPlace, dx: point.x - start.x, dy: point.y - start.y) {
            case false?:
                state = .failed
                return
            case true?:
                super.touchesMoved(touches, with: event)
                if state == .possible { state = .began }       // at once, not after the pan's own distance
                return
            case nil:
                break
            }
        }
        super.touchesMoved(touches, with: event)
    }

    override func reset() {
        super.reset()
        start = nil
        startPlace = .none
    }

    /// The list's own scrolling waits while this decides (only while the list selects).
    override func shouldBeRequiredToFail(by other: UIGestureRecognizer) -> Bool {
        if isEnabled, let scroll = other.view as? UIScrollView, other === scroll.panGestureRecognizer { return true }
        return super.shouldBeRequiredToFail(by: other)
    }
}
