import SwiftUI
import UIKit

/// What the home screen can do; `EmpireStore` (brief 08) provides it, previews fake it.
struct EmpireHomeActions {
    /// The province's app if installed, else its website; false when neither opened (the page shows instead).
    var open: (Province) async -> Bool = { _ in true }
    /// Asks for access to an app of the "+" sheet; true when the hub took it (the sheet then shows its new state).
    var request: (String) async -> Bool = { _ in true }
    var loadApprovals: () async -> Void = {}
    /// (the account as its card shows it, approve); true when the decision went through.
    var decide: (PendingAccount, Bool) async -> Bool = { _, _ in true }
    var openSettings: () -> Void = {}                     // Settings, with Log out (the app presents it)
    var refresh: () async -> Void = {}
}

/// The store's busy and error state, as the sheets show it.
struct EmpireHomeStatus {
    var requesting: String?         // the app of the "+" sheet being asked for
    var requestError: String?
    var approvals: [PendingAccount] = []
    var approvalsLoading = false
    var approvalsError: String?
    var deciding = false
    var loadError: String?          // a refresh failed; the data shown is the last good one
}

/// The throne room, as approved on the phone hub (ares-empire web/app/mobile.jsx): header (crest · THE EMPIRE ·
/// quiet icons), the faded marble bust, the desktop's wheel with one quiet line under it, and the chronicle (Patrik)
/// or "What's new" (everyone else), ending in THE EMPIRE in gold (`WordmarkScrollView`). No slogans, gold only as an
/// accent.
struct EmpireHome: View {
    let data: EmpireData
    let marks: [String: UIImage]
    let status: EmpireHomeStatus
    let actions: EmpireHomeActions
    /// The open sheet and the expansions, kept by `ContentView` so a tapped notification can close them.
    @Bindable var navigation: EmpireNavigation

    @Environment(\.colorScheme) private var scheme
    @State private var front: EmpireRing.Item?

    enum Sheet: Identifiable {
        /// `unopened`: tapping it in the ring opened nothing (its app is not on this iPhone, and it has no website).
        /// `moreApps`: the "+" card's sheet, the other apps open to users (members).
        case province(Province, unopened: Bool = false), idea(Idea), moreApps, approvals
        var id: String {
            switch self {
            case .province(let p, _): "p-" + p.slug
            case .idea(let i): "i-" + i.title
            case .moreApps: "more-apps"
            case .approvals: "approvals"
            }
        }
    }

    private var admin: Bool { data.me.admin }
    private var expanded: Bool { navigation.expanded }

