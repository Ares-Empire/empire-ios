import Foundation

/// What the Aresus widget shows: the overview cut down to a status light. The widget fetches it itself and the app
/// saves it after every overview it loads (`WidgetStatusStore`), so a widget without a connection shows the last one
/// with its age. Display data only: no token, no account.
nonisolated struct WidgetStatus: Codable, Equatable, Sendable {
    /// A province with an issue.
    nonisolated struct Issue: Codable, Equatable, Sendable {
        let slug: String
        let name: String
        let line: String           // "Website down since 14:02 (502)"
    }

    /// How many provinces are in each state (planned ones count as inactive, as on the watchtower).
    nonisolated struct Counts: Codable, Equatable, Sendable {
        let issue: Int
        let active: Int
        let inactive: Int
    }

    /// The headline: "All running", "1 issue", "3 issues" (provinces and the server, as the server counts them).
    let summary: String
    /// `.issue` when a province or the server has one, else `.active`.
    let state: AresusState
    /// The provinces with an issue, in the server's order.
    let issues: [Issue]
    let counts: Counts
    /// The server's own issue ("Disk 92 % full"), if any.
    let serverIssue: String?
    /// Aresync's line on the watchtower ("3 machines · last sync 4 min ago"), if Aresus watches it.
    let syncLine: String?
    /// The server's check round this status comes from.
    let checked: Date

    /// After this long without a newer check the status is stale: the widget keeps showing it with its age, but
    /// without its status colour, so an old "All running" never reads as current.
    static let staleAfter: TimeInterval = 60 * 60

    init(summary: String, state: AresusState, issues: [Issue], counts: Counts, serverIssue: String?, syncLine: String?,
         checked: Date) {
        self.summary = summary
        self.state = state
        self.issues = issues
        self.counts = counts
        self.serverIssue = serverIssue
        self.syncLine = syncLine
        self.checked = checked
    }

    init(overview: Overview) {
        let issues = overview.provinces.filter { $0.state == .issue }
            .map { Issue(slug: $0.slug, name: $0.name, line: $0.line) }
        let issueCount = issues.count + (overview.server.issue == nil ? 0 : 1)
        self.init(summary: Self.summary(issues: issueCount),
                  state: issueCount == 0 ? .active : .issue,
                  issues: issues,
                  counts: Counts(issue: issues.count,
                                 active: overview.provinces.count(where: { $0.state == .active }),
                                 inactive: overview.provinces.count(where: { $0.state == .inactive })),
                  serverIssue: overview.server.issue,
                  syncLine: overview.provinces.first { $0.slug == "aresync" }?.line,
                  checked: overview.checked)
    }

    static func summary(issues: Int) -> String {
        switch issues {
        case 0: "All running"
        case 1: "1 issue"
        default: "\(issues) issues"
        }
    }

    // MARK: what the views show

    /// One issue as the widget lists it: a province, or the server last.
    nonisolated struct Row: Equatable, Identifiable, Sendable {
        let id: String
        let name: String
        let line: String
        let url: URL
    }

    /// The issues to list: the provinces in the server's order, then the server.
    var rows: [Row] {
        issues.map { Row(id: "province-" + $0.slug, name: $0.name, line: $0.line, url: WidgetLink.province($0.slug)) }
            + (serverIssue.map { [Row(id: "server", name: "Server", line: $0, url: WidgetLink.server)] } ?? [])
    }

    var issueCount: Int { rows.count }

    /// The lock screen's line, longest first; the widget shows the first that fits, so a name is never cut:
    /// "3 issues · Aresium, Arestemis, Server", "3 issues · Aresium, Arestemis +1", "3 issues · Aresium +2", "3 issues".
    /// All good: just "All running".
    var lockLines: [String] {
        let names = rows.map(\.name)
        let withNames = names.indices.reversed().map { last in
            let rest = names.count - 1 - last
            return summary + " · " + names[...last].joined(separator: ", ") + (rest > 0 ? " +\(rest)" : "")
        }
        return withNames + [summary]
    }

    /// The share of watched things running, for the lock screen's ring: the active provinces and the server out of
    /// those plus the ones with an issue (inactive provinces are not watched).
    var runningShare: Double {
        let running = counts.active + (serverIssue == nil ? 1 : 0)
        let watched = counts.active + counts.issue + 1
        return Double(running) / Double(watched)
    }

    func isStale(at now: Date) -> Bool { now.timeIntervalSince(checked) >= Self.staleAfter }

    /// A made-up status for the system's widget gallery and the placeholder (never real data).
    static func example(checked: Date) -> WidgetStatus {
        WidgetStatus(summary: summary(issues: 0), state: .active, issues: [],
                     counts: Counts(issue: 0, active: 4, inactive: 4), serverIssue: nil,
                     syncLine: "3 machines · last sync 2 min ago", checked: checked)
    }

    /// The moment the status turns stale.
    var staleAt: Date { checked.addingTimeInterval(Self.staleAfter) }
}

/// The app's links the widget opens (`AresusLink` in the app reads them).
nonisolated enum WidgetLink {
    static let home = URL(string: "aresus://")!
    static let server = URL(string: "aresus://server")!

    static func province(_ slug: String) -> URL {
        var components = URLComponents()
        components.scheme = "aresus"
        components.host = "province"
        components.path = "/" + slug
        return components.url ?? home
    }
}

/// The widget's kind (`WidgetCenter.reloadTimelines(ofKind:)`).
nonisolated enum AresusWidgetKind {
    static let status = "AresusStatus"
}
