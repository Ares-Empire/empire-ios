import SwiftUI
import UIKit

/// What the home screen can do; `EmpireStore` (brief 08) provides it, previews fake it.
/// Ring changes report success so the sheet closes only when the server took the change.
struct EmpireHomeActions {
    var open: (Province) -> Void = { _ in }              // the province's app if installed, else its website
    var add: (String) async -> Bool = { _ in true }
    var remove: (String) async -> Bool = { _ in true }
    var loadApprovals: () async -> Void = {}
    var decide: (String, Bool) async -> Bool = { _, _ in true }   // (account id, approve)
    var logOut: () -> Void = {}
    var refresh: () async -> Void = {}
}

/// The store's busy and error state, as the sheets show it.
struct EmpireHomeStatus {
    var ringBusy = false
    var ringError: String?
    var approvals: [PendingAccount] = []
    var approvalsLoading = false
    var approvalsError: String?
    var deciding = false
    var loadError: String?          // a refresh failed; the data shown is the last good one
}

/// The throne room, as approved on the phone hub (ares-empire web/app/mobile.jsx): header (crest · THE EMPIRE ·
/// quiet icons), the faded marble bust, the desktop's wheel with one quiet line under it, and the chronicle (Patrik)
/// or "What's new" (everyone else). No slogans, gold only as an accent.
struct EmpireHome: View {
    let data: EmpireData
    let marks: [String: UIImage]
    let status: EmpireHomeStatus
    let actions: EmpireHomeActions

    @State private var expanded = false
    @State private var front: EmpireRing.Item?
    @State private var sheet: Sheet?

    enum Sheet: Identifiable {
        case province(Province), idea(Idea), add, approvals
        var id: String {
            switch self {
            case .province(let p): "p-" + p.slug
            case .idea(let i): "i-" + i.title
            case .add: "add"
            case .approvals: "approvals"
            }
        }
    }

    private var admin: Bool { data.me.admin }

