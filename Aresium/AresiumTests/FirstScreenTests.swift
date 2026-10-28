import Foundation
import Testing
@testable import Aresium

/// The first screen (brief 25): phone mode without data shows "No data yet", the tour shows in its place while it runs,
/// and the first screen comes back after the tour (finished or ended early) while there is no data: the made-up data is
/// never shown outside the tour. (Import data and the category picker after it: `ImportThenCategoriesTests`.)
@MainActor
struct FirstScreenTests {
    /// 27 Oct 2026, noon, as the tour's tests.
    private static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!

    private static func parent() -> URL {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "build/25-test-tours/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// What the app shows for the person's phone store and the tour, as ContentView asks.
    private func screen(_ person: PhoneBackend, tour: TourModel?) -> MainScreen {
        MainScreen.choose(tour: tour?.phase, hasMode: true, waitsForServerLogin: false,
                          phoneRecords: person.summary.payments + person.summary.receipts)
    }

    @Test func whatShows() {
        #expect(MainScreen.choose(tour: nil, hasMode: true, waitsForServerLogin: false, phoneRecords: 0) == .firstScreen)
        #expect(MainScreen.choose(tour: nil, hasMode: true, waitsForServerLogin: false, phoneRecords: 12) == .dashboard)
        // Server mode (no phone store) never shows the first screen.
        #expect(MainScreen.choose(tour: nil, hasMode: true, waitsForServerLogin: false, phoneRecords: nil) == .dashboard)
        #expect(MainScreen.choose(tour: nil, hasMode: true, waitsForServerLogin: true, phoneRecords: nil) == .waitingForLogin)
        #expect(MainScreen.choose(tour: nil, hasMode: false, waitsForServerLogin: false, phoneRecords: nil) == .opening)
        // The tour, from the moment it is asked for until it ends, over anything.
        for phase: TourModel.Phase in [.preparing, .running, .failed("x")] {
            #expect(MainScreen.choose(tour: phase, hasMode: true, waitsForServerLogin: false, phoneRecords: 0) == .tour)
        }
        #expect(MainScreen.choose(tour: .ended, hasMode: true, waitsForServerLogin: false, phoneRecords: 0) == .firstScreen)
    }

    /// Without data: the first screen; the tour in its place; after the tour (to its end, or ended at any step) the first
    /// screen again, and the person's store still has no payment.
    @Test(arguments: [TourStep.welcome, .category, .lock, .contact, .done])
    func theFirstScreenComesBackAfterTheTour(endAt step: TourStep) async throws {
        let person = try await PhoneTest.backend()
        #expect(screen(person, tour: nil) == .firstScreen)

        let tour = TourModel { try await TourWorld.make(in: Self.parent(), now: Self.now, makeEngine: { try PhoneTest.engine() }) }
        #expect(screen(person, tour: tour) == .tour, "the tour shows while its store is made")
        await tour.start(at: step)
        #expect(tour.phase == .running && screen(person, tour: tour) == .tour)
        #expect(try #require(tour.world).phone.summary.payments > 100)
        if step == .done { tour.next() } else { tour.end() }           // finished, or End tour

        #expect(tour.phase == .ended)
        #expect(screen(person, tour: tour) == .firstScreen)
        #expect(screen(person, tour: nil) == .firstScreen)
        try await person.refresh()
        #expect(person.summary.payments == 0, "the made-up data never reaches the person's store")
        #expect(screen(person, tour: nil) == .firstScreen)
    }
}
