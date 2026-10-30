import SwiftUI

/// One sync run's report: the machine, when it finished and how it went; the counts, the problems, the log.
struct RunSheet: View {
    let id: Int
    let store: AresusStore
    @Environment(\.dismiss) private var dismiss

    private var run: RunDetail? { store.runs[id] }
    /// The list's line for this run, so the header shows while the report loads.
    private var summary: RunSummary? {
        store.sync?.runs.lazy.compactMap { if case .run(let run) = $0, run.id == id { run } else { nil } }.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let run {
                        header(machine: run.machine, finished: run.finished, result: run.result, summary: run.summary,
                               took: run.finished.timeIntervalSince(run.started))
                        report(run)
                    } else {
                        if let summary {
                            header(machine: summary.machine, finished: summary.finished, result: summary.result,
                                   summary: summary.summary, took: nil)
                        }
                        if let error = store.error(.run(id)) {
                            CalmMessage(text: error, actionTitle: String(localized: "Try again")) { Task { await store.load(.run(id)) } }
                                .padding(.top, 40)
                        } else {
                            CalmLoading().padding(.top, 50)
                        }
                    }
                }
                .padding(.horizontal, 22).padding(.top, 30).padding(.bottom, 36)
            }
            .scrollIndicators(.hidden)
            .task { if run == nil { await store.load(.run(id)) } }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
            .background { ProvinceWall(accent: .aresus) }
        }
    }

    private func header(machine: String, finished: Date, result: RunResult, summary: String,
                        took: TimeInterval?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(machine).font(AppFont.text(20, weight: .bold)).foregroundStyle(Ink.primary).lineLimit(1)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                StatusLabel(text: result == .ok ? String(localized: "OK") : String(localized: "Failed"), tone: result == .ok ? .active : .issue, size: 10)
            }
            Text([AresusFormat.moment(finished, now: store.clock.now()), took.map { String(localized: "took \(AresusFormat.duration($0))") }]
                    .compactMap { $0 }.joined(separator: " · "))
                .font(AppFont.number(12, weight: .regular)).foregroundStyle(Ink.muted).padding(.top, 6)
            Text(summary).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func report(_ run: RunDetail) -> some View {
        let counts = run.counts.shown
        if !counts.isEmpty {
            FlowRow(spacing: 8) {
                ForEach(counts, id: \.key) { count in
                    CountCapsule(label: count.label, value: count.value, failed: count.key == "failed")
                }
            }
            .padding(.top, 18)
            .accessibilityElement(children: .combine)
        }
        if !run.problems.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: String(localized: "Problems"))
                ForEach(Array(run.problems.enumerated()), id: \.offset) { _, problem in
                    Text(problem.message).font(AppFont.text(13)).lineSpacing(3)
                        .foregroundStyle(StatusTone.issue.color(.aresus)).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 28)
        }
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: String(localized: "Log"), value: run.lines.isEmpty ? nil : String(localized: "\(run.lines.count) lines"))
            if run.lines.isEmpty {
                Text("This run wrote no log lines.").font(AppFont.text(13)).foregroundStyle(Ink.muted)
            } else {
                LogBlock(lines: run.lines)
            }
        }
        .padding(.top, 28)
    }
}

/// "pulled 3": a small mono capsule; a failure count in the issue red.
private struct CountCapsule: View {
    let label: String
    let value: Int
    let failed: Bool

    var body: some View {
        let red = StatusTone.issue.color(.aresus)
        Text("\(label) \(value)").font(AppFont.number(11.5, weight: .medium))
            .foregroundStyle(failed ? red : Ink.secondary)
            .padding(.horizontal, 11).frame(minHeight: 26)
            .background(Ink.card2, in: .capsule)
            .overlay(Capsule().strokeBorder(failed ? red.opacity(0.35) : Ink.line))
    }
}

/// The log in JetBrains Mono on a darker card: FAIL lines in the issue red, SKIP and WARN muted, the rest in ink.
private struct LogBlock: View {
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line).font(AppFont.number(11.5, weight: .regular)).foregroundStyle(color(LogTone(line: line)))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .textSelection(.enabled)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Ink.card2, in: RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Ink.rowRadius, style: .continuous).strokeBorder(Ink.line))
    }

    private func color(_ tone: LogTone) -> Color {
        switch tone {
        case .fail: StatusTone.issue.color(.aresus)
        case .quiet: Ink.muted
        case .normal: Ink.primary
        }
    }
}