    var body: some View {
        ZStack(alignment: .top) {
            EmpireStyle.background.ignoresSafeArea()
            backdrop
            WordmarkScrollView {
                VStack(spacing: 0) {
                    header
                    if let loadError = status.loadError {
                        Text(loadError).font(AppFont.text(11.5)).foregroundStyle(LoginStyle.problemInk)
                            .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 2)
                    }
                    ringSection
                    if !expanded {
                        Divider().overlay(EmpireStyle.hairline(dark: 0.06)).padding(.horizontal, 26).padding(.top, 14)
                        ChronicleList(title: admin ? String(localized: "Chronicle") : String(localized: "What's new"), entries: data.chronicle, marks: marks)
                            .padding(.horizontal, 26).padding(.top, 22)
                    }
                }
            } band: { width in
                WordmarkBand(word: "THE EMPIRE", width: width, fill: AnyShapeStyle(EmpireStyle.goldText))
            }
            .scrollIndicators(.hidden)
            .refreshable { await actions.refresh() }
            #if DEBUG
            .defaultScrollAnchor(LaunchArguments.current.contains("-scrollToEnd") ? .bottom : nil)   // screenshots
            #endif
        }
        #if DEBUG
        .onAppear(perform: openDebugSheet)
        #endif
        .sheet(item: $navigation.sheet) { sheet in
            EmpireSheetView(sheet: sheet, data: data, marks: marks, status: status, actions: actions,
                            close: { navigation.sheet = nil })
                .presentationDetents(sheet.isSmall ? [.medium, .large] : [.large])
                .presentationDragIndicator(sheet.isSmall ? .visible : .hidden)
                .presentationBackground(EmpireStyle.sheetBackground)
        }
    }

    // MARK: header

    private var header: some View {
        ZStack {
            Text(expanded ? "EXPANSIONS" : "THE EMPIRE")
                .font(AppFont.text(12.5, weight: .bold)).tracking(5.2).padding(.leading, 5.2).goldFill()   // text-indent balances the tracking
                .onTapGesture { if admin { withAnimation(.easeInOut(duration: 0.25)) { navigation.expanded.toggle() } } }
                .accessibilityAddTraits(admin ? .isButton : [])
            HStack(spacing: 2) {
                Image("Crest").resizable().scaledToFit().frame(height: 42).shadow(color: EmpireStyle.shadow(dark: 0.65), radius: 6, y: 4)
                    .accessibilityHidden(true)
                Spacer()
                if admin {
                    iconButton(expanded ? "circle.dotted" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? String(localized: "Show the provinces") : String(localized: "Show the expansions")) {
                        withAnimation(.easeInOut(duration: 0.25)) { navigation.expanded.toggle() }
                    }
                    // No count when the hub could not count (`pending` null): no badge rather than a wrong one.
                    iconButton("tray", label: data.pending.map { String(localized: "Approvals, \($0) pending") }
                                   ?? String(localized: "Approvals"), badge: data.pending ?? 0) {
                        navigation.sheet = .approvals; Task { await actions.loadApprovals() }
                    }
                }
                iconButton("gearshape", label: String(localized: "Settings")) { actions.openSettings() }
            }
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.top, 6).padding(.bottom, 4)
    }

    private func iconButton(_ symbol: String, label: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(EmpireStyle.icon(dark: 0xA8A9A7))
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(verbatim: "\(badge)").font(AppFont.number(9, weight: .semibold)).foregroundStyle(Color(light: Color(hex: 0xF3F1EA), dark: Color(hex: 0x0B0C0E)))
                            .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                            .background(Color(light: Color(hex: 0x2A2925), dark: Color(hex: 0xD9D9D3)), in: .capsule).offset(x: -4, y: 6)
                    }
                }
        }
        .accessibilityLabel(label)
    }

    // MARK: backdrop

    /// The desktop's bust, large on the left and faded (as the desktop recedes it on small screens). On the ivory wall
    /// it is laid in with multiply, a faint grey relief.
    private var backdrop: some View {
        Image("Backdrop").resizable().scaledToFit().frame(height: 560)
            .blendMode(scheme == .light ? .multiply : .normal)
            .opacity(scheme == .light ? 0.13 : 0.22)
            .mask(LinearGradient(stops: [.init(color: .black, location: 0.3), .init(color: .clear, location: 0.92)],
                                 startPoint: .top, endPoint: .bottom))
            .frame(maxWidth: .infinity, alignment: .leading).offset(x: -150)
            .allowsHitTesting(false).accessibilityHidden(true)
            .ignoresSafeArea(edges: .top)
    }

    // MARK: ring

    private var ringItems: [EmpireRing.Item] {
        if expanded {
            return data.ideas.map { .init(id: "idea:" + $0.title, name: $0.title, status: "SCOUTED", isAdd: false) }
        }
        var items = data.projects.map { p in
            EmpireRing.Item(id: p.slug, name: p.name, status: !admin && p.isComingSoon ? "COMING SOON" : p.status, isAdd: false)
        }
        if !admin { items.append(.init(id: "__add", name: String(localized: "More apps"), status: "", isAdd: true)) }
        return items
    }

    private var ringSection: some View {
        VStack(spacing: 2) {
            if ringItems.isEmpty {
                Text("No expansions yet.").font(AppFont.text(12)).foregroundStyle(EmpireStyle.quiet(dark: 0x9B9F9D))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 26).padding(.vertical, 12)
            } else {
                EmpireRing(items: ringItems, marks: marks, onOpen: open, onHold: details, onFront: { front = $0 })
                    .id(expanded ? "ideas" : "provinces:" + data.projects.map(\.slug).joined(separator: ","))
                    .frame(height: 158)
                caption.frame(minHeight: 18).padding(.horizontal, 40)
            }
        }
        .padding(.top, 46).padding(.bottom, 16)   // lower than the website (Patrik, 2026-10-24)
    }

    @ViewBuilder private var caption: some View {
        if let front, !expanded, let province = data.projects.first(where: { $0.slug == front.id }) {
            if let live = province.live {
                Text(live).font(AppFont.number(11, weight: .regular)).foregroundStyle(EmpireStyle.heading(dark: 0xB5B8B4))
            } else {
                Text(province.blurb).font(AppFont.text(12.5)).foregroundStyle(EmpireStyle.quiet(dark: 0x8F9390)).multilineTextAlignment(.center)
            }
        } else if front == nil, !admin, !expanded {
            Text("Ask for access to more apps").font(AppFont.text(12.5)).foregroundStyle(EmpireStyle.quiet(dark: 0x8F9390))
        }
    }

    /// Tapping the front tab: a province opens (its app, else its website); anything that does not open shows its page.
    private func open(_ item: EmpireRing.Item) {
        guard !expanded, let province = data.projects.first(where: { $0.slug == item.id }), province.canOpen else {
            details(item)
            return
        }
        Task {
            let opened = await actions.open(province)
            if !opened { navigation.sheet = .province(province, unopened: true) }
        }
    }

    /// Holding a tab: its page (the "+" card: the other apps to ask for).
    private func details(_ item: EmpireRing.Item) {
        if item.isAdd { navigation.sheet = .moreApps; return }
        if expanded, let idea = data.ideas.first(where: { "idea:" + $0.title == item.id }) {
            navigation.sheet = .idea(idea)
            return
        }
        if let province = data.projects.first(where: { $0.slug == item.id }) { navigation.sheet = .province(province) }
    }
}

