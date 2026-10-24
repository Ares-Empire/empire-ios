import SwiftUI
import UIKit

/// A province's page: the mark, name, status word, line and what it is; then its checks, last deploy, the last 14 days
/// and recent incidents. Empty sections are left out. The name moves into the bar once the hero scrolls away.
struct ProvinceDetailScreen: View {
    private static let end = "end"
    let slug: String
    let store: AresusStore
    let mark: UIImage?
    @State private var showsTitle = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var detail: ProvinceDetail? { store.provinces[slug] }
    private var province: Province? { detail?.province ?? store.overview?.provinces.first { $0.slug == slug } }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let province { hero(province) }
                if let detail {
                    DetailSections(detail: detail, clock: store.clock, refreshError: store.error(.province(slug)))
                        .animation(reduceMotion ? nil : .smooth, value: detail)
                } else if let error = store.error(.province(slug)) {
                    CalmMessage(text: error, actionTitle: "Try again") { Task { await store.load(.province(slug)) } }
                        .padding(.top, province == nil ? 160 : 34)
                } else {
                    CalmLoading().padding(.top, province == nil ? 190 : 40)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 44)
            Color.clear.frame(height: 1).id(Self.end)
        }
        .scrollIndicators(.hidden)
        #if DEBUG
        .task(id: detail != nil) {
            // Screenshots: `-scrollToEnd` shows the page's last sections.
            guard detail != nil, ProcessInfo.processInfo.arguments.contains("-scrollToEnd") else { return }
            try? await Task.sleep(for: .milliseconds(400))
            proxy.scrollTo(Self.end, anchor: .bottom)
        }
        #endif
        }
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 170
        } action: { _, past in
            withAnimation(.easeInOut(duration: 0.2)) { showsTitle = past }
        }
        .refreshable { await store.load(.province(slug)) }
        .scrollEdgeEffectStyle(.soft, for: .top)
        .background { ProvinceWall(accent: .aresus) }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(province?.name ?? "").font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary)
                    .opacity(showsTitle ? 1 : 0).accessibilityHidden(!showsTitle)
            }
        }
    }

    private func hero(_ province: Province) -> some View {
        VStack(spacing: 0) {
            ProvinceMarkView(name: province.name, image: mark, size: 88).padding(.bottom, 18)
            Text(province.name).font(AppFont.text(26, weight: .bold)).foregroundStyle(Ink.primary)
                .accessibilityAddTraits(.isHeader)
            StatusLabel(text: province.word, tone: province.state.tone, size: 11).padding(.top, 9)
            Text(province.line).font(AppFont.text(13)).foregroundStyle(Ink.muted).padding(.top, 12)
            if let about = detail?.about, !about.isEmpty {
                Text(about).font(AppFont.text(14)).lineSpacing(4).foregroundStyle(Ink.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 16).padding(.horizontal, 12)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 10)
        .opacity(province.state == .inactive ? 0.85 : 1)
    }
}

/// The page's sections below the hero; each one only when it has something to show.
private struct DetailSections: View {
    let detail: ProvinceDetail
    let clock: AresusClock
    let refreshError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let refreshError {
                Text("Not refreshed: \(refreshError)").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.top, 16)
            }
            if !detail.checks.isEmpty {
                let failing = detail.checks.filter { !$0.ok }.count
                section("Checks", value: failing > 0 ? "\(failing) of \(detail.checks.count) failing" : "all \(detail.checks.count) ok") {
                    CardRows(items: detail.checks) { CheckRow(check: $0) }
                }
            }
            if let deploy = detail.deploy {
                section("Last deploy") { DeployCard(deploy: deploy, clock: clock) }
            }
            if hasUptime {
                section("14 days", value: detail.averageUptime.map(AresusFormat.uptime)) {
                    UptimeStrip(days: detail.uptime)
                }
            }
            if !detail.incidents.isEmpty {
                section("Incidents", value: "\(detail.incidents.count)") {
                    CardRows(items: detail.incidents) { IncidentRow(incident: $0, clock: clock) }
                }
            }
            if detail.checks.isEmpty && detail.deploy == nil && !hasUptime && detail.incidents.isEmpty {
                CalmMessage(text: "Aresus has nothing to check here yet.").padding(.top, 44)
            }
        }
    }

    private var hasUptime: Bool { detail.uptime.contains { $0.ratio != nil } }

    private func section<Content: View>(_ title: String, value: String? = nil,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(text: title, value: value)
            content()
        }
        .padding(.top, 30)
    }
}

