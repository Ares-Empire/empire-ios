import Foundation

/// The bundled answers of the contract (`Samples/`, copies of aresus/docs/samples) for screenshots and tests, plus a few
/// made-up details the samples lack (other provinces, other runs), so every screen can be opened in sample mode.
/// `-sampleAllGood` turns the sample's issue into a running province; `-sampleEmpty` empties the sync overview.
nonisolated struct AresusSamples: Sendable {
    let allGood: Bool
    /// `-sampleEmpty`: no machine has reported yet.
    var emptySync = false

    /// The sample source when the app was launched with `-sampleData` (DEBUG only).
    static func launched(arguments: [String] = LaunchArguments.current) -> AresusSamples? {
        #if DEBUG
        guard arguments.contains("-sampleData") else { return nil }
        return AresusSamples(allGood: arguments.contains("-sampleAllGood"), emptySync: arguments.contains("-sampleEmpty"))
        #else
        return nil
        #endif
    }

    func overview() throws -> Overview {
        let overview: Overview = try Self.load("overview")
        guard allGood else { return overview }
        // The former issue joins the active provinces by name; everything else keeps the sample's order.
        let active = (overview.provinces.filter { $0.state == .active }
                      + overview.provinces.filter { $0.state == .issue }.map(Self.running)).sorted { $0.name < $1.name }
        return Overview(version: overview.version, checked: overview.checked, summary: "Everything running",
                        server: overview.server, provinces: active + overview.provinces.filter { $0.state == .inactive })
    }

    func province(_ slug: String) throws -> ProvinceDetail {
        if slug == "aresium" {
            let detail: ProvinceDetail = try Self.load("province")
            return allGood ? Self.running(detail) : detail
        }
        guard let province = try overview().provinces.first(where: { $0.slug == slug }) else {
            throw HTTPError.server(404, "Aresus does not watch this province.")
        }
        return Self.madeUpDetail(for: province, checked: try overview().checked)
    }

    func sync() throws -> SyncOverview { emptySync ? SyncOverview(machines: [], runs: []) : try Self.load("sync") }

    func run(_ id: Int) throws -> RunDetail {
        let run: RunDetail = try Self.load("run")
        if id == run.id { return run }
        guard case .run(let summary)? = try sync().runs.first(where: { $0.id == "run-\(id)" }) else {
            throw HTTPError.server(404, "This run is no longer kept.")
        }
        return Self.madeUpRun(for: summary)
    }

    /// The moment the samples were taken: 12 s after the overview's check, so the screens read like a live answer.
    func now() throws -> Date { try overview().checked.addingTimeInterval(12) }

    func folders() throws -> FolderList { try Self.load("drop-folders") }
    func drops() throws -> [Drop] {
        if emptySync { return [] }
        let answer: DropsAnswer = try Self.load("drops")
        return answer.drops
    }

    // MARK: loading

    static func load<T: Decodable>(_ name: String) throws -> T {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try AresusJSON.decoder().decode(T.self, from: Data(contentsOf: url))
    }

    // MARK: all good

    private static func running(_ province: Province) -> Province {
        Province(slug: province.slug, name: province.name, logo: province.logo, state: .active, word: "Active",
                 line: "Website 182 ms", since: province.since)
    }

    private static func running(_ detail: ProvinceDetail) -> ProvinceDetail {
        let checks = detail.checks.map { check in
            Check(name: check.name, ok: true,
                  detail: check.ok ? check.detail : check.name == "Website" ? "200 in 182 ms" : "active (running)",
                  checked: check.checked)
        }
        let incidents = detail.incidents.map { incident in
            Incident(opened: incident.opened, resolved: incident.resolved ?? incident.opened.addingTimeInterval(360),
                     summary: incident.summary)
        }
        return ProvinceDetail(slug: detail.slug, name: detail.name, logo: detail.logo, state: .active, word: "Active",
                              line: "Website 182 ms", since: detail.since, about: detail.about, url: detail.url, app: detail.app, checks: checks,
                              deploy: detail.deploy, incidents: incidents, uptime: detail.uptime)
    }

    // MARK: made-up details (fictional, for sample mode only)

    private static let abouts = [
        "empire": "The hub: every province on one ring, the chronicle and the Empire accounts.",
        "arestemis": "The flat hunt: new listings found, checked and sorted as they appear.",
        "aresync": "Git sync across the Mac, the Windows laptop and the server, every repo, automatically.",
        "arestoteles": "AI portfolio strategist: theses, falsifiers, conviction.",
        "aresis": "Privacy guardian: scans exposed personal data and proposes fixes.",
        "arescrypt": "A password and secrets vault for the empire.",
        "aresolus": "Weather and air for the places that matter."
    ]

    private static func madeUpDetail(for province: Province, checked: Date) -> ProvinceDetail {
        let watched = province.state != .inactive
        let checks = watched ? [
            Check(name: "Website", ok: true, detail: "200 in 96 ms", checked: checked),
            Check(name: "\(province.slug).service", ok: true, detail: "active for 6 days", checked: checked),
            Check(name: "TLS certificate", ok: true, detail: "expires in 74 days", checked: checked)
        ] : province.slug == "arestoteles" ? [
            Check(name: "Website", ok: true, detail: "200 in 151 ms", checked: checked),
            Check(name: "arestoteles.service", ok: true, detail: "inactive (off on purpose)", checked: checked)
        ] : []
        let deploy = province.word == "Planned" ? nil :
            Deploy(commit: "4e7ff91", subject: "Plainer status lines", date: checked.addingTimeInterval(-3 * 86_400),
                   behind: watched ? 0 : 3)
        let days = (0..<14).map { offset -> UptimeDay in
            let day = AresusFormat.dayKey(checked.addingTimeInterval(Double(offset - 13) * 86_400),
                                          calendar: Calendar(identifier: .gregorian))
            return UptimeDay(day: day, ratio: watched && offset >= 4 ? 1 : nil)
        }
        return ProvinceDetail(slug: province.slug, name: province.name, logo: province.logo, state: province.state,
                              word: province.word, line: province.line, since: province.since,
                              about: abouts[province.slug], url: nil, app: nil, checks: checks, deploy: deploy, incidents: [],
                              uptime: province.word == "Planned" ? [] : days)
    }

    private static func madeUpRun(for summary: RunSummary) -> RunDetail {
        let lines = summary.machine == "Server"
            ? ["PULL  ares-empire  fe141a2..9c03d7e", "HOOK  ares-empire  restarted ares-empire.service"]
            : ["PULL  ares-empire  e0aafda..fe141a2", "PULL  Arestemis  1beeb75..b9a79d8",
               "PUSH  aresium  (1 commit(s) -> origin)", "SKIP  scratch  (not a git repo)"]
        let counts = summary.machine == "Server"
            ? RunCounts(cloned: 0, committed: 0, pushed: 0, pulled: 1, skipped: 0, failed: 0)
            : RunCounts(cloned: 0, committed: 0, pushed: 1, pulled: 2, skipped: 1, failed: 0)
        return RunDetail(id: summary.id, machine: summary.machine, finished: summary.finished, result: summary.result,
                         summary: summary.summary, started: summary.finished.addingTimeInterval(-30), counts: counts,
                         lines: lines, problems: [])
    }
}
