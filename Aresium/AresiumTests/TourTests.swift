import Foundation
import Testing
@testable import Aresium

/// The tour (brief 24): its steps go on when the person does the thing or taps Next, and it runs on a made-up store of
/// its own that is deleted when it ends, at any step, without touching the person's store.
@MainActor
struct TourTests {
    /// 27 Oct 2026, noon: the made-up months end in October.
    private static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!

    /// A folder of the test's own in the worktree's build folder; the tour makes its own folder inside.
    private static func parent() -> URL {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "build/24-test-tours/\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func model(in parent: URL) -> TourModel {
        TourModel { try await TourWorld.make(in: parent, now: now, makeEngine: { try PhoneTest.engine() }) }
    }

    /// The tour's folders in `parent`.
    private static func tourFolders(in parent: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(TourWorld.folderPrefix) }
    }

    /// Waits (up to 10 s) until `condition` holds; the follow-up question's answer finishes in a task of its own.
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    @Test func eachStepGoesOnWhenThePersonDoesTheThing() async throws {
        let parent = Self.parent()
        let tour = Self.model(in: parent)
        await tour.start()
        #expect(tour.phase == .running)
        #expect(tour.step == .welcome)
        #expect(tour.target == nil)
        let world = try #require(tour.world)
        #expect(world.root.deletingLastPathComponent().standardizedFileURL == parent.standardizedFileURL)
        #expect(world.phone.summary.payments > 100)

        tour.next()
        #expect(tour.step == .income)
        #expect(tour.target == .pageDots)
        var place = tour.place
        place.side = .income                                   // the swipe
        tour.update(place)
        #expect(tour.step == .overview)
        #expect(tour.target == .range)
        #expect(tour.place.side == .income, "the income page stays")

        place = tour.place
        place.current = false                                  // Overview
        tour.update(place)
        #expect(tour.step == .graph)
        #expect(tour.target == .graph)
        #expect(!tour.place.current, "Overview stays for the graph")

        place = tour.place
        place.graph = true
        tour.update(place)
        #expect(tour.step == .category)
        #expect(tour.place.graph, "the graph stays open")
        #expect(tour.place.current && tour.place.side == .expenses, "back on this month's expenses")
        let groceries = try #require(world.firstCategory)
        #expect(tour.target == .category(groceries))

        place = tour.place
        place.path.append(world.dashboard.route(category: groceries, side: .expenses, current: true))   // the row
        tour.update(place)
        #expect(tour.step == .payment)
        let first = try #require(world.dashboard.transactions(category: groceries, month: "2026-10", side: .expenses).first)
        #expect(tour.target == .payment(first.transaction.id))

        place = tour.place
        place.payment = first.transaction                       // the payment's detail
        tour.update(place)
        #expect(tour.step == .switchCategory)
        #expect(tour.target == .change)

        // Change → another category → Save: the shop question comes, as in real use; the answer moves on.
        let detail = world.dashboard.transactionDetailStore(for: first.transaction)
        await detail.load()
        detail.beginRecategorisation()
        let eatingOut = try #require(try await world.phone.categories().name(of: "eating-out"))
        detail.select(eatingOut)
        await detail.save()
        let question = try #require(detail.followUp)
        #expect(question.count > 3)
        #expect(tour.step == .switchCategory, "still waiting for the answer")
        detail.answer(moveOthers: true)
        await eventually { tour.step == .categories }
        #expect(tour.step == .categories)
        #expect(tour.place.payment == nil, "the payment closes")
        #expect(tour.target == .settings)

        tour.openSettings()
        #expect(tour.target == .categoriesRow)
        tour.setCategoriesShown(true)
        #expect(tour.target == nil, "free to choose and add categories")
        try await world.phone.addCustom(named: "Fiktiv-Kategorie")
        tour.next()
        #expect(tour.step == .importFiles)
        #expect(!tour.showsSettings && tour.place.path.isEmpty)
        #expect(tour.target == .importButton)

        tour.importTapped()
        #expect(tour.step == .done)
        #expect(tour.target == nil)
        tour.next()
        #expect(tour.phase == .ended)
        #expect(Self.tourFolders(in: parent).isEmpty, "the made-up store is deleted")
    }

    @Test func nextGetsEachStepsScreenReady() async throws {
        let parent = Self.parent()
        let tour = Self.model(in: parent)
        await tour.start()
        var seen: [TourStep] = [tour.step]
        while tour.phase == .running {
            switch tour.step {
            case .payment:
                #expect(tour.place.path.last?.month == "2026-10", "this month's payments of a category")
                #expect(tour.target != nil)
            case .switchCategory:
                #expect(tour.place.payment != nil, "a payment's detail")
                #expect(tour.target == .change)
            case .categories:
                #expect(tour.place.payment == nil)
                #expect(tour.target == .settings)
            case .importFiles, .welcome, .done:
                #expect(tour.place.path.isEmpty && tour.place.payment == nil)
            default:
                #expect(tour.place.path.isEmpty)
                #expect(tour.target != nil)
            }
            tour.next()
            if tour.phase == .running { seen.append(tour.step) }
        }
        #expect(seen == TourStep.allCases)
        #expect(Self.tourFolders(in: parent).isEmpty)
    }

    /// Ending at any step: the person's store is as it was, the tour's folder is gone.
    @Test(arguments: TourStep.allCases)
    func endingAtAnyStepLeavesThePersonsStoreAndDeletesTheTours(step: TourStep) async throws {
        // The person's own store, with payments, categories and a learned shop.
        let personal = PhoneTest.storage()
        let person = try await PhoneTest.backend(storage: personal, chosen: ["groceries", "eating-out"])
        _ = try await person.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000),
                                                           ("02.10.2026", "Fiktiv Laden", "Einkauf", -500)])],
                                         auth: BackendAuth(token: nil))
        let payment = try #require(try await person.ledger.payments().first)
        let eatingOut = try #require(try await person.categories().name(of: "eating-out"))
        _ = try await person.switchCategory(id: payment.id, to: eatingOut, auth: BackendAuth(token: nil))
        let before = try await person.ledger.export(on: Self.now)

        let parent = Self.parent()
        let tour = Self.model(in: parent)
        await tour.start(at: step)
        #expect(tour.step == step)
        let world = try #require(tour.world)
        #expect(!world.root.path.hasPrefix(personal.root.path) && !personal.root.path.hasPrefix(world.root.path))
        // Changes in the tour: a payment moved and its shop learned, a category of one's own.
        let moved = try #require(try await world.phone.ledger.payments().first)
        _ = try await world.phone.switchCategory(id: moved.id, to: eatingOut, auth: BackendAuth(token: nil))
        try await world.phone.addCustom(named: "Tour-Kategorie")
        #expect(FileManager.default.fileExists(atPath: world.root.path))

        tour.end()
        #expect(tour.phase == .ended)
        #expect(tour.world == nil)
        #expect(!FileManager.default.fileExists(atPath: world.root.path))
        #expect(Self.tourFolders(in: parent).isEmpty)
        #expect(try await person.ledger.export(on: Self.now) == before, "the person's store is untouched")
        // Opened again from the disk: the same.
        let reopened = try await PhoneTest.backend(storage: personal)
        #expect(try await reopened.ledger.export(on: Self.now) == before)
    }

    @Test func endingWhileTheStoreIsMadeDeletesIt() async throws {
        let parent = Self.parent()
        var tour: TourModel?
        let model = TourModel {
            tour?.end()                                         // "End tour" while the store is being filled
            return try await TourWorld.make(in: parent, now: Self.now, makeEngine: { try PhoneTest.engine() })
        }
        tour = model
        await model.start()
        #expect(model.phase == .ended)
        #expect(model.world == nil)
        #expect(Self.tourFolders(in: parent).isEmpty)
    }

    @Test func leftoverToursAreRemovedAndNothingElse() throws {
        let parent = Self.parent()
        let left = parent.appending(path: TourWorld.folderPrefix + "left")
        let other = parent.appending(path: "aresium-sample-phone-kept")
        for folder in [left, other] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        TourWorld.removeLeftovers(in: parent)
        #expect(!FileManager.default.fileExists(atPath: left.path))
        #expect(FileManager.default.fileExists(atPath: other.path))
    }

    /// The tour opens on "this month": on the 1st its payments are all there, dated the 1st.
    @Test func theMadeUpMonthIsFullOnAnyDay() throws {
        let first = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 9))!
        let filled = TourData.vrBankCSV(now: first, fillThisMonth: true).split(separator: "\n").filter { $0.contains(".11.2026") }
        #expect(filled.count > 20)
        #expect(filled.allSatisfy { $0.contains(";01.11.2026;") })
        // The samples keep the days as they come: only the 1st's payments.
        let plain = TourData.vrBankCSV(now: first).split(separator: "\n").filter { $0.contains(".11.2026") }
        #expect(plain.count == 1)
        // Every month's payments stay within the months up to today.
        let late = TourData.vrBankCSV(now: Self.now, fillThisMonth: true).split(separator: "\n")
        #expect(!late.contains { $0.contains(".11.2026") || $0.contains("28.10.2026") || $0.contains("31.10.2026") })
    }
}