/// A check: a small green tick or red cross, its name, its detail on the right (below when it does not fit).
private struct CheckRow: View {
    let check: Check

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                mark
                name
                Spacer(minLength: 12)
                detail
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                mark
                VStack(alignment: .leading, spacing: 4) {
                    name
                    detail
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(check.name), \(check.ok ? "ok" : "failing")")
        .accessibilityValue(check.detail)
    }

    private var mark: some View {
        Image(systemName: check.ok ? "checkmark" : "xmark").font(.system(size: 11, weight: .bold))
            .foregroundStyle((check.ok ? StatusTone.active : .issue).color(.aresus)).frame(width: 14)
    }

    private var name: some View {
        Text(check.name).font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.primary).lineLimit(1)
    }

    private var detail: some View {
        Text(check.detail).font(AppFont.number(12, weight: .regular)).foregroundStyle(Ink.secondary).lineLimit(1)
    }
}

/// The deployed commit, its subject and date; how far GitHub is ahead when it is.
private struct DeployCard: View {
    let deploy: Deploy
    let clock: AresusClock

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(deploy.commit).font(AppFont.number(13)).foregroundStyle(Ink.secondary)
                Spacer(minLength: 12)
                Text(AresusFormat.moment(deploy.date, now: clock.now())).font(AppFont.number(12, weight: .regular))
                    .foregroundStyle(Ink.muted).lineLimit(1)
            }
            Text(deploy.subject).font(AppFont.text(14, weight: .medium)).lineSpacing(3).foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            if let behind = deploy.behind, behind > 0 {
                Text("\(behind) \(behind == 1 ? "commit" : "commits") on GitHub not deployed")
                    .font(AppFont.text(12, weight: .medium)).foregroundStyle(Color(hex: 0xE0B15A)).padding(.top, 10)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}

/// 14 thin bars across the width, oldest first: the up share in the accent, the down share in the issue red on top,
/// grey for days not watched; the first and last day's initials underneath.
private struct UptimeStrip: View {
    let days: [UptimeDay]
    private let height: CGFloat = 44

    var body: some View {
        VStack(spacing: 10) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.element.id) { index, day in
                    if index > 0 { Spacer(minLength: 3) }
                    bar(day).frame(width: 7, height: height)
                }
            }
            HStack {
                label(days.first)
                Spacer()
                label(days.last)
            }
        }
        .padding(.horizontal, 18).padding(.top, 18).padding(.bottom, 13)
        .glassCard()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Uptime, last \(days.count) days")
        .accessibilityValue(days.map { day in
            let name = AresusFormat.date(day: day.day).map { AresusFormat.day($0) } ?? day.day
            return "\(name): \(AresusFormat.uptime(day.ratio))"
        }.joined(separator: ", "))
    }

    @ViewBuilder private func bar(_ day: UptimeDay) -> some View {
        let shape = RoundedRectangle(cornerRadius: 2, style: .continuous)
        if let share = UptimeShare(ratio: day.ratio) {
            VStack(spacing: 0) {
                StatusTone.issue.color(.aresus).frame(height: height * share.down)
                AppAccent.aresus.color.frame(height: height * share.up)
            }
            .clipShape(shape)
        } else {
            shape.fill(Ink.muted.opacity(0.28))
        }
    }

    private func label(_ day: UptimeDay?) -> some View {
        let initial = day.flatMap { AresusFormat.date(day: $0.day) }.map { AresusFormat.weekdayInitial($0) } ?? ""
        return Text(initial).font(AppFont.text(10, weight: .semibold)).foregroundStyle(Ink.muted)
            .frame(width: 7)
    }
}

/// An incident: when it opened, how long it lasted (or "ongoing" in red), what it was.
private struct IncidentRow: View {
    let incident: Incident
    let clock: AresusClock

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(AresusFormat.moment(incident.opened, now: clock.now())).font(AppFont.number(12, weight: .regular))
                    .foregroundStyle(Ink.muted)
                Spacer(minLength: 12)
                if let resolved = incident.resolved {
                    Text(AresusFormat.duration(resolved.timeIntervalSince(incident.opened)))
                        .font(AppFont.number(12, weight: .regular)).foregroundStyle(Ink.secondary)
                } else {
                    Text("ongoing").font(AppFont.number(12)).foregroundStyle(StatusTone.issue.color(.aresus))
                }
            }
            Text(incident.summary).font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .accessibilityElement(children: .combine)
    }
}