    var body: some View {
        ZStack(alignment: .top) {
            EmpireStyle.background.ignoresSafeArea()
            backdrop
            ScrollView {
                VStack(spacing: 0) {
                    header
                    if let loadError = status.loadError {
                        Text(loadError).font(AppFont.text(11.5)).foregroundStyle(Color(hex: 0xD9B4A6))
                            .multilineTextAlignment(.center).padding(.horizontal, 40).padding(.top, 2)
                    }
                    ringSection
                    if !expanded {
                        Divider().overlay(Color.white.opacity(0.06)).padding(.horizontal, 26).padding(.top, 14)
                        ChronicleList(title: admin ? String(localized: "Chronicle") : String(localized: "What's new"), entries: data.chronicle, marks: marks)
                            .padding(.horizontal, 26).padding(.top, 22).padding(.bottom, 40)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { await actions.refresh() }
        }
        .preferredColorScheme(.dark)
        #if DEBUG
        .onAppear(perform: openDebugSheet)
        #endif
        .sheet(item: $sheet) { sheet in
            EmpireSheetView(sheet: sheet, data: data, marks: marks, status: status, actions: actions, close: { self.sheet = nil })
                .presentationDetents(sheet.isSmall ? [.medium] : [.large])
                .presentationDragIndicator(sheet.isSmall ? .visible : .hidden)
                .presentationBackground(Color(hex: 0x0A0C0E))
                .preferredColorScheme(.dark)
        }
    }

    // MARK: header

    private var header: some View {
        ZStack {
            Text(expanded ? "EXPANSIONS" : "THE EMPIRE")
                .font(AppFont.text(12.5, weight: .bold)).tracking(5.2).padding(.leading, 5.2).goldFill()   // text-indent balances the tracking
                .onTapGesture { if admin { withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() } } }
                .accessibilityAddTraits(admin ? .isButton : [])
            HStack(spacing: 2) {
                Image("Crest").resizable().scaledToFit().frame(height: 42).shadow(color: .black.opacity(0.65), radius: 6, y: 4)
                    .accessibilityHidden(true)
                Spacer()
                if admin {
                    iconButton(expanded ? "circle.dotted" : "arrow.up.left.and.arrow.down.right",
                               label: expanded ? String(localized: "Show the provinces") : String(localized: "Show the expansions")) {
                        withAnimation(.easeInOut(duration: 0.25)) { expanded.toggle() }
                    }
                    iconButton("tray", label: String(localized: "Approvals, \(data.pending) pending"), badge: data.pending) {
                        sheet = .approvals; Task { await actions.loadApprovals() }
                    }
                }
                iconButton("rectangle.portrait.and.arrow.right", label: String(localized: "Log out")) { actions.logOut() }
            }
        }
        .padding(.leading, 18).padding(.trailing, 8).padding(.top, 6).padding(.bottom, 4)
    }

    private func iconButton(_ symbol: String, label: String, badge: Int = 0, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .regular)).foregroundStyle(Color(hex: 0xA8A9A7))
                .frame(width: 44, height: 44)
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        Text(verbatim: "\(badge)").font(AppFont.number(9, weight: .semibold)).foregroundStyle(Color(hex: 0x0B0C0E))
                            .padding(.horizontal, 4).frame(minWidth: 15, minHeight: 15)
                            .background(Color(hex: 0xD9D9D3), in: .capsule).offset(x: -4, y: 6)
                    }
                }
        }
        .accessibilityLabel(label)
    }

    // MARK: backdrop

    /// The desktop's bust, large on the left and faded (as the desktop recedes it on small screens).
    private var backdrop: some View {
        Image("Backdrop").resizable().scaledToFit().frame(height: 560)
            .opacity(0.22)
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
        if !admin { items.append(.init(id: "__add", name: String(localized: "Add a province"), status: "", isAdd: true)) }
        return items
    }

    private var ringSection: some View {
        VStack(spacing: 2) {
            if ringItems.isEmpty {
                Text("No expansions yet.").font(AppFont.text(12)).foregroundStyle(Color(hex: 0x9B9F9D))
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
                Text(live).font(AppFont.number(11, weight: .regular)).foregroundStyle(Color(hex: 0xB5B8B4))
            } else {
                Text(province.blurb).font(AppFont.text(12.5)).foregroundStyle(Color(hex: 0x8F9390)).multilineTextAlignment(.center)
            }
        } else if front == nil, !admin, !expanded {
            Text("Add a province to your ring").font(AppFont.text(12.5)).foregroundStyle(Color(hex: 0x8F9390))
        }
    }

    /// Tapping the front tab: a province opens (its app, else its website); anything that cannot open shows its page.
    private func open(_ item: EmpireRing.Item) {
        if let province = data.projects.first(where: { $0.slug == item.id }), !expanded, province.canOpen {
            actions.open(province)
        } else {
            details(item)
        }
    }

    /// Holding a tab: its page.
    private func details(_ item: EmpireRing.Item) {
        if item.isAdd { sheet = .add; return }
        if expanded, let idea = data.ideas.first(where: { "idea:" + $0.title == item.id }) { sheet = .idea(idea); return }
        if let province = data.projects.first(where: { $0.slug == item.id }) { sheet = .province(province) }
    }
}

#if DEBUG
extension EmpireHome {
    /// Screenshots: `-openSheet province|idea|add|approvals` opens that page at launch.
    private func openDebugSheet() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-openSheet"), arguments.indices.contains(index + 1) else { return }
        switch arguments[index + 1] {
        case "province": sheet = data.projects.first.map { .province($0) }
        case "idea": sheet = data.ideas.first.map { .idea($0) }
        case "add": sheet = .add
        case "approvals": sheet = .approvals
        default: break
        }
    }
}
#endif

extension Province {
    /// Whether it can be opened from the phone (as `ProvinceOpener` does): open for this account, with an app or a website.
    var canOpen: Bool { !isComingSoon && (app != nil || !url.isEmpty) }
}

extension EmpireHome.Sheet {
    var isSmall: Bool { if case .add = self { true } else { false } }
}
