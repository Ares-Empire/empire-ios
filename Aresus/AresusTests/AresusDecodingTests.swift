import Foundation
import Testing
@testable import Aresus

/// Every sample of the contract decodes into the models (aresus/docs/API.md, docs/samples).
struct AresusDecodingTests {
    @Test func overviewSample() throws {
        let overview: Overview = try sample("overview")
        #expect(overview.version == 1)
        #expect(overview.checked == at("2026-10-24T12:09:00Z"))
        #expect(overview.summary == "1 issue")
        #expect(overview.server == Server(host: "server.example", diskUsed: 0.35, memoryUsed: 0.46, load: 0.04,
                                          uptimeSeconds: 488_000, issue: nil))
        #expect(overview.provinces.count == 8)
        let aresium = try #require(overview.provinces.first)
        #expect(aresium == Province(slug: "aresium", name: "Aresium", logo: "brand/hermes.webp", state: .issue, word: "Issue",
                                    line: "Website down since 14:02 (502)", since: at("2026-10-24T12:02:00Z")))
        #expect(overview.provinces.map(\.state) == [.issue, .active, .active, .active, .inactive, .inactive, .inactive, .inactive])
        #expect(overview.provinces.last?.word == "Planned" && overview.provinces.last?.since == nil)
    }

    @Test func provinceSample() throws {
        let detail: ProvinceDetail = try sample("province")
        #expect(detail.slug == "aresium" && detail.state == .issue)
        #expect(detail.url == "https://aresium.de" && detail.app == "aresium://")
        #expect(detail.about?.hasPrefix("Personal finance command") == true)
        #expect(detail.checks.count == 5)
        #expect(detail.checks.filter { !$0.ok }.map(\.name) == ["Website", "aresium.service"])
        #expect(detail.deploy == Deploy(commit: "c22dad8", subject: "/api/pulse: one line for the Empire hub's Aresium card",
                                        date: at("2026-10-24T01:58:00Z"), behind: 0))
        #expect(detail.incidents.count == 2)
        #expect(detail.incidents[0].resolved == nil)
        #expect(detail.incidents[1].resolved == at("2026-10-21T03:20:00Z"))
        #expect(detail.uptime.count == 14)
        #expect(detail.uptime.first == UptimeDay(day: "2026-10-11", ratio: nil))
        #expect(detail.uptime.last == UptimeDay(day: "2026-10-24", ratio: 0.97))
        #expect(detail.province.line == "Website down since 14:02 (502)")
    }

    @Test(arguments: [false, true])
    func provinceLinksAreOptional(nullFields: Bool) throws {
        var json = try #require(JSONSerialization.jsonObject(with: sampleData("province")) as? [String: Any])
        for key in ["url", "app"] {
            if nullFields { json[key] = NSNull() }
            else { json.removeValue(forKey: key) }
        }
        let detail = try AresusJSON.decoder().decode(ProvinceDetail.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(detail.url == nil && detail.app == nil)
        #expect(!detail.canOpen)
    }

    @Test(arguments: ["aresium", "aresus"])
    func ownPageNeverOffersOpen(slug: String) throws {
        var json = try #require(JSONSerialization.jsonObject(with: sampleData("province")) as? [String: Any])
        json["slug"] = slug
        let detail = try AresusJSON.decoder().decode(ProvinceDetail.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(detail.canOpen == (slug != "aresus"))
    }

    @Test func allGoodSamplesKeepProvinceLinks() throws {
        let detail = try AresusSamples(allGood: true).province("aresium")
        #expect(detail.canOpen && detail.url == "https://aresium.de" && detail.app == "aresium://")
    }

    @Test func syncSample() throws {
        let sync: SyncOverview = try sample("sync")
        #expect(sync.machines.map(\.name) == ["Aresium", "Server", "Windows-Laptop"])
        #expect(sync.machines.map(\.server) == [false, true, false])
        let notebook = try #require(sync.machines.last)
        #expect(notebook.os == "Windows" && notebook.state == .issue && notebook.lastResult == .failed)
        #expect(notebook.lastOK == at("2026-10-18T09:00:09Z"))
        #expect(notebook.openProblems.count == 1)
        #expect(sync.runs.map(\.isQuiet) == [true, false, false, true, false])
        #expect(sync.runs[0] == .quiet(QuietDay(machine: "Server", day: "2026-10-24", count: 141, last: at("2026-10-24T12:05:03Z"))))
        #expect(sync.runs[4] == .run(RunSummary(id: 612, machine: "Windows-Laptop", finished: at("2026-10-19T09:00:12Z"),
                                                result: .failed, summary: "rebase conflict in aresium")))
    }

    /// `server` marks the aresus server; an answer without it (an older server), or with null, reads false.
    @Test(arguments: [(#""server": true,"#, true), (#""server": false,"#, false), ("", false), (#""server": null,"#, false)])
    func machineServerIsReadLeniently(field: String, server: Bool) throws {
        let json = #"{"name": "AresOS", "os": "Linux", "# + field
            + #""last_run": "2026-11-09T08:00:00Z", "last_result": "ok", "last_ok": "2026-11-09T08:00:00Z", "open_problems": [], "state": "active"}"#
        let machine = try AresusJSON.decoder().decode(Machine.self, from: Data(json.utf8))
        #expect(machine.server == server)
        #expect(machine.name == "AresOS" && machine.os == "Linux" && machine.state == .active && machine.lastResult == .ok)
        #expect(machine.lastRun == at("2026-11-09T08:00:00Z") && machine.openProblems.isEmpty)
    }

    /// The rack only for the server; any other machine by its system, so a laptop running Linux (AresOS) is a computer.
    @Test(arguments: [("Linux", true, "server.rack"), ("Linux", false, "desktopcomputer"), ("macOS", false, "laptopcomputer"),
                      ("Windows", false, "pc"), ("FreeBSD", false, "desktopcomputer")])
    func machineSymbol(os: String, server: Bool, symbol: String) {
        let machine = Machine(name: "Machine", os: os, server: server, lastRun: nil, lastResult: nil, lastOK: nil,
                              openProblems: [], state: .active)
        #expect(machine.symbol == symbol)
    }

    @Test func runSample() throws {
        let run: RunDetail = try sample("run")
        #expect(run.id == 612 && run.result == .failed)
        #expect(run.started == at("2026-10-19T08:59:40Z"))
        #expect(run.counts == RunCounts(cloned: 0, committed: 1, pushed: 0, pulled: 3, skipped: 0, failed: 1))
        #expect(run.lines.count == 5)
        #expect(run.problems == [RunProblem(key: "conflict:aresium", immediate: true,
                                            message: "aresium: rebase conflict between local commits and origin, resolve by hand")])
    }

    @Test func runsAndQuietDaysAreToldApartByTheQuietKey() throws {
        let json = Data("""
        [{"id": 1, "machine": "Server", "finished": "2026-10-24T11:40:04Z", "result": "ok", "summary": "nothing to do", "quiet": false},
         {"machine": "Server", "day": "2026-10-24", "count": 3, "last": "2026-10-24T12:05:03Z", "quiet": true}]
        """.utf8)
        let items = try AresusJSON.decoder().decode([SyncItem].self, from: json)
        guard case .run(let run) = items[0], case .quiet(let day) = items[1] else {
            Issue.record("Wrong cases: \(items)")
            return
        }
        #expect(run.id == 1 && run.summary == "nothing to do")
        #expect(day.count == 3)
        #expect(items.map(\.id) == ["run-1", "quiet-Server-2026-10-24"])
        // The same item can round-trip, `quiet` included.
        let again = try AresusJSON.decoder().decode([SyncItem].self, from: AresusJSON.encoder().encode(items))
        #expect(again == items)
        let encoded = try JSONSerialization.jsonObject(with: AresusJSON.encoder().encode(items)) as? [[String: Any]]
        #expect(encoded?.map { $0["quiet"] as? Bool } == [false, true])
    }

    @Test(arguments: [
        #"{"id": 1, "machine": "Server", "finished": "2026-10-24T11:40:04Z", "result": "ok", "summary": "x"}"#,
        #"{"machine": "Server", "day": "2026-10-24", "count": 3, "last": "2026-10-24T12:05:03Z", "quiet": false}"#,
        #"{"id": 1, "machine": "Server", "finished": "2026-10-24T11:40:04Z", "result": "ok", "summary": "x", "quiet": true}"#,
        #"{"id": 1, "machine": "Server", "finished": "2026-10-24T11:40:04Z", "result": "maybe", "summary": "x", "quiet": false}"#
    ])
    func malformedSyncItemsAreRejected(json: String) {
        #expect(throws: DecodingError.self) { try AresusJSON.decoder().decode(SyncItem.self, from: Data(json.utf8)) }
    }

    @Test func timestampsAcceptFractionsAndOffsets() throws {
        #expect(AresusJSON.date("2026-10-24T12:09:00Z") == Date(timeIntervalSince1970: 1_792_843_740))
        #expect(AresusJSON.date("2026-10-24T12:09:00.250Z") == Date(timeIntervalSince1970: 1_792_843_740.25))
        #expect(AresusJSON.date("2026-10-24T14:09:00+02:00") == Date(timeIntervalSince1970: 1_792_843_740))
        #expect(AresusJSON.date("24.10.2026 12:09") == nil)
        let json = Data(#"{"name": "Website", "ok": true, "detail": "200", "checked": "yesterday"}"#.utf8)
        #expect(throws: DecodingError.self) { try AresusJSON.decoder().decode(Check.self, from: json) }
    }

    @Test func optionalFieldsAcceptNull() throws {
        let json = Data("""
        {"slug": "aresolus", "name": "Aresolus", "logo": null, "state": "inactive", "word": "Planned", "line": "Not built yet",
         "since": null, "about": null, "checks": [], "deploy": null, "incidents": [], "uptime": []}
        """.utf8)
        let detail = try AresusJSON.decoder().decode(ProvinceDetail.self, from: json)
        #expect(detail.logo == nil && detail.about == nil && detail.deploy == nil && detail.uptime.isEmpty)
        // Without `server` too, as an answer from before the field: it reads as no server.
        let machine = Data(#"{"name": "New", "os": "Linux", "last_run": null, "last_result": null, "last_ok": null, "open_problems": [], "state": "inactive"}"#.utf8)
        let decoded = try AresusJSON.decoder().decode(Machine.self, from: machine)
        #expect(decoded.lastRun == nil && decoded.lastResult == nil && !decoded.server && decoded.symbol == "desktopcomputer")
        let deploy = Data(#"{"commit": "abc1234", "subject": "x", "date": "2026-10-24T01:58:00Z", "behind": null}"#.utf8)
        #expect(try AresusJSON.decoder().decode(Deploy.self, from: deploy).behind == nil)
    }
}
