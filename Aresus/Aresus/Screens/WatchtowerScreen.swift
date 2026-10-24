import SwiftUI
import UIKit

/// The Aresus tab: the watchtower. The check's moment and summary painted on the wall, the server card, then every
/// province as a box like the hub's ring tab (Issues, Active, Inactive), ending in the ARESUS band. Tap a box for its page.
struct WatchtowerTab: View {
    let store: AresusStore
    @Bindable var navigation: AresusNavigation
    let marks: [String: UIImage]
    let logOut: () -> Void

    var body: some View {
        NavigationStack(path: $navigation.provincePath) {
            WatchtowerScreen(store: store, serverRequest: navigation.serverRequest, marks: marks) {
                navigation.showsSettings = true
            }
            .navigationDestination(for: String.self) { slug in
                ProvinceDetailScreen(slug: slug, store: store, mark: marks[slug])
            }
        }
        .sheet(isPresented: $navigation.showsSettings) {
            SettingsScreen(app: SettingsApp(name: "Aresus", accent: .aresus, sendsNotifications: true),
                           session: store.session, sample: store.isSample, logOut: logOut)
        }
    }
}

struct WatchtowerScreen: View {
    private static let end = "end"
    let store: AresusStore
    let serverRequest: Int
    let marks: [String: UIImage]
    let openSettings: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AresusHeader(bust: Image("Bust"), title: "Aresus") {
                            GlassIconButton(symbol: "gearshape", label: String(localized: "Settings"), action: openSettings)
                        }
                        content.padding(.horizontal, 18)
                            .animation(reduceMotion ? nil : .smooth, value: store.overview)
                        if store.overview != nil {
                            WordmarkBand(word: "ARESUS", width: geometry.size.width).padding(.top, 44).padding(.bottom, 10).id(Self.end)
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.load(.overview) }
                .onChange(of: serverRequest) { _, _ in
                    withAnimation(.smooth) { proxy.scrollTo(ServerCard.anchor, anchor: .top) }
                }
                #if DEBUG
                .task(id: store.overview?.checked) {
                    // Screenshots: `-scrollToEnd` shows the inactive provinces and the band.
                    guard store.overview != nil, ProcessInfo.processInfo.arguments.contains("-scrollToEnd") else { return }
                    try? await Task.sleep(for: .milliseconds(300))
                    proxy.scrollTo(Self.end, anchor: .bottom)
                }
                #endif
            }
        }
        .background { ProvinceWall(accent: .aresus) }
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var content: some View {
        if let overview = store.overview {
            Summary(overview: overview, clock: store.clock, refreshError: store.error(.overview))
                .padding(.top, 18)
            ServerCard(server: overview.server).id(ServerCard.anchor).padding(.top, 26)
            ForEach(overview.sections) { section in
                SectionTitle(text: section.title, value: "\(section.provinces.count)")
                    .padding(.top, 30).padding(.bottom, 12)
                VStack(spacing: section.provinces.first?.state == .inactive ? 9 : 12) {
                    ForEach(section.provinces) { province in
                        NavigationLink(value: province.slug) {
                            ProvinceBox(province: province, mark: marks[province.slug])
                        }
                        .buttonStyle(PressedBox())
                    }
                }
            }
        } else if let error = store.error(.overview) {
            CalmMessage(text: error, actionTitle: String(localized: "Try again")) { Task { await store.load(.overview) } }
                .padding(.top, 170)
        } else {
            CalmLoading().padding(.top, 190)
        }
    }
}

