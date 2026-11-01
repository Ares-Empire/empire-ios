import SwiftUI

/// The Aresync tab: every machine with its last sync, then the runs grouped by day. Quiet runs come folded into one
/// muted line per machine and day; tap a run for its report.
struct SyncScreen: View {
    let store: AresusStore
    var drops: DropsStore? = nil
    let open: (Int) -> Void
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                AresusHeader(bust: Image("SyncBust"), title: "Aresync") {
                    GlassIconButton(symbol: "gearshape", label: String(localized: "Settings"),
                                    action: openSettings)
                }
                content.padding(.horizontal, 18)
                    .animation(reduceMotion ? nil : .smooth, value: store.sync)
            }
            .padding(.bottom, 36)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await store.load(.sync)
            await drops?.refresh()
        }
        .background { ProvinceWall(accent: .aresus) }
    }

    @ViewBuilder private var content: some View {
        if let sync = store.sync {
            if sync.machines.isEmpty && sync.runs.isEmpty {
                CalmMessage(text: String(localized: "No sync reports yet. Each machine reports after its next run.")).padding(.top, 170)
            } else {
                if let error = store.error(.sync) {
                    Text("Not refreshed: \(error)").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .lineLimit(2).padding(.top, 14)
                }
                if !sync.machines.isEmpty {
                    SectionTitle(text: String(localized: "Machines"), value: "\(sync.machines.count)").padding(.top, 18).padding(.bottom, 12)
                    CardRows(items: sync.machines) { MachineRow(machine: $0, clock: store.clock) }
                }
                ForEach(RunDay.group(sync.runs, now: store.clock.now())) { day in
                    SectionTitle(text: day.title).padding(.top, 30).padding(.bottom, 12)
                    CardRows(items: day.items) { item in
                        switch item {
                        case .run(let run):
                            Button { open(run.id) } label: { RunRow(run: run) }.buttonStyle(PressedRow())
                        case .quiet(let quiet):
                            QuietRow(day: quiet)
                        }
                    }
                }
            }
        } else if let error = store.error(.sync) {
            CalmMessage(text: error, actionTitle: String(localized: "Try again")) { Task { await store.load(.sync) } }.padding(.top, 170)
        } else {
            CalmLoading().padding(.top, 190)
        }
    }
}

/// A machine: its system's symbol, its name, when it last synced, its state; open problems below in red.
private struct MachineRow: View {
    let machine: Machine
    let clock: AresusClock

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: machine.symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(Ink.muted)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(machine.name).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                    if let lastRun = machine.lastRun {
                        LiveRelativeTime(date: lastRun, clock: clock, text: { String(localized: "last sync \($0)") })
                    } else {
                        Text("no sync yet").font(AppFont.number(12, weight: .regular)).foregroundStyle(Ink.muted)
                    }
                }
                Spacer(minLength: 8)
                StatusLabel(text: machine.state.word, tone: machine.state.tone)
            }
            ForEach(Array(machine.openProblems.enumerated()), id: \.offset) { _, problem in
                Text(problem).font(AppFont.text(12)).lineSpacing(2).foregroundStyle(StatusTone.issue.color(.aresus))
                    .lineLimit(2).padding(.leading, 40)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .opacity(machine.state == .inactive ? 0.7 : 1)
        .accessibilityElement(children: .combine)
    }
}

/// A run: the time it finished, the machine over its summary, the result word.
private struct RunRow: View {
    let run: RunSummary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(AresusFormat.time(run.finished)).font(AppFont.number(13, weight: .regular)).foregroundStyle(Ink.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(run.machine).font(AppFont.text(13, weight: .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                Text(run.summary).font(AppFont.text(13)).foregroundStyle(Ink.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            StatusLabel(text: run.result == .ok ? String(localized: "OK") : String(localized: "Failed"), tone: run.result == .ok ? .active : .issue, size: 9.5)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Shows the run's report")
    }
}

/// Runs that changed nothing, folded: "Server · 141 quiet runs", muted and not tappable.
private struct QuietRow: View {
    let day: QuietDay

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(AresusFormat.time(day.last)).font(AppFont.number(13, weight: .regular))
            Text(verbatim: "\(day.machine) · " + String(localized: "\(day.count) quiet runs")).font(AppFont.text(13))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Ink.muted)
        .padding(.horizontal, 16).padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// A row pressed inside a card: a faint tint behind it (`Ink.press`).
private struct PressedRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Ink.press : .clear)
    }
}