#if DEBUG
extension EmpireHome {
    /// Screenshots: `-openSheet province|unopened|idea|add|approvals|settings` opens that page at launch (`unopened`:
    /// the first province's page as a ring tap that opened nothing shows it; `add`: the "+" card's sheet).
    /// `-tapProvince <slug>` taps that province in the ring, as a finger would (its app, its website, or its page).
    private func openDebugSheet() {
        let arguments = LaunchArguments.current
        if let index = arguments.firstIndex(of: "-tapProvince"), arguments.indices.contains(index + 1) {
            open(EmpireRing.Item(id: arguments[index + 1], name: "", status: "", isAdd: false))
        }
        guard let index = arguments.firstIndex(of: "-openSheet"), arguments.indices.contains(index + 1) else { return }
        switch arguments[index + 1] {
        case "province": navigation.sheet = data.projects.first.map { .province($0) }
        case "unopened": navigation.sheet = data.projects.first.map { .province($0, unopened: true) }
        case "idea": navigation.sheet = data.ideas.first.map { .idea($0) }
        case "add": navigation.sheet = .moreApps
        case "approvals":
            navigation.sheet = .approvals
            Task { await actions.loadApprovals() }          // as the tray button does
        case "settings": actions.openSettings()
        default: break
        }
    }
}
#endif

extension Province {
    /// Whether opening it is worth trying (`ProvinceOpener`): open for this account, with an app or a website. Whether
    /// the app is installed shows only when it is tried.
    var canOpen: Bool { !isComingSoon && (app != nil || !url.isEmpty) }
}

extension EmpireHome.Sheet {
    var isSmall: Bool { if case .moreApps = self { true } else { false } }
}
