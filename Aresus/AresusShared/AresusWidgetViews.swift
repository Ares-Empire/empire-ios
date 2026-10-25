import SwiftUI
import WidgetKit

/// The widget's views, compiled into the app too so its widget gallery (DEBUG `-widgetGallery`) shows the real thing.
/// `date` is the entry's moment: a status older than `WidgetStatus.staleAfter` loses its status colour.
/// The wall behind the home-screen sizes is `ProvinceWall(accent: .aresus)` (the widget's `containerBackground`).
struct AresusWidgetView: View {
    let content: WidgetContent
    let date: Date
    let family: WidgetFamily

    var body: some View {
        Group {
            switch family {
            case .accessoryRectangular: WidgetRectangular(content: content, date: date)
            case .accessoryCircular: WidgetCircular(content: content, date: date)
            case .systemMedium: home(medium: true)
            default: home(medium: false)
            }
        }
        .widgetURL(WidgetLink.home)
    }

    @ViewBuilder private func home(medium: Bool) -> some View {
        switch content {
        case .status(let status):
            if medium {
                WidgetMedium(status: status, stale: status.isStale(at: date))
            } else {
                WidgetSmall(status: status, stale: status.isStale(at: date))
            }
        case .loggedOut: WidgetMessage(text: WidgetMessage.loggedOut)
        case .notLoaded: WidgetMessage(text: WidgetMessage.notLoaded)
        }
    }
}

// MARK: home screen

/// Small: the bust and the name, the headline (and the first issue), how old the check is.
struct WidgetSmall: View {
    let status: WidgetStatus
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WidgetMark()
            Spacer(minLength: 4)
            WidgetHeadline(status: status, stale: stale).layoutPriority(1)
            if let first = status.rows.first {
                Text(first.name).font(AppFont.text(13, weight: .semibold)).foregroundStyle(Ink.primary)
                    .lineLimit(1).padding(.top, 3).layoutPriority(1)
                // Two lines when they fit; with larger text it gives way first, so the headline keeps its size.
                Text(first.line).font(AppFont.text(11)).foregroundStyle(Ink.muted)
                    .lineLimit(2).padding(.top, 2)
            }
            Spacer(minLength: 8)        // more room above the age, so two muted lines don't run together
            WidgetChecked(checked: status.checked)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}

