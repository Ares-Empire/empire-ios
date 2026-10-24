import Foundation
import Testing
@testable import Aresus

/// Times, durations, shares and groupings as the screens show them, pinned to Berlin (UTC+2 on 24 Oct 2026).
struct AresusFormatTests {
    /// Sat 24 Oct 2026, 14:09:12 in Berlin.
    let now = at("2026-10-24T12:09:12Z")

    @Test(arguments: [
        ("2026-10-24T12:09:12Z", "just now"),
        ("2026-10-24T12:09:30Z", "just now"),            // a clock a little ahead
        ("2026-10-24T12:09:00Z", "12 s ago"),
        ("2026-10-24T12:05:03Z", "4 min ago"),
        ("2026-10-24T09:00:31Z", "3 h ago"),
        ("2026-10-23T21:57:02Z", "yesterday 23:57"),
        ("2026-10-23T23:57:02Z", "12 h ago"),            // 01:57 today in Berlin
        ("2026-10-19T09:00:12Z", "Mon 19 Oct 11:00"),
        ("2025-10-19T09:00:12Z", "19 Oct 2025")
    ])
    func relativeTimes(date: String, expected: String) {
        #expect(AresusFormat.relative(at(date), now: now, calendar: berlin) == expected)
    }

    @Test func relativeTimesAcrossMidnight() {
        let afterMidnight = at("2026-10-24T22:30:00Z")   // 00:30 on Sunday in Berlin
        #expect(AresusFormat.relative(at("2026-10-24T21:50:00Z"), now: afterMidnight, calendar: berlin) == "40 min ago")
        #expect(AresusFormat.relative(at("2026-10-24T20:00:00Z"), now: afterMidnight, calendar: berlin) == "yesterday 22:00")
    }

    @Test func timesAndDays() {
        #expect(AresusFormat.time(at("2026-10-24T07:05:00Z"), calendar: berlin) == "09:05")
        #expect(AresusFormat.day(at("2026-10-19T09:00:00Z"), calendar: berlin) == "Mon 19 Oct")
        #expect(AresusFormat.checkedHeading(at("2026-10-24T12:09:00Z"), calendar: berlin) == "Sat 24 Oct · 14:09")
        #expect(AresusFormat.moment(at("2026-10-24T01:58:00Z"), now: now, calendar: berlin) == "Today 03:58")
        #expect(AresusFormat.moment(at("2026-10-21T03:14:00Z"), now: now, calendar: berlin) == "Wed 21 Oct 05:14")
        #expect(AresusFormat.weekdayInitial(at("2026-10-24T12:00:00Z"), calendar: berlin) == "S")
        #expect(AresusFormat.weekdayInitial(at("2026-10-21T12:00:00Z"), calendar: berlin) == "W")
    }

    @Test(arguments: [
        ("2026-10-24", "Today"),
        ("2026-10-23", "Yesterday"),
        ("2026-10-19", "Mon 19 Oct"),
        ("2025-10-19", "Sun 19 Oct 2025")
    ])
    func dayHeadings(day: String, expected: String) throws {
        let date = try #require(AresusFormat.date(day: day, calendar: berlin))
        #expect(AresusFormat.dayHeading(date, now: now, calendar: berlin) == expected)
        #expect(AresusFormat.dayKey(date, calendar: berlin) == day)
    }

    @Test(arguments: ["2026-13-01", "2026-02-30", "26-10-24", "2026-10-24T12:00", "", "abcd-ef-gh"])
    func invalidDaysAreRejected(day: String) {
        #expect(AresusFormat.date(day: day, calendar: berlin) == nil)
    }

    @Test func durations() {
        #expect(AresusFormat.duration(-5) == "0 s")
        #expect(AresusFormat.duration(45) == "45 s")
        #expect(AresusFormat.duration(360) == "6 min")
        #expect(AresusFormat.duration(7200) == "2 h")
        #expect(AresusFormat.duration(7800) == "2 h 10 min")
        #expect(AresusFormat.duration(3 * 86_400) == "3 d")
        #expect(AresusFormat.duration(3 * 86_400 + 4 * 3600 + 59) == "3 d 4 h")
        #expect(AresusFormat.upFor(488_000) == "5 d")
        #expect(AresusFormat.upFor(54_000) == "15 h")
        #expect(AresusFormat.upFor(2400) == "40 min")
    }

    @Test func percentagesAndUptime() {
        #expect(AresusFormat.percent(0.35) == "35 %")
        #expect(AresusFormat.percent(0) == "0 %")
        #expect(AresusFormat.percent(1) == "100 %")
        #expect(AresusFormat.percent(0.996) == "99 %")     // nearly full is not full
        #expect(AresusFormat.percent(1.4) == "100 %")
        #expect(AresusFormat.uptime(1) == "100 %")
        #expect(AresusFormat.uptime(0.996) == "99.6 %")
        #expect(AresusFormat.uptime(0.97) == "97 %")
        #expect(AresusFormat.uptime(0.9999) == "99.9 %")   // any downtime never reads as 100 %
        #expect(AresusFormat.uptime(nil) == "not watched")
        #expect(AresusFormat.load(0.04) == "0.04")
        #expect(AresusFormat.load(1.2) == "1.20")
    }

