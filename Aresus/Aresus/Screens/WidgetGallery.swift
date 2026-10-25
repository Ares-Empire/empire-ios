#if DEBUG
import SwiftUI
import WidgetKit

/// `-widgetGallery good|issues|loggedout`: the widget's real views (`AresusShared/AresusWidgetViews.swift`) at the sizes
/// iOS gives them, for screenshots (the simulator's home screen cannot be scripted). The states come from the bundled
/// samples, re-dated so the ages read like a live widget's.
struct WidgetGallery: View {
    enum Page: String {
        case good, issues, loggedout

        static func launched(arguments: [String]) -> Page? {
            guard let index = arguments.firstIndex(of: "-widgetGallery") else { return nil }
            return arguments.indices.contains(index + 1) ? Page(rawValue: arguments[index + 1]) ?? .good : .good
        }
    }

    let page: Page
    private let now = Date.now

    var body: some View {
        GeometryReader { geometry in
            let sizes = WidgetSizes(screenWidth: geometry.size.width)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                        SectionHeading(text: section.title)
                            .padding(.top, index == 0 ? 10 : 30).padding(.bottom, 12)
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(Array(section.rows.enumerated()), id: \.offset) { _, row in
                                HStack(spacing: sizes.gap(row)) {
                                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                                        WidgetCell(cell: cell, size: sizes.size(cell.family), now: now)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(width: sizes.medium.width, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .background {
            LinearGradient(colors: [Self.wallpaperTop, Self.wallpaperBottom], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }

    /// A home screen's wallpaper behind the widgets, light or dark with the appearance (`-appearance light|dark`), as
    /// the widgets follow the home screen's.
    private static let wallpaperTop = Color(light: Color(hex: 0xE2E5EB), dark: Color(hex: 0x2A2D35))
    private static let wallpaperBottom = Color(light: Color(hex: 0xCBD0D9), dark: Color(hex: 0x111216))
    /// The one tint iOS draws lock-screen widgets in: white on the dark wallpaper, dark ink on the light one.
    fileprivate static let lockInk = Color(light: Color(hex: 0x0A0C12), dark: .white)

    // MARK: the states

    private struct Section {
        let title: String
        let rows: [[Cell]]
    }

    private var sections: [Section] {
        let good = status(Self.allGood(), age: 240)
        let goodOld = status(Self.allGood(), age: 2 * 3600 + 300)
        let one = status(Self.oneIssue(), age: 240)
        let three = status(Self.threeIssues(), age: 60)
        switch page {
        case .good:
            return [Section(title: "All running · checked 4 min and 2 h ago",
                            rows: [[.small(good), .small(goodOld)], [.medium(good)]]),
                    Section(title: "Lock screen",
                            rows: [[.rectangular(good), .circular(good), .circular(goodOld)], [.rectangular(goodOld)]])]
        case .issues:
            return [Section(title: "1 issue · 3 issues",
                            rows: [[.small(one), .small(three)], [.medium(one)], [.medium(three)]]),
                    Section(title: "Lock screen",
                            rows: [[.rectangular(one), .circular(one), .circular(three)], [.rectangular(three)]])]
        case .loggedout:
            return [Section(title: "Logged out · nothing loaded yet",
                            rows: [[.small(.loggedOut), .small(.notLoaded)], [.medium(.loggedOut)]]),
                    Section(title: "Lock screen",
                            rows: [[.rectangular(.loggedOut), .circular(.loggedOut)], [.rectangular(.notLoaded)]])]
        }
    }

    /// A sample's status as if its check ran `age` seconds ago.
    private func status(_ overview: Overview?, age: TimeInterval) -> WidgetContent {
        guard let overview else { return .notLoaded }
        let status = WidgetStatus(overview: overview)
        return .status(WidgetStatus(summary: status.summary, state: status.state, issues: status.issues,
                                    counts: status.counts, serverIssue: status.serverIssue, syncLine: status.syncLine,
                                    checked: now.addingTimeInterval(-age)))
    }

    private static func allGood() -> Overview? { try? AresusSamples(allGood: true).overview() }
    private static func oneIssue() -> Overview? { try? AresusSamples(allGood: false).overview() }

    /// The sample with Arestemis down too and the server over its disk limit (made up).
    private static func threeIssues() -> Overview? {
        guard let overview = oneIssue() else { return nil }
        let arestemis = overview.provinces.first { $0.slug == "arestemis" }.map {
            Province(slug: $0.slug, name: $0.name, logo: $0.logo, state: .issue, word: "Issue",
                     line: "Bot not answering since 13:51", since: $0.since)
        }
        let others = overview.provinces.filter { $0.slug != "arestemis" }
        let server = overview.server
        return Overview(version: overview.version, checked: overview.checked, summary: "3 issues",
                        server: Server(host: server.host, diskUsed: 0.92, memoryUsed: server.memoryUsed, load: server.load,
                                       uptimeSeconds: server.uptimeSeconds, issue: "Disk 92 % full"),
                        provinces: others.filter { $0.state == .issue } + [arestemis].compactMap { $0 }
                            + others.filter { $0.state != .issue })
    }
}

/// One widget in the gallery.
private enum Cell {
    case small(WidgetContent), medium(WidgetContent), rectangular(WidgetContent), circular(WidgetContent)

    var family: WidgetFamily {
        switch self {
        case .small: .systemSmall
        case .medium: .systemMedium
        case .rectangular: .accessoryRectangular
        case .circular: .accessoryCircular
        }
    }

    var content: WidgetContent {
        switch self {
        case .small(let content), .medium(let content), .rectangular(let content), .circular(let content): content
        }
    }
}

/// A home-screen widget on its wall with the system's content margins and corners; a lock-screen one bare, in one
/// tint, as iOS draws it.
private struct WidgetCell: View {
    let cell: Cell
    let size: CGSize
    let now: Date

    var body: some View {
        let view = AresusWidgetView(content: cell.content, date: now, family: cell.family)
        switch cell.family {
        case .systemSmall, .systemMedium:
            view.padding(16)
                .frame(width: size.width, height: size.height)
                .background { ProvinceWall(accent: .aresus) }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        default:
            view.frame(width: size.width, height: size.height)
                .foregroundStyle(WidgetGallery.lockInk).tint(WidgetGallery.lockInk)
        }
    }
}

/// The widget sizes iOS uses for a screen width (Apple HIG → Widgets → Specifications, iPhone, in points). Screens
/// between the listed widths get the smaller size, so text that fits here fits on the phone.
private struct WidgetSizes {
    let small: CGSize
    let medium: CGSize
    let rectangular: CGSize
    let circular: CGSize

    init(screenWidth: CGFloat) {
        if screenWidth >= 428 {            // 428-440 pt wide (Plus and Pro Max)
            small = CGSize(width: 170, height: 170)
            medium = CGSize(width: 364, height: 170)
            rectangular = CGSize(width: 172, height: 76)
            circular = CGSize(width: 76, height: 76)
        } else {                           // 390-402 pt wide (iPhone 15, 16, 17 and their Pros)
            small = CGSize(width: 158, height: 158)
            medium = CGSize(width: 338, height: 158)
            rectangular = CGSize(width: 160, height: 72)
            circular = CGSize(width: 72, height: 72)
        }
    }

    func size(_ family: WidgetFamily) -> CGSize {
        switch family {
        case .systemMedium: medium
        case .accessoryRectangular: rectangular
        case .accessoryCircular: circular
        default: small
        }
    }

    /// Two small widgets fill a medium one's width; lock-screen widgets share it evenly.
    func gap(_ row: [Cell]) -> CGFloat {
        let used = row.map { size($0.family).width }.reduce(0, +)
        return row.count > 1 ? max(8, (medium.width - used) / CGFloat(row.count - 1)) : 0
    }
}
#endif