/// Medium: the small one's left half; on the right the issues (each opens its province) or, all good, the counts and
/// Aresync's line. The first issue is not repeated on the left: the rows carry it.
struct WidgetMedium: View {
    let status: WidgetStatus
    let stale: Bool

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                WidgetMark()
                Spacer(minLength: 6)
                WidgetHeadline(status: status, stale: stale)
                Spacer(minLength: 6)
                WidgetChecked(checked: status.checked)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            Rectangle().fill(Ink.line).frame(width: 1).padding(.horizontal, 14).accessibilityHidden(true)
            Group {
                if status.rows.isEmpty {
                    counts
                } else {
                    issueRows
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var issueRows: some View {
        let rows = status.rows
        return VStack(alignment: .leading, spacing: 9) {
            ForEach(rows.prefix(3)) { row in
                Link(destination: row.url) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name).font(AppFont.text(12, weight: .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                        Text(row.line).font(AppFont.text(10.5)).foregroundStyle(Ink.muted)
                            .lineLimit(4 - min(rows.count, 3))         // 1 row: 3 lines, 2 rows: 2, 3 rows: 1
                    }
                    .multilineTextAlignment(.leading)                   // a link's label would centre it
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .accessibilityElement(children: .combine)
            }
            if rows.count > 3 {
                Text("and \(rows.count - 3) more", tableName: "AresusShared").font(AppFont.text(10.5)).foregroundStyle(Ink.muted)
            }
        }
        .padding(.top, 3)
    }

    private var counts: some View {
        VStack(alignment: .leading, spacing: 5) {
            count(String(localized: LocalizedStringResource("\(status.counts.active) active", table: "AresusShared",
                                                            locale: .appLanguage)), tone: .active)
            count(String(localized: LocalizedStringResource("\(status.counts.inactive) inactive",
                                                            table: "AresusShared",
                                                            locale: .appLanguage)), tone: .inactive)
            Spacer(minLength: 6)
            if let sync = status.syncLine {
                Text(verbatim: "Aresync · " + sync).font(AppFont.text(11)).foregroundStyle(Ink.muted)
                    .lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.top, 3)
        .accessibilityElement(children: .combine)
    }

    private func count(_ text: String, tone: StatusTone) -> some View {
        Text(text).font(AppFont.number(12, weight: .medium))
            .foregroundStyle(stale && tone == .active ? Ink.secondary : tone.color(.aresus))
    }
}

/// Logged out, or nothing loaded yet: the bust and one calm sentence.
struct WidgetMessage: View {
    static var loggedOut: String { String(localized: LocalizedStringResource("Open Aresus to log in",
                                                                             table: "AresusShared",
                                                                             locale: .appLanguage)) }
    static var notLoaded: String { String(localized: LocalizedStringResource("Open Aresus to load the status",
                                                                             table: "AresusShared",
                                                                             locale: .appLanguage)) }
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            Image("Bust").resizable().scaledToFit().frame(width: 46, height: 46)
                .shadow(color: .black.opacity(0.55), radius: 6, y: 4).accessibilityHidden(true)
            Text(text).font(AppFont.text(12)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The bust and the name in tracked capitals.
struct WidgetMark: View {
    var body: some View {
        HStack(spacing: 6) {
            Image("Bust").resizable().scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
            Text(verbatim: "ARESUS").font(AppFont.text(9, weight: .semibold)).tracking(1.8).foregroundStyle(Ink.muted)
        }
    }
}

/// "● All running" with a green dot, or "1 issue" in the issue red; without the colour once stale.
struct WidgetHeadline: View {
    let status: WidgetStatus
    let stale: Bool

    var body: some View {
        if status.rows.isEmpty {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Circle().fill(stale ? Ink.muted : StatusTone.active.color(.aresus)).frame(width: 7, height: 7)
                    .alignmentGuide(.firstTextBaseline) { $0[VerticalAlignment.center] + 5.5 }   // centred on the x-height
                    .accessibilityHidden(true)
                Text(status.summary).font(AppFont.text(18, weight: .semibold)).foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(status.summary).font(AppFont.text(22, weight: .bold))
                .foregroundStyle(stale ? Ink.secondary : StatusTone.issue.color(.aresus))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
    }
}

/// "checked 4 minutes ago", counting by itself.
struct WidgetChecked: View {
    let checked: Date
    var size: CGFloat = 10

    var body: some View {
        Text("checked \(TimeDataSource<Date>.currentDate, format: WidgetAge.style(since: checked))", tableName: "AresusShared")
            .font(AppFont.number(size, weight: .regular)).foregroundStyle(Ink.muted)
            .lineLimit(1).minimumScaleFactor(0.8)
    }
}

// MARK: lock screen (drawn by iOS in one tint: hierarchy by opacity, not colour)

struct WidgetRectangular: View {
    let content: WidgetContent
    let date: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: "ARESUS").font(AppFont.text(10, weight: .semibold)).tracking(1.6).foregroundStyle(.secondary)
            switch content {
            case .status(let status):
                ViewThatFits(in: .horizontal) {                     // as many whole names as fit
                    ForEach(status.lockLines, id: \.self) { line in
                        Text(line).font(AppFont.text(14, weight: .semibold)).lineLimit(1)
                    }
                }
                .opacity(status.isStale(at: date) ? 0.6 : 1)
                WidgetChecked(checked: status.checked, size: 11).foregroundStyle(.secondary)
            case .loggedOut:
                Text(WidgetMessage.loggedOut).font(AppFont.text(13)).lineLimit(2)
            case .notLoaded:
                Text(WidgetMessage.notLoaded).font(AppFont.text(13)).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// A ring of what is running, the number of issues inside (a checkmark when there are none).
struct WidgetCircular: View {
    let content: WidgetContent
    let date: Date

    var body: some View {
        switch content {
        case .status(let status):
            Gauge(value: status.runningShare) {
                Text(verbatim: "Aresus")
            } currentValueLabel: {
                if status.issueCount == 0 {
                    Image(systemName: "checkmark").font(.system(size: 17, weight: .bold))
                } else {
                    Text(verbatim: "\(status.issueCount)").font(AppFont.number(19, weight: .semibold))
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .opacity(status.isStale(at: date) ? 0.5 : 1)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: "Aresus, \(status.summary)"))
        case .loggedOut, .notLoaded:
            ZStack {
                AccessoryWidgetBackground()
                Image("Bust").resizable().scaledToFit().padding(9)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(content == .loggedOut ? WidgetMessage.loggedOut : WidgetMessage.notLoaded)
        }
    }
}