    // MARK: display

    @Test func runsGroupByDay() throws {
        let sync: SyncOverview = try sample("sync")
        let days = RunDay.group(sync.runs, now: now, calendar: berlin)
        #expect(days.map(\.key) == ["2026-10-24", "2026-10-23", "2026-10-19"])
        #expect(days.map(\.title) == ["Today", "Yesterday", "Mon 19 Oct"])
        #expect(days.map(\.items.count) == [3, 1, 1])
        #expect(days[0].items.map(\.id) == ["quiet-Server-2026-10-24", "run-905", "run-880"])
    }

    @Test func runsGroupByTheLocalDayAndMergeSplitDays() {
        let late = SyncItem.run(RunSummary(id: 2, machine: "Server", finished: at("2026-10-23T22:30:00Z"),  // 00:30 Sat
                                           result: .ok, summary: "pulled 1"))
        let quiet = SyncItem.quiet(QuietDay(machine: "Server", day: "2026-10-24", count: 9, last: at("2026-10-23T22:20:00Z")))
        let earlier = SyncItem.run(RunSummary(id: 1, machine: "Aresium", finished: at("2026-10-23T20:00:00Z"),
                                              result: .failed, summary: "pull fails"))
        let odd = SyncItem.quiet(QuietDay(machine: "Server", day: "not a day", count: 1, last: at("2026-10-24T06:00:00Z")))
        let days = RunDay.group([late, earlier, quiet, odd], now: now, calendar: berlin)
        #expect(days.map(\.key) == ["2026-10-24", "2026-10-23"])
        #expect(days[0].items == [late, quiet, odd])
        #expect(days[1].items == [earlier])
    }

    @Test func overviewSections() throws {
        let overview: Overview = try sample("overview")
        #expect(overview.sections.map(\.title) == ["Issues", "Active", "Inactive"])
        #expect(overview.sections.map(\.provinces.count) == [1, 3, 4])
        #expect(overview.hasIssue)
        let allGood = try AresusSamples(allGood: true).overview()
        #expect(allGood.sections.map(\.title) == ["Active", "Inactive"])
        #expect(!allGood.hasIssue)
        let serverIssue = Overview(version: 1, checked: now, summary: "1 issue",
                                   server: Server(host: "s", diskUsed: 0.92, memoryUsed: 0.4, load: 0, uptimeSeconds: 0,
                                                  issue: "Disk 92 % full"),
                                   provinces: allGood.provinces)
        #expect(serverIssue.hasIssue)
    }

    @Test func serverLimits() {
        let calm = Server(host: "s", diskUsed: 0.85, memoryUsed: 0.92, load: 0, uptimeSeconds: 0, issue: nil)
        #expect(!calm.diskOverLimit && !calm.memoryOverLimit)
        let full = Server(host: "s", diskUsed: 0.86, memoryUsed: 0.93, load: 0, uptimeSeconds: 0, issue: "Disk 86 % full")
        #expect(full.diskOverLimit && full.memoryOverLimit)
    }

    @Test func runDetails() throws {
        let run: RunDetail = try sample("run")
        #expect(run.counts.shown.map(\.label) == ["pulled", "committed", "failed"])
        #expect(run.counts.shown.map(\.value) == [3, 1, 1])
        #expect(run.lines.map(LogTone.init(line:)) == [.normal, .normal, .fail, .normal, .normal])
        #expect(LogTone(line: "SKIP  scratch  (not a git repo)") == .quiet)
        #expect(LogTone(line: "WARN  aresium  slow") == .quiet)
        #expect(LogTone(line: "") == .normal)
    }

    @Test func machinesAndUptime() throws {
        let sync: SyncOverview = try sample("sync")
        #expect(sync.machines.map(\.symbol) == ["laptopcomputer", "server.rack", "pc"])
        #expect(sync.machines.map(\.state.word) == ["Active", "Active", "Issue"])
        let detail: ProvinceDetail = try sample("province")
        let average = try #require(detail.averageUptime)
        #expect(abs(average - (0.996 + 1 + 1 + 0.97) / 4) < 0.000_001)
        #expect(UptimeShare(ratio: nil) == nil)
        #expect(UptimeShare(ratio: 1) == UptimeShare(ratio: 1.2))
        #expect(UptimeShare(ratio: 1)?.down == 0)
        #expect(UptimeShare(ratio: 0.996)?.down == 0.08)      // six minutes still show
        #expect(UptimeShare(ratio: 0.5)?.down == 0.5)
    }
}