/// The check's moment, the summary in big type (ink, or the issue red), and how long ago the round ran.
private struct Summary: View {
    let overview: Overview
    let clock: AresusClock
    let refreshError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeading(text: AresusFormat.checkedHeading(overview.checked))
            Text(overview.summary).font(AppFont.text(26, weight: .bold))
                .foregroundStyle(overview.hasIssue ? StatusTone.issue.color(.aresus) : Ink.primary)
                .contentTransition(.numericText())
                .padding(.top, 6)
            LiveRelativeTime(date: overview.checked, clock: clock, text: { String(localized: "checked \($0)") }).padding(.top, 5)
            if let refreshError {
                Text("Not refreshed: \(refreshError)").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    .lineLimit(2).padding(.top, 8)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The server's figures side by side: Disk, Memory, Load, Up; a thin bar under the two shares.
struct ServerCard: View {
    static let anchor = "server"
    let server: Server

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                figure(String(localized: "Disk"), AresusFormat.percent(server.diskUsed), share: server.diskUsed, over: server.diskOverLimit)
                figure(String(localized: "Memory"), AresusFormat.percent(server.memoryUsed), share: server.memoryUsed,
                       over: server.memoryOverLimit)
                figure(String(localized: "Load"), AresusFormat.load(server.load))
                figure(String(localized: "Up"), AresusFormat.upFor(server.uptimeSeconds))
            }
            if let issue = server.issue {
                Text(issue).font(AppFont.text(13, weight: .medium)).foregroundStyle(StatusTone.issue.color(.aresus))
                    .padding(.top, 14)
            }
        }
        .padding(.horizontal, 16).padding(.top, 15).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Server")
    }

    /// "35 %": the number in mono, its unit smaller in text type, so the figure does not read as two numbers.
    private func figureValue(_ value: String) -> some View {
        let parts = value.split(separator: " ", maxSplits: 1).map(String.init)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(parts[0]).font(AppFont.number(17)).foregroundStyle(Ink.primary).contentTransition(.numericText())
            if parts.count > 1 {
                Text(parts[1]).font(AppFont.text(12, weight: .medium)).foregroundStyle(Ink.secondary)
            }
        }
        .lineLimit(1)
    }

    private func figure(_ label: String, _ value: String, share: Double? = nil, over: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label.uppercased()).font(AppFont.text(10, weight: .semibold)).tracking(1.2)
                .foregroundStyle(Ink.muted).lineLimit(1)
            figureValue(value).padding(.top, 6)
            if let share {
                ShareBar(fraction: share, color: over ? StatusTone.issue.color(.aresus) : AppAccent.aresus.color)
                    .padding(.top, 9)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A province as the hub's ring tab, full width: its mark, the NAME over the status word, the line below.
struct ProvinceBox: View {
    let province: Province
    let mark: UIImage?

    /// Inactive and planned provinces are quieter and slimmer, so the running ones lead the list (Patrik: "simple,
    /// clean, not bloated").
    private var compact: Bool { province.state == .inactive }

    var body: some View {
        HStack(spacing: compact ? 12 : 14) {
            ProvinceMarkView(name: province.name, image: mark, size: compact ? 36 : 48)
            VStack(alignment: .leading, spacing: 0) {
                Text(province.name.uppercased()).font(AppFont.text(compact ? 13 : 15, weight: .bold))
                    .tracking(compact ? 1.3 : 1.5).foregroundStyle(Ink.primary).lineLimit(1)
                if compact {
                    HStack(spacing: 7) {
                        StatusLabel(text: province.word, tone: province.state.tone, size: 9)
                        Text(province.line).font(AppFont.text(11.5)).foregroundStyle(Ink.muted).lineLimit(1)
                    }
                    .padding(.top, 4)
                } else {
                    StatusLabel(text: province.word, tone: province.state.tone).padding(.top, 5)
                    Text(province.line).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        .lineLimit(province.state == .issue ? 2 : 1).padding(.top, 6)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: compact ? 11 : 12, weight: .semibold)).foregroundStyle(Ink.muted)
        }
        .opacity(compact ? 0.72 : 1)
        .padding(.leading, compact ? 12 : 14).padding(.trailing, 16).padding(.vertical, compact ? 9 : 12)
        .frame(maxWidth: .infinity, minHeight: compact ? 58 : 78, alignment: .leading)
        .modifier(BoxSurface(issue: province.state == .issue))
        .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(province.name), \(province.word)")
        .accessibilityValue(province.line)
        .accessibilityAddTraits(.isButton)
    }
}

/// Glass for every box; an issue box gets a faint red edge instead of the glass edge.
private struct BoxSurface: ViewModifier {
    let issue: Bool
    func body(content: Content) -> some View {
        if issue {
            content.modifier(EdgedGlassCard(edge: StatusTone.issue.color(.aresus).opacity(0.35)))
        } else {
            content.glassCard()
        }
    }
}

/// A box pressed: a touch smaller and dimmer, no highlight colour.
struct PressedBox: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
