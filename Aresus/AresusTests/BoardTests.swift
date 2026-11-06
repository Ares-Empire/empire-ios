import Foundation
import Testing
@testable import Aresus

@MainActor
struct BoardTests {
    @Test func decodesContractSample() throws {
        let board: BoardWaiting = try sample("board-waiting")
        #expect(board.asks.map(\.id) == [1, 2])
        #expect(board.asks[0].options == ["Ship it", "Wait"])
        #expect(board.asks[0].due == "2026-11-07")
        #expect(board.asks[1].options.isEmpty)
        #expect(board.answered.only?.answer == "Amber")
        #expect(board.unowned == BoardUnowned(count: 3, oldest: at("2026-11-03T10:00:00Z"), topics: ["orchard", "lantern"]))
        #expect(board.asks[0].claudeURL?.absoluteString == "https://claude.ai/code/session_demo01")
        #expect(try AresusJSON.decoder().decode(BoardWaiting.self, from: AresusJSON.encoder().encode(board)) == board)
    }

    @Test func unknownKindsAndStatesNeverHideTheOtherAsks() throws {
        var json = try #require(JSONSerialization.jsonObject(with: sampleData("board-waiting")) as? [String: Any])
        let original = try #require(json["asks"] as? [[String: Any]])
        var unknownKind = original[0]; unknownKind["id"] = 10; unknownKind["kind"] = "future-kind"
        var unknownState = original[0]; unknownState["id"] = 11; unknownState["state"] = "future-state"
        var work = original[0]; work["id"] = 12; work["kind"] = "work"
        var closed = original[0]; closed["id"] = 13; closed["state"] = "done"
        var sparse = original[0]
        sparse["id"] = 14
        for key in ["why", "session", "due", "since", "sent_to", "sent", "answer", "key"] { sparse.removeValue(forKey: key) }
        json["asks"] = [unknownKind, unknownState, work, closed] + original + [sparse]
        json["answered"] = [unknownKind, unknownState, work, closed]
        let decoded = try AresusJSON.decoder().decode(BoardWaiting.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(decoded.asks.map(\.id) == [1, 2, 14])
        #expect(decoded.answered.isEmpty)
        #expect(decoded.asks.last?.why == nil)
    }

    @Test func answeredSortNewestFirstButAsksKeepServerOrder() throws {
        let source: BoardWaiting = try sample("board-waiting")
        var newer = source.answered[0]
        newer.id = 20
        newer.updated = newer.updated.addingTimeInterval(1)
        let board = BoardWaiting(asks: source.asks.reversed(), answered: [source.answered[0], newer], unowned: source.unowned)
        #expect(board.asks.map(\.id) == [2, 1])
        #expect(board.answered.map(\.id) == [20, 3])
    }

    @Test(arguments: [AppLanguage.english, .german])
    func agesUseTheChosenLanguage(language: AppLanguage) {
        let now = at("2026-11-06T12:00:00Z")
        #expect(BoardWords.age(now.addingTimeInterval(-172800), now: now, language: language)
                == (language == .english ? "2 days" : "2 Tage"))
        #expect(BoardWords.age(now.addingTimeInterval(-3600), now: now, language: language)
                == (language == .english ? "1 hour" : "1 Stunde"))
        #expect(BoardWords.age(now.addingTimeInterval(-120), now: now, language: language)
                == (language == .english ? "2 minutes" : "2 Minuten"))
        #expect(BoardWords.age(now.addingTimeInterval(60), now: now, language: language)
                == (language == .english ? "1 minute" : "1 Minute"))
    }

    @Test func dueDatesUseBerlinAndTheChosenLocale() throws {
        #expect(BoardWords.due("2026-11-07", language: .english) == "due Sat 7 Nov")
        // The date's German words come from Foundation; the new "due %@" catalog translation is left to Claude.
        let germanDate = try #require(BoardWords.due("2026-11-07", language: .german))
        #expect(germanDate.contains("Sa.") && germanDate.contains("Nov."))
        #expect(BoardWords.isDue("2026-11-07", now: at("2026-11-06T23:00:00Z")))
        #expect(!BoardWords.isDue("2026-11-07", now: at("2026-11-06T22:59:59Z")))
        #expect(BoardWords.isDue("2026-11-01", now: at("2026-11-06T10:00:00Z")))
        #expect(BoardWords.due("2026-02-30") == nil)
        #expect(BoardWords.due("2026-1-01") == nil)
        #expect(!BoardWords.isDue("bad-date", now: .now))
    }

    @Test func wordsAndOwnAnswerValidation() throws {
        #expect(BoardAction.answer("Ship it").message(language: .english) == "Answered: Ship it")
        #expect(BoardAction.done.message(language: .english) == "Done")
        #expect(BoardAction.drop.message(language: .english) == "Set aside")
        let board: BoardWaiting = try sample("board-waiting")
        #expect(board.unowned.line(language: .english) == "3 open items have no session · orchard, lantern")
        #expect(BoardUnowned(count: 1, oldest: nil, topics: []).line(language: .english) == "1 open item has no session")
        #expect(BoardWords.ownAnswer(" \n ") == nil)
        #expect(BoardWords.ownAnswer(" \nShip it\nTomorrow.  ") == "Ship it\nTomorrow.")
        #expect(BoardWords.ownAnswer(String(repeating: "a", count: 1000)) != nil)
        #expect(BoardWords.ownAnswer(String(repeating: "a", count: 1001)) == nil)
        var item = board.asks[0]
        item.session = "bad/session"
        #expect(item.claudeURL == nil)
        item.session = nil
        #expect(item.claudeURL == nil)
    }

    @Test(arguments: [BoardAction.answer("Ship it"), .done, .drop])
    func actionsWaitThenSendExactlyOnce(action: BoardAction) async throws {
        let session = await signedInSession()
        let original: BoardWaiting = try sample("board-waiting")
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let item = original.asks[action == .done ? 1 : 0]
        let response = result(item, action: action)
        transport.data = try AresusJSON.encoder().encode(response)
        store.perform(action, on: item)
        #expect(store.badgeCount == 1 && store.asks.allSatisfy { $0.id != item.id })
        #expect(store.undoOffer?.message == action.message())
        #expect(transport.requests.count == 1)
        await store.commitPending()
        await store.commitPending()
        #expect(transport.requests.count == 2 && store.undoOffer == nil)
        #expect(store.badgeCount == 1 && store.failed.isEmpty)
        if case .answer = action { #expect(store.waiting?.answered.first == response) }
        else { #expect(store.waiting?.answered.count == 1) }
        let request = try #require(transport.requests.last)
        let suffix: String
        switch action { case .answer: suffix = "answer"; case .done: suffix = "done"; case .drop: suffix = "drop" }
        #expect(request.url?.path == "/api/aresus/board/items/\(item.id)/\(suffix)")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-empire-token")
        if case .answer(let text) = action {
            #expect(try JSONDecoder().decode([String: String].self, from: #require(request.httpBody)) == ["answer": text])
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        } else { #expect(request.httpBody == nil) }
    }

    @Test(arguments: [BoardAction.answer("Ship it"), .done, .drop])
    func undoCancelsEveryAction(action: BoardAction) async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let before = store.asks
        store.perform(action, on: before[action == .done ? 1 : 0])
        let offer = try #require(store.undoOffer)
        // The shared bar clears the binding before it calls Undo.
        store.undoOffer = nil
        await offer.undo?()
        offer.onDismiss?()
        await store.leavingForeground()
        #expect(store.asks == before && store.badgeCount == 2)
        #expect(transport.requests.count == 1)
    }

    @Test func undoTapCancelsSynchronouslyBeforeForegroundCanSend() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let before = store.asks
        store.perform(.drop, on: before[0])
        store.undoOffer?.performUndo()
        #expect(store.asks == before && store.undoOffer == nil)
        await store.leavingForeground()
        #expect(transport.requests.count == 1)
    }

    @Test func leavingForegroundSendsAtOnceAndIgnoresTheOldBar() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let item = try #require(store.asks.first)
        store.perform(.answer("Ship it"), on: item)
        let offer = try #require(store.undoOffer)
        transport.data = try AresusJSON.encoder().encode(result(item, action: .answer("Ship it")))
        await store.leavingForeground()
        await offer.undo?()
        offer.onDismiss?()
        await store.commitPending()
        #expect(transport.requests.count == 2 && store.undoOffer == nil && store.badgeCount == 1)
    }

    @Test func undoExpiryStartsTheSendAndForegroundDoesNotDuplicateIt() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let item = try #require(store.asks.first)
        store.perform(.drop, on: item)
        transport.data = try AresusJSON.encoder().encode(result(item, action: .drop))
        let gate = RequestGate(); transport.nextGate = gate
        store.undoOffer?.onDismiss?()
        await gate.waitUntilPaused()
        await store.leavingForeground()
        #expect(store.undoOffer == nil && transport.requests.count == 2 && store.badgeCount == 1)
        gate.resume()
    }

    @Test func replacingAnOfferCommitsOnlyThePreviousAction() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let before = store.asks
        transport.data = try AresusJSON.encoder().encode(result(before[0], action: .drop))
        let gate = RequestGate(); transport.nextGate = gate
        store.perform(.drop, on: before[0])
        let previous = try #require(store.undoOffer)
        store.perform(.done, on: before[1])
        await gate.waitUntilPaused()
        previous.onDismiss?()
        await previous.undo?()
        #expect(store.badgeCount == 0 && transport.requests.count == 2)
        await store.undoOffer?.undo?()
        gate.resume()
        await store.leavingForeground()
        #expect(store.asks.map(\.id) == [2])
    }

    @Test func failedSendRestoresTheCardAndAllowsRetry() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let before = store.asks
        store.perform(.answer("Ship it"), on: before[0])
        transport.failure = URLError(.notConnectedToInternet)
        await store.commitPending()
        #expect(store.asks == before && store.failed == [1] && store.undoOffer == nil)
        transport.failure = nil
        transport.data = try AresusJSON.encoder().encode(result(before[0], action: .answer("Ship it")))
        store.perform(.answer("Ship it"), on: before[0])
        #expect(store.failed.isEmpty)
        await store.commitPending()
        #expect(store.badgeCount == 1 && store.waiting?.answered.first?.answer == "Ship it")
    }

    @Test(arguments: [404, 409]) func goneOrChangedItemsLeaveTheList(status: Int) async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        store.perform(.drop, on: try #require(store.asks.first))
        var updated: BoardWaiting = try sample("board-waiting"); updated.asks.removeFirst()
        transport.responses = [(status, Data()), (200, try AresusJSON.encoder().encode(updated))]
        await store.commitPending()
        #expect(store.asks.map(\.id) == [2] && store.failed.isEmpty)
        #expect(transport.requests.count == (status == 409 ? 3 : 2))
        #expect(store.notice == (status == 409 ? "Already answered elsewhere." : nil))
    }

    @Test(arguments: [401, 403], [false, true])
    func authenticationFailuresClearBoardAndPendingActions(status: Int, sending: Bool) async throws {
        let storage = MemoryTokens()
        let session = await signedInSession(storage: storage)
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        store.perform(.drop, on: try #require(store.asks.first))
        transport.status = status
        if sending { await store.commitPending() } else { await store.refresh() }
        #expect(store.waiting == nil && store.badgeCount == 0 && store.undoOffer == nil && store.failed.isEmpty)
        #expect(status == 401 ? storage.token == nil : storage.token != nil)
        #expect(status == 401 ? !session.isSignedIn : session.isDenied)
        await store.leavingForeground()
        #expect(transport.requests.count == 2)
    }

    @Test func refreshThrottlesAndKeepsTheLastGoodListOnFailure() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh(olderThan: 60)
        let loaded = try #require(store.loadedAt)
        await store.refresh(olderThan: 60, now: loaded.addingTimeInterval(59))
        #expect(transport.requests.count == 1)
        transport.status = 503
        await store.refresh(olderThan: 60, now: loaded.addingTimeInterval(60))
        #expect(transport.requests.count == 2 && store.badgeCount == 2 && store.error != nil)
        #expect(transport.requests[0].url?.path == "/api/aresus/board/waiting")
    }

    @Test func anOlderRefreshCannotResurrectAnAnsweredCard() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let item = try #require(store.asks.first)
        let gate = RequestGate(); transport.nextGate = gate
        let refresh = Task { await store.refresh() }
        await gate.waitUntilPaused()
        store.perform(.answer("Ship it"), on: item)
        transport.data = try AresusJSON.encoder().encode(result(item, action: .answer("Ship it")))
        await store.commitPending()
        gate.resume(); await refresh.value
        #expect(store.asks.map(\.id) == [2] && store.waiting?.answered.first?.id == 1)
    }

    @Test func conflictRefreshWaitsForAnOlderRefreshToFinish() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let item = try #require(store.asks.first)
        var changed: BoardWaiting = try sample("board-waiting"); changed.asks.removeFirst()
        transport.responses = [(200, try sampleData("board-waiting")), (409, Data()),
                               (200, try AresusJSON.encoder().encode(changed))]
        let gate = RequestGate(); transport.nextGate = gate
        let refreshing = Task { await store.refresh() }
        await gate.waitUntilPaused()
        store.perform(.drop, on: item)
        await store.commitPending()
        let refreshed = RequestGate(); transport.nextGate = refreshed
        gate.resume(); await refreshing.value
        await refreshed.waitUntilPaused()
        #expect(transport.requests.count == 4 && store.notice == "Already answered elsewhere.")
        #expect(store.asks.map(\.id) == [2])
        refreshed.resume()
    }

    @Test func logoutDiscardsAPausedSendAndItsUndo() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("board-waiting"))
        let store = BoardStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh()
        let item = try #require(store.asks.first)
        store.perform(.drop, on: item)
        transport.data = try AresusJSON.encoder().encode(result(item, action: .drop))
        let gate = RequestGate(); transport.nextGate = gate
        let sending = Task { await store.commitPending() }
        await gate.waitUntilPaused()
        session.logOut()
        gate.resume(); await sending.value
        #expect(store.waiting == nil && store.undoOffer == nil && store.badgeCount == 0)
    }

    @Test func samplesPersistPretendAnswersAndFailOnlyTheNextSend() async throws {
        let session = EmpireSession(app: .aresus, storage: MemoryTokens(), restoreOnLaunch: false)
        let transport = FakeTransport()
        let store = BoardStore(session: session, client: AresusAPI(transport: transport),
                               samples: AresusSamples(allGood: false), failNextSend: true)
        await store.refresh()
        let item = try #require(store.asks.first)
        store.perform(.answer("Ship it"), on: item)
        await store.commitPending()
        #expect(store.asks.count == 2 && store.failed == [1])
        store.perform(.answer("Ship it"), on: item)
        await store.commitPending()
        await store.refresh()
        #expect(store.badgeCount == 1 && store.waiting?.answered.first?.id == 1)
        #expect(transport.requests.isEmpty)
        let empty = try #require(AresusSamples.launched(arguments: ["-sampleData", "-sampleBoardEmpty"]))
        #expect(try empty.boardWaiting() == .empty)
        let many = try #require(AresusSamples.launched(arguments: ["-sampleData", "-sampleBoardManyAsks"]))
        let scrolling = try many.boardWaiting()
        #expect(scrolling.asks.count == 8 && scrolling.asks.first?.id == 1)
        #expect(Set((scrolling.asks + scrolling.answered).map(\.id)).count == 9)
    }

    private func result(_ item: BoardItem, action: BoardAction) -> BoardItem {
        var result = item
        result.updated = result.updated.addingTimeInterval(60)
        switch action {
        case .answer(let text): result.state = .answered; result.answer = text
        case .done: result.state = .done
        case .drop: result.state = .dropped
        }
        return result
    }
}
