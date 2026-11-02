import Foundation
import SwiftUI
import Testing
@testable import Aresium

/// The tour (briefs 24, 25, 42, 59, 77, 99 and 203): its steps go on when the person does the thing or taps Next, the
/// graph's, the search's and the Settings rows' steps only point and go on, the graph's step is left out (and no card
/// mentions the graph) while the graph is hidden, adding up works on the tour's own choices in memory, and it runs on a
/// made-up store of its own that is deleted when it ends, at any step, without touching the person's store or settings.
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

    /// The graph shown (the default), unless a test says otherwise; never the simulator's own setting.
    private static func model(in parent: URL, showsGraph: Bool = true) -> TourModel {
        TourModel(showsGraph: showsGraph, graphMoves: true) {
            try await TourWorld.make(in: parent, now: now, makeEngine: { try PhoneTest.engine() })
        }
    }

    /// The tour's folders in `parent`.
    private static func tourFolders(in parent: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix(TourWorld.folderPrefix) }
    }

    /// The person's settings and choices the tour must never write, as the app's own defaults hold them.
    private static let personsKeys = [PaymentSums.key, GraphSetting.key, GraphMotionSetting.key, PhoneBackend.ownNamesKey,
                                      AresiumMessages.preferencesKey, AresiumMessages.historyKey,
                                      AresiumMessages.progressKey]

    private static func personsDefaults() -> [String: Data] {
        var values: [String: Data] = [:]
        for key in personsKeys {
            if let value = UserDefaults.standard.object(forKey: key) {
                values[key] = (try? NSKeyedArchiver.archivedData(withRootObject: value, requiringSecureCoding: false))
                    ?? Data()
            }
        }
        return values
    }

    /// Waits (up to 10 s) until `condition` holds; the follow-up question's answer finishes in a task of its own.
    private func eventually(_ condition: () -> Bool) async {
        for _ in 0..<200 where !condition() { try? await Task.sleep(for: .milliseconds(50)) }
    }

    /// The category list on top of the tour's dashboard, as its rows show.
    private func shownList(_ tour: TourModel) throws -> PaymentList {
        let world = try #require(tour.world)
        let route = try #require(tour.place.path.last)
        #expect(route.isCategoryList)
        return world.dashboard.paymentList(category: route.category, month: try #require(route.month), side: route.side)
    }

    @Test func eachStepGoesOnWhenThePersonDoesTheThing() async throws {
        let before = Self.personsDefaults()
        let parent = Self.parent()
        let tour = Self.model(in: parent)
        await tour.start()
        #expect(tour.phase == .running)
        #expect(tour.step == .welcome)
        #expect(tour.target == nil)
        #expect(tour.count == 22)
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
        #expect(tour.target == .graph, "the graph itself, on the start screen")
        #expect(tour.holdsTheScreen)
        #expect(!tour.place.current, "Overview stays for the graph")
        #expect(tour.number == 4 && tour.count == 22)

        place = tour.place
        place.side = .expenses                                  // the person moves the page: the step asks nothing
        tour.update(place)
        place = tour.place
        place.open(DashboardRoute(monthPage: "2026-09", side: .expenses))   // a tap on a month opens its page
        tour.update(place)
        #expect(tour.step == .graph, "only Next goes on from the graph")
        #expect(tour.target == .graph, "the month's page has its own graph")
        place = tour.place
        place.day = DayRoute(date: "2026-09-14", side: .expenses)            // a tap on a day there (brief 77)
        tour.update(place)
        #expect(tour.step == .graph)
        tour.next()

        // Brief 77: the search's magnifying glass on the start screen; the search and the names it opens are free.
        #expect(tour.step == .search)
        #expect(tour.place.path.isEmpty && tour.place.day == nil, "back on the start screen, the day's sheet closed")
        #expect(tour.target == .search && tour.holdsTheScreen)
        #expect(tour.number == 5)
        place = tour.place
        place.open(.search)                                                   // the magnifying glass
        tour.update(place)
        #expect(tour.step == .search, "only Next goes on from the search")
        #expect(tour.target == nil && !tour.holdsTheScreen, "free to type and open a name")
        let found = try #require(world.dashboard.searchNames("REWE").first, "the tour's search runs on its own store")
        place = tour.place
        place.open(DashboardRoute(name: PaymentNameRoute(key: found.key, title: found.shownName)))
        tour.update(place)
        #expect(tour.step == .search && tour.target == nil)
        tour.next()
        #expect(tour.step == .category)
        #expect(tour.place.path.isEmpty, "back on the start screen")
        #expect(tour.place.current && tour.place.side == .expenses, "back on this month's expenses")
        let groceries = try #require(world.firstCategory)
        #expect(tour.target == .category(groceries))

        place = tour.place
        place.path.append(world.dashboard.route(category: groceries, side: .expenses, current: true))   // the row
        tour.update(place)
        #expect(tour.step == .payment)
        let first = try #require(world.dashboard.transactions(category: groceries, month: "2026-10", side: .expenses).first)
        #expect(tour.target == .payment(first.transaction.id))
        #expect(!tour.rowShortcuts, "the ringed row opens its page: no swipe or menu here")

        place = tour.place
        place.payment = first.transaction                       // the payment's page
        tour.update(place)
        #expect(tour.step == .rename)
        #expect(tour.target == .paymentName)

        // The name, renamed for the whole shop: saved in the tour's store, which moves on.
        let detail = world.dashboard.transactionDetailStore(for: first.transaction)
        await detail.prepareRename()
        #expect(detail.offersRename)
        tour.paymentRecategorised()
        #expect(tour.step == .rename, "only a saved name moves on")
        await detail.rename(to: "Fiktiv Supermarkt", scope: .shop)
        #expect(detail.detail?.place == "Fiktiv Supermarkt")
        #expect(tour.step == .switchCategory)
        #expect(tour.target == .change)

        // The category's chip → another category → Save: the shop question comes, as in real use; the answer moves on.
        detail.beginRecategorisation()
        let eatingOut = try #require(try await world.phone.categories().name(of: "eating-out"))
        detail.select(eatingOut)
        await detail.save()
        let question = try #require(detail.followUp)
        #expect(question.count > 3)
        #expect(tour.step == .switchCategory, "still waiting for the answer")
        detail.answer(moveOthers: true)
        await eventually { tour.step == .payback }

        // Brief 203: the made-up trip's page, half paid back, its link ringed; only Next goes on (optional).
        #expect(tour.step == .payback)
        let trip = try #require(world.paybackTrip)
        #expect(tour.place.payment?.id == trip, "the trip's page")
        #expect(tour.target == .payback && tour.holdsTheScreen)
        #expect(tour.place.path.last?.isCategoryList == true, "the list stays under the page")
        place = tour.place
        place.payment = nil                                      // the page swiped away: free, nothing moves on
        tour.update(place)
        #expect(tour.step == .payback && tour.target == nil && !tour.holdsTheScreen)
        tour.next()
        #expect(tour.step == .select)
        #expect(tour.place.payment == nil, "the payment closes: the list under it")

        // Brief 82: the list's select icon. Selecting works on the tour's store and frees the screen; Next goes on and
        // ends it.
        #expect(tour.target == .selectIcon)
        #expect(tour.holdsTheScreen && !tour.rowShortcuts)
        let listRoute = try #require(tour.place.path.last)
        place = tour.place
        place.selection = PaymentSelection(route: listRoute)
        tour.update(place)
        #expect(tour.step == .select, "selecting asks nothing of the step")
        #expect(tour.target == nil && !tour.holdsTheScreen, "the list, its bar and its windows are free to try")
        place = tour.place
        place.selection?.toggleAll(in: world.dashboard)
        tour.update(place)
        #expect(world.dashboard.selectionSummary(try #require(tour.place.selection).ids).canSwitch)
        tour.next()
        #expect(tour.step == .addUp)
        #expect(tour.place.selection == nil, "Next ends selecting")

        // The swipe's Add up on the ringed single row: the name as one row, in the tour's choices.
        var list = try shownList(tour)
        guard case let .payment(row, true)? = list.entries.first(where: {
            if case .payment(_, true) = $0 { true } else { false }
        }) else { Issue.record("no single row with a name to add up"); return }
        #expect(tour.target == .payment(row.transaction.id))
        #expect(tour.holdsTheScreen && tour.rowShortcuts, "the ringed row swipes; the back swipe stays off")
        let name = try #require(PaymentList.nameKey(row.transaction))
        let category = world.dashboard.sumCategoryKey(groceries)
        world.dashboard.sums.setName(name, in: category, sums: true)
        #expect(tour.step == .sumIcon)
        #expect(tour.addedUpName == name)
        #expect(try shownList(tour).summed(name) != nil, "the name is one row now")
        #expect(tour.target == .sumIcon)
        #expect(!tour.rowShortcuts)

        // The icon: every name in the list added up (another grocer has several payments too, so it was off).
        list = try shownList(tour)
        #expect(list.sumKeys.count >= 2 && !list.allSummed)
        world.dashboard.sums.toggleCategory(category, names: list.sumKeys)
        #expect(tour.step == .allFrom)
        #expect(try shownList(tour).allSummed)
        #expect(tour.target == .summed(name), "the same row as at Add up")
        #expect(tour.rowShortcuts)

        // Separate meanwhile: the ring follows the name to its first row; All opens the name's page and moves on.
        world.dashboard.sums.setName(name, in: category, sums: false)
        #expect(tour.step == .allFrom)
        let firstOfName = try #require(try shownList(tour).rows.first { PaymentList.nameKey($0.transaction) == name })
        #expect(tour.target == .payment(firstOfName.transaction.id))
        let nameRoute = try #require(world.dashboard.nameRoute(for: firstOfName.transaction))
        place = tour.place
        place.open(nameRoute)
        tour.update(place)
        #expect(tour.step == .categories)
        #expect(tour.place.path.last?.isNamePage == true, "the name's page stays under the gear")
        #expect(tour.target == .settings)

        tour.openSettings()
        #expect(tour.target == .dataRows)
        tour.settingsRowTapped(.lockRow)
        tour.settingsRowTapped(.messagesRow)
        #expect(tour.step == .categories, "a row answers only its own step")
        tour.setCategoriesShown(true)
        #expect(tour.target == nil, "free to choose and add categories")
        try await world.phone.addCustom(named: "Fiktiv-Kategorie", side: .spend)
        tour.next()
        #expect(tour.step == .messages)
        #expect(tour.showsSettings && !tour.showsCategories, "back in the tour's Settings, at Messages")
        #expect(tour.target == .messagesRow)
        tour.closeSettings()
        #expect(tour.target == .settings, "closed: the gear again")
        tour.openSettings()
        tour.settingsRowTapped(.messagesRow)
        #expect(tour.step == .lock && tour.target == .lockRow)
        tour.settingsRowTapped(.contactRow)
        #expect(tour.step == .lock)
        tour.settingsRowTapped(.lockRow)
        #expect(tour.step == .dashboardSettings && tour.target == .dashboardRows)
        tour.settingsRowTapped(.dashboardRows)
        #expect(tour.step == .contact && tour.target == .contactRow)
        tour.settingsRowTapped(.contactRow)
        #expect(tour.step == .importFiles)
        #expect(!tour.showsSettings && tour.place.path.isEmpty)
        #expect(tour.target == .importButton)

        tour.importTapped()
        // Brief 99: what an import left Not sorted, name by name: Not sorted's card on this month's list opens the quick
        // sort on the tour's store; closing it goes on.
        #expect(tour.step == .quickSort)
        let notSorted = try #require(tour.place.path.last)
        #expect(notSorted.category == CategoryName.uncategorised && notSorted.month == "2026-10" && tour.place.current)
        #expect(tour.target == .quickSortCard && tour.holdsTheScreen)
        place = tour.place
        place.quickSort = QuickSortFlow(store: world.dashboard)            // the card's tap
        tour.update(place)
        #expect(tour.step == .quickSort && tour.target == nil, "its cards are free to sort")
        let card = try #require(tour.place.quickSort?.card)
        let pick = try #require(card.choices.first?.name)
        await card.sort(pick)
        #expect(tour.place.quickSort?.sortedPayments == card.ids.count, "sorted on the tour's store")
        place = tour.place
        place.quickSort = nil                                               // Done
        tour.update(place)
        #expect(tour.step == .done)
        #expect(tour.target == nil)
        tour.next()
        #expect(tour.phase == .ended)
        #expect(Self.tourFolders(in: parent).isEmpty, "the made-up store is deleted")
        #expect(Self.personsDefaults() == before, "the person's choices, settings, names and messages untouched")
    }

    @Test func nextGetsEachStepsScreenReady() async throws {
        let parent = Self.parent()
        let tour = Self.model(in: parent)
        await tour.start()
        var seen: [TourStep] = [tour.step]
        while tour.phase == .running {
            switch tour.step {
            case .graph:
                #expect(!tour.place.current, "Overview's months")
                #expect(tour.target == .graph)
            case .search:
                #expect(tour.place.path.isEmpty && tour.place.day == nil)
                #expect(tour.target == .search)
            case .payment:
                #expect(tour.place.path.last?.month == "2026-10", "this month's payments of a category")
                #expect(tour.place.path.last?.categoryID == TourData.firstCategory, "the tour's page follows a category rename")
                #expect(tour.target != nil)
            case .rename:
                #expect(tour.place.payment != nil, "a payment's page")
                #expect(tour.target == .paymentName)
            case .switchCategory:
                #expect(tour.place.payment != nil, "a payment's page")
                #expect(tour.target == .change)
            case .payback:
                #expect(tour.place.payment?.id == tour.world?.paybackTrip, "the made-up trip's page")
                #expect(tour.place.payment?.paidBack == 64)
                #expect(tour.target == .payback)
            case .select:
                #expect(tour.place.payment == nil && tour.place.path.last?.isCategoryList == true)
                #expect(tour.target == .selectIcon)
            case .addUp, .allFrom:
                #expect(tour.place.payment == nil && tour.place.path.last?.isCategoryList == true)
                if case .payment? = tour.target {} else { Issue.record("a single row at \(tour.step)") }
                #expect(tour.rowShortcuts && tour.holdsTheScreen)
            case .sumIcon:
                #expect(tour.place.path.last?.isCategoryList == true)
                #expect(tour.target == .sumIcon)
            case .categories:
                #expect(tour.place.payment == nil)
                #expect(tour.target == .settings)
            case .messages:
                #expect(tour.showsSettings && tour.target == .messagesRow)
            case .lock:
                #expect(tour.showsSettings && tour.target == .lockRow)
            case .dashboardSettings:
                #expect(tour.showsSettings && tour.target == .dashboardRows)
            case .contact:
                #expect(tour.showsSettings && tour.target == .contactRow)
            case .importFiles, .welcome, .done:
                #expect(tour.place.path.isEmpty && tour.place.payment == nil)
            case .quickSort:
                #expect(tour.place.path.last?.category == CategoryName.uncategorised)
                #expect(tour.target == .quickSortCard)
            default:
                #expect(tour.place.path.isEmpty)
                #expect(tour.target != nil)
            }
            if tour.holdsTheScreen && !tour.step.swipesRows { #expect(!tour.rowShortcuts, "\(tour.step)") }
            tour.next()
            if tour.phase == .running { seen.append(tour.step) }
        }
        #expect(seen == TourStep.allCases)
        #expect(seen.count == 22)
        #expect(Self.tourFolders(in: parent).isEmpty)
    }

    /// With the graph hidden in Settings (brief 42), the tour has no graph step: twenty-one steps, counted 1 to 21 on the
    /// card, Overview followed by the search (brief 77); a DEBUG start at the graph's step starts at the search; no card
    /// mentions the graph (brief 59).
    @Test func withTheGraphHiddenTheGraphStepIsLeftOut() async throws {
        #expect(TourStep.steps(showingGraph: true) == TourStep.allCases)
        #expect(TourStep.steps(showingGraph: false) == TourStep.allCases.filter { $0 != .graph })

        let tour = Self.model(in: Self.parent(), showsGraph: false)
        await tour.start()
        #expect(tour.count == 21)
        var numbers: [Int] = []
        var seen: [TourStep] = []
        while tour.phase == .running {
            numbers.append(tour.number)
            seen.append(tour.step)
            #expect(tour.target != .graph)
            #expect(!tour.text.localizedCaseInsensitiveContains("graph"), "\(tour.step)")
            if tour.step == .overview { #expect(tour.nextStep == .search) }
            if tour.step == .done { #expect(tour.nextStep == nil) }
            tour.next()
        }
        #expect(numbers == Array(1...21))
        #expect(!seen.contains(.graph) && seen.first == .welcome && seen.last == .done)
        for step in TourStep.steps(showingGraph: false) {
            #expect(!step.text(.english, showingGraph: false).localizedCaseInsensitiveContains("graph"))
            #expect(!step.text(.german, showingGraph: false).localizedCaseInsensitiveContains("diagramm"))
        }

        let started = Self.model(in: Self.parent(), showsGraph: false)
        await started.start(at: .graph)
        #expect(started.step == .search && started.number == 4)
        started.end()
    }

    /// Every card has its German, and the cards about the new features say what they show, in both languages.
    @Test func theCardsSayWhatTheyShowInBothLanguages() {
        for step in TourStep.allCases {
            for graph in [true, false] {
                let english = step.text(.english, showingGraph: graph), german = step.text(.german, showingGraph: graph)
                #expect(!german.isEmpty && german != english, "\(step) has its German")
                #expect(!english.contains("!") && !german.contains("!"), "no exclamation marks")
            }
        }
        #expect(TourStep.graph.text(.english) == "Hold the graph and slide to read each month. A tap opens the month, or the day where it shows days.")
        #expect(TourStep.graph.text(.german) == "Halte den Finger auf dem Diagramm und zieh: jeder Monat mit seiner Zahl. Antippen öffnet den Monat, zeigt es Tage, den Tag.")
        #expect(TourStep.search.text(.english) == "Search a name, your own or the bank's. A tap shows all its payments.")
        #expect(TourStep.search.text(.german).contains("Namen") && TourStep.search.text(.german).contains("Bank"))
        #expect(TourStep.categories.text(.english) == "Choose categories and add your own. Hold a category to rename or delete it.")
        #expect(TourStep.categories.text(.german).contains("Umbenennen oder Löschen"))
        #expect(TourStep.addUp.text(.german).contains("Summieren"))
        #expect(TourStep.allFrom.text(.german).contains("Alle"))
        #expect(TourStep.select.text(.english) == "Tap to select several payments and move or rename them at once.")
        #expect(TourStep.select.text(.german)
                == "Tippe hier, um mehrere Buchungen auszuwählen und auf einmal zu verschieben oder umzubenennen.")
        #expect(TourStep.importFiles.text(.english) == "Files from your bank, receipts and cash come in here.")
        #expect(TourStep.quickSort.text(.english)
                == "What an import leaves Not sorted, you go through here name by name. One tap sorts all of a name's payments.")
        #expect(TourStep.quickSort.text(.german)
                == "Was nach einem Import nicht sortiert ist, gehst du hier Name für Name durch. Einmal tippen sortiert alle Buchungen eines Namens.")
        #expect(TourStep.dashboardSettings.text(.german, showingGraph: true).contains("Diagramm"))
        #expect(TourStep.dashboardSettings.text(.german, showingGraph: false) == "Hier summierst du gleiche Namen in jeder Liste.")
    }

    /// The tour scrolls to a control only as far as it takes to show it above the card, and not at all when it shows
    /// (brief 59: a start page's moving graph went half away for a category row that nearly showed).
    @Test func theTourScrollsOnlyAsFarAsItTakes() throws {
        // Shown already, wholly in the upper 60 %: no scroll.
        #expect(TourScrollPlace(frame: CGRect(x: 0, y: 100, width: 300, height: 60), height: 600).scrollAnchor == nil)
        // Its lower edge just past it: brought to the end of the shown part.
        let near = TourScrollPlace(frame: CGRect(x: 0, y: 340, width: 300, height: 60), height: 600)
        let anchor = try #require(near.scrollAnchor)
        let top = anchor.y * (600 - 60)                     // where its top lands with that anchor
        #expect(abs(top + 60 - 360) < 0.001, "its lower edge at 60 % of the height")
        // Above the top (scrolled past), or taller than the shown part: its top at the top.
        #expect(TourScrollPlace(frame: CGRect(x: 0, y: -40, width: 300, height: 60), height: 600).scrollAnchor != nil)
        #expect(TourScrollPlace(frame: CGRect(x: 0, y: 500, width: 300, height: 500), height: 600).scrollAnchor?.y == 0)
    }

    /// Adding up in the tour (brief 59): its lists offer it, on choices of its own in memory; the person's are never
    /// read or written, the app's defaults never touched.
    @Test func addingUpInTheTourIsInMemoryOnly() async throws {
        let before = Self.personsDefaults()
        let tour = Self.model(in: Self.parent())
        await tour.start(at: .addUp)
        let world = try #require(tour.world)
        #expect(world.dashboard.offersSums)
        #expect(!world.dashboard.sums.isKept && world.dashboard.sums.choices == SumChoices(), "empty, in memory")
        world.dashboard.sums.setEverywhere(true)
        #expect(tour.step == .sumIcon, "a name added up moves on")
        world.dashboard.sums.toggleCategory("id:groceries", names: ["merchant:fiktiv"])
        #expect(tour.step == .allFrom)
        world.dashboard.sums.setName("merchant:fiktiv", sums: false)
        #expect(tour.step == .allFrom, "only All moves on from here")
        tour.end()
        #expect(Self.personsDefaults() == before)
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
        try await world.phone.addCustom(named: "Tour-Kategorie", side: .spend)
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
