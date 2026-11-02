import SwiftUI

// The tour's look (the logic is `Model/Tour.swift`; the veil, ring and card are the shared ones of
// `Shared/Design/TourPieces.swift`, as Aresium's tour has them). The real tabs run on the tour's world; each step lays a
// light veil in the wall's colour over the screen it names, leaves the part it is about clear with a ring in the app's
// violet, and shows one card in the app's glass at the bottom: "3 / 8", Skip, the step's title, one or two sentences,
// Next (Done at the last step) in the accent. Reduce Motion: nothing moves, the ring and the card change in place.

extension EnvironmentValues {
    /// The tour the screens run in; nil in the account's own app (the anchors, veil and card then do nothing). The
    /// shared pieces see it as the `tourGuide`.
    var tour: TourModel? {
        get { tourGuide as? TourModel }
        set { tourGuide = newValue }
    }
}

/// What the shared veil, ring and scrolling read.
extension TourModel: TourGuide {
    var spots: [AnyHashable] { targets.map(AnyHashable.init) }
    /// The part pointed at takes taps (a card opens its page, a row swipes, the magnifying glass searches); the rest
    /// waits for Next.
    var holdsTheRest: Bool { true }
    var ring: Color { Look.accent.color }
    /// The pages keep the card's room (`tourCardRoom`).
    var cardRoomInSafeArea: Bool { true }
}

extension View {
    /// Marks a part of a real screen the tour may point at (nothing outside the tour).
    func tourAnchor(_ spot: TourSpot?) -> some View { tourSpot(spot.map(AnyHashable.init)) }

    /// The tour's card at the bottom of a tab's stack (it stays put while pages are pushed, under the undo bar) or of a
    /// sheet's page.
    func tourCard() -> some View { modifier(TourCardInset()) }

    /// On each page of a tab's stack: the room the card takes at the bottom, so lists end and bars stand above it (a
    /// stack's inset does not reach its pages).
    func tourCardRoom() -> some View { modifier(TourCardRoom()) }
}

private struct TourCardInset: ViewModifier {
    @Environment(\.tour) private var tour

    func body(content: Content) -> some View {
        if let tour, tour.phase == .running {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                ArestemisTourCard(tour: tour)
                    .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                        if tour.cardRoom != height { tour.cardRoom = height }
                    }
            }
        } else {
            content
        }
    }
}

private struct TourCardRoom: ViewModifier {
    @Environment(\.tour) private var tour

    func body(content: Content) -> some View {
        if let tour, tour.phase == .running {
            content.safeAreaPadding(.bottom, tour.cardRoom)
        } else {
            content
        }
    }
}

/// The step's card (`TourCard`, shared): "3 / 8", Skip, the step's title and words, Next or Done in the accent.
private struct ArestemisTourCard: View {
    let tour: TourModel

    var body: some View {
        let last = tour.nextStep == nil
        TourCard(count: "\(tour.number) / \(tour.count)", title: tour.step.title(), text: Text(Self.words(tour.step)),
                 step: tour.step, leave: last ? nil : Text("Skip"), main: last ? Text("Done") : Text("Next"),
                 mainFill: Look.accent.color, mainInk: Look.onAccent,
                 // The searches' pulse moves under the card (`GlassCard.blur`, brief 87's rule).
                 blur: false,
                 onLeave: { tour.end() }, onMain: { tour.next() }) {
            EmptyView()
        }
    }

    /// The lines one under the other; a line about one kind is led by its name in ink.
    static func words(_ step: TourStep) -> AttributedString {
        var text = AttributedString()
        for (index, line) in step.lines().enumerated() {
            if index > 0 { text += AttributedString("\n") }
            if let label = line.label {
                var name = AttributedString(label + ": ")
                name.font = AppFont.text(14.5, weight: .semibold)
                name.foregroundColor = Ink.primary
                text += name
            }
            text += AttributedString(line.text)
        }
        return text
    }
}
