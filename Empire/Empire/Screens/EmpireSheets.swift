import SwiftUI
import UIKit

/// The phone hub's dialogs (mobile.jsx `Dialog`, `Province`, `Approvals`, the "+" sheet and the idea page), as native
/// sheets: a quiet header with the section's name and a close button, then the page. Plain ivory buttons; gold only
/// for the status words and the "+" sheet's quiet Ask for access.
struct EmpireSheetView: View {
    let sheet: EmpireHome.Sheet
    let data: EmpireData
    let marks: [String: UIImage]
    let status: EmpireHomeStatus
    let actions: EmpireHomeActions
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title).font(AppFont.text(13, weight: .medium)).foregroundStyle(EmpireStyle.heading(dark: 0xB8BCB8))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .regular)).foregroundStyle(EmpireStyle.icon(dark: 0xA8A9A7))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.leading, 26).padding(.trailing, 14).padding(.top, sheet.isSmall ? 10 : 8).padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(EmpireStyle.hairline(dark: 0.05)).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error { ErrorNote(text: error).padding(.bottom, 20) }
                    page
                }
                .padding(.horizontal, 26).padding(.top, sheet.isSmall ? 22 : 26).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .interactiveDismissDisabled(status.requesting != nil || status.deciding)
    }

    private var title: String {
        switch sheet {
        case .province: String(localized: "Provinces")
        case .idea: String(localized: "Expansions")
        case .moreApps: String(localized: "More apps")
        case .approvals: String(localized: "Approvals")
        }
    }

    private var error: String? {
        switch sheet {
        case .moreApps: status.requestError
        case .approvals: status.approvalsError
        case .province, .idea: nil
        }
    }

    @ViewBuilder private var page: some View {
        switch sheet {
        case .province(let province, let unopened):
            // the live copy, so a refresh while the page is open shows through
            ProvincePage(province: data.projects.first { $0.slug == province.slug } ?? province, data: data,
                         mark: marks[province.slug], marks: marks, unopened: unopened, actions: actions)
        case .idea(let idea):
            IdeaPage(idea: idea)
        case .moreApps:
            MoreAppsPage(addable: data.addable, marks: marks, requesting: status.requesting, actions: actions)
        case .approvals:
            ApprovalsPage(status: status, actions: actions)
        }
    }
}

// MARK: - pieces shared by the pages

private enum Sheet {
    static let heading = EmpireStyle.heading(dark: 0xC2C4BF)
    static let body = EmpireStyle.body(dark: 0xADB2AD)
    static let cardStroke = EmpireStyle.edge(dark: 0x16 / 255)
}

private struct ErrorNote: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.text(12)).lineSpacing(5).foregroundStyle(LoginStyle.problemInk)
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(LoginStyle.problemFill, in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LoginStyle.problemEdge))
            .accessibilityAddTraits(.isStaticText)
    }
}

/// .em-primary / .em-secondary / .em-danger
private struct HubButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.text(12, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity, minHeight: 46)
            .padding(.horizontal, 16)
            .background(background, in: .rect(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(stroke))
            .opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.5)
    }

    private var foreground: Color {
        switch kind {
        case .primary: LoginStyle.standard.buttonText
        case .secondary: LoginStyle.standard.secondaryText
        case .danger: FormButtonStyle.dangerInk
        }
    }
    private var background: Color {
        switch kind {
        case .primary: LoginStyle.standard.button
        case .secondary: EmpireStyle.fill(dark: 0x04 / 255)
        case .danger: Color(light: Color(hex: 0xC24848, opacity: 0.10), dark: Color(hex: 0x5E2929, opacity: 0x2B / 255))
        }
    }
    private var stroke: Color {
        switch kind {
        case .primary: LoginStyle.standard.button
        case .secondary: EmpireStyle.edge(dark: 0x20 / 255)
        case .danger: Color(light: Color(hex: 0xB84A4A, opacity: 0.35), dark: Color(hex: 0xBC6D6D, opacity: 0x44 / 255))
        }
    }
}

private struct StatusWord: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.number(9, weight: .regular)).tracking(1.1)
            .foregroundStyle(Color(light: Color(hex: 0x86662A), dark: Color(hex: 0xC5AE7E)))
    }
}

private struct Note: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.text(12)).lineSpacing(6).foregroundStyle(EmpireStyle.body(dark: 0xB3BAB3))
            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
            .background(EmpireStyle.fill(dark: 0x04 / 255), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(EmpireStyle.edge(dark: 0x15 / 255)))
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(title).font(AppFont.text(13, weight: .medium)).foregroundStyle(Sheet.heading)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 14)
    }
}

private struct Paragraph: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.text(13)).lineSpacing(7.5).foregroundStyle(Sheet.body).fixedSize(horizontal: false, vertical: true)
    }
}

/// .em-detail-hero: the mark, the name, the status word, then what it is. With `open`, the mark and the name are the
/// link (a small arrow beside the name says so); there is no separate Open button.
private struct DetailHero<MarkView: View>: View {
    let name: String
    let status: String
    var blurb: String? = nil
    var live: String? = nil
    var open: (() -> Void)? = nil
    @ViewBuilder let mark: MarkView

    var body: some View {
        VStack(spacing: 0) {
            if let open {
                Button(action: open) { title }
                    .buttonStyle(PressedOpacity())
                    .accessibilityLabel("Open \(name)")
            } else {
                title
            }
            StatusWord(text: EmpireStyle.statusWord(status))
            if let blurb, !blurb.isEmpty {
                Text(blurb).font(AppFont.text(13)).lineSpacing(5.5).foregroundStyle(EmpireStyle.body(dark: 0xA9AEAA)).padding(.top, 18)
            }
            if let live {
                Text(live).font(AppFont.number(11, weight: .regular)).foregroundStyle(EmpireStyle.heading(dark: 0xC4C8C2)).padding(.top, 18)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    private var title: some View {
        VStack(spacing: 0) {
            mark.frame(width: 72, height: 80).padding(.bottom, 14)
            Text(name).font(AppFont.text(26, weight: .medium)).foregroundStyle(EmpireStyle.title(dark: 0xEEEEE8))
                .overlay(alignment: .trailing) {
                    if open != nil {
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(EmpireStyle.quiet(dark: 0x8F9390)).offset(x: 20)
                    }
                }
                .padding(.bottom, 12)
        }
        .contentShape(Rectangle())
    }
}

private struct PressedOpacity: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.6 : 1)
    }
}

/// A province's mark at page size: the image, else its initial in a thin circle (.em-monogram, 48 pt; smaller in a
/// "+" sheet row).
private struct PageMark: View {
    let name: String
    let image: UIImage?
    var monogram: CGFloat = 48
    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Text(String(name.prefix(1)).uppercased()).font(AppFont.text(monogram * 0.46))
                .foregroundStyle(EmpireStyle.title(dark: 0xE6E6DF))
                .frame(width: monogram, height: monogram)
                .overlay(Circle().strokeBorder(EmpireStyle.edge(dark: 0x22 / 255)))
        }
    }
}

// MARK: - province

/// A province's page (hold its card, or a tap that opened nothing). When opening it opened nothing and the hub sends
/// the app's install link (TestFlight while testing, the App Store later), the page offers Install.
private struct ProvincePage: View {
    let province: Province
    let data: EmpireData
    let mark: UIImage?
    let marks: [String: UIImage]
    let actions: EmpireHomeActions
    /// Opening it opened nothing: its app is not on this iPhone and it has no website. The name stops being a link.
    @State private var unopened: Bool
    @Environment(\.openURL) private var openURL

    init(province: Province, data: EmpireData, mark: UIImage?, marks: [String: UIImage], unopened: Bool,
         actions: EmpireHomeActions) {
        self.province = province
        self.data = data
        self.mark = mark
        self.marks = marks
        self.actions = actions
        _unopened = State(initialValue: unopened)
    }

    private var admin: Bool { data.me.admin }
    private var comingSoon: Bool { !admin && province.isComingSoon }
    /// The name opens the province, unless it is known not to open.
    private var link: (() -> Void)? {
        guard province.canOpen, !unopened else { return nil }
        return { open() }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHero(name: province.name, status: comingSoon ? "COMING SOON" : province.status,
                       blurb: province.blurb, live: province.live,
                       open: link) {
                PageMark(name: province.name, image: mark)
            }
            if comingSoon {
                Note(text: String(localized: "Coming soon. You’ll be able to open \(province.name) here when it’s available."))
                    .padding(.bottom, 8)
            } else if unopened {
                Note(text: String(localized: "The \(province.name) app isn’t on this iPhone.")).padding(.bottom, 8)
                if let install = province.installURL {
                    Button { openURL(install) } label: {
                        HStack(spacing: 8) { Image(systemName: "arrow.down.circle").font(.system(size: 13)); Text("Install") }
                    }
                    .buttonStyle(HubButtonStyle(kind: .primary))
                    .accessibilityLabel(Text("Install \(province.name)"))
                    .padding(.top, 6).padding(.bottom, 8)
                }
            }
            DetailSection(title: String(localized: "About")) { Paragraph(text: province.detail.about.isEmpty ? province.blurb : province.detail.about) }
            DetailSection(title: String(localized: "Features")) {
                if province.detail.features.isEmpty {
                    Paragraph(text: String(localized: "No features listed yet."))
                } else {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(Array(province.detail.features.enumerated()), id: \.offset) { _, feature in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .medium)).foregroundStyle(EmpireStyle.quiet(dark: 0x8C9391))
                                Paragraph(text: feature)
                            }
                        }
                    }
                }
            }
            Rectangle().fill(EmpireStyle.hairline(dark: 0x10 / 255)).frame(height: 1).padding(.top, 14)
            ChronicleList(title: String(localized: "What's new"), entries: data.chronicle.filter { $0.project == province.slug }, marks: marks)
                .padding(.top, 23)
        }
    }

    private func open() {
        Task {
            let opened = await actions.open(province)
            if !opened { withAnimation(.easeOut(duration: 0.2)) { unopened = true } }
        }
    }
}

// MARK: - idea

private struct IdeaPage: View {
    let idea: Idea
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHero(name: idea.title, status: "PLANNED") {
                Image(systemName: "square.stack.3d.up").font(.system(size: 30, weight: .light)).foregroundStyle(EmpireStyle.icon(dark: 0xBCC0BD))
            }
            DetailSection(title: String(localized: "About")) { Paragraph(text: idea.note) }
        }
    }
}

// MARK: - more apps

/// The "+" card's sheet (members): the other apps open to users, each with its state on the right: Ask for access (a
/// quiet gold button; then "Asking…"), Asked · waiting for approval, or Coming soon (shown, not requestable). The
/// state after asking is the hub's answer; a refusal shows its sentence at the top of the sheet.
private struct MoreAppsPage: View {
    let addable: [Province]
    let marks: [String: UIImage]
    let requesting: String?
    let actions: EmpireHomeActions

    var body: some View {
        if addable.isEmpty {
            EmptyState(symbol: "checkmark", title: String(localized: "No other apps right now."),
                       note: String(localized: "New apps show up here when they open."))
        } else {
            VStack(alignment: .leading, spacing: 0) {
                Text("Ask for an app, and it joins your ring once it’s approved.")
                    .font(AppFont.text(12)).lineSpacing(5).foregroundStyle(EmpireStyle.body(dark: 0xA9AEAA))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 20)
                VStack(spacing: 12) {
                    ForEach(addable) { province in row(province) }
                }
            }
        }
    }

    private func row(_ province: Province) -> some View {
        HStack(alignment: .top, spacing: 14) {
            PageMark(name: province.name, image: marks[province.slug], monogram: 38).frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 10) {
                    Text(province.name).font(AppFont.text(15, weight: .medium))
                        .foregroundStyle(EmpireStyle.title(dark: 0xE4E9DF)).lineLimit(1)
                        .layoutPriority(1)                  // the state takes what is left (one line or two)
                    Spacer(minLength: 6)
                    state(province)
                }
                .frame(minHeight: 40)
                if !province.blurb.isEmpty {
                    Text(province.blurb).font(AppFont.text(12)).lineSpacing(4)
                        .foregroundStyle(EmpireStyle.quiet(dark: 0x969E97))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .hubCard(padding: 16)
    }

    @ViewBuilder private func state(_ province: Province) -> some View {
        if province.isComingSoon {
            StatusWord(text: EmpireStyle.statusWord("COMING SOON"))
        } else if province.access == .requested {
            // One line when it fits beside the name, else two.
            ViewThatFits(in: .horizontal) {
                Text("Asked · waiting for approval").lineLimit(1)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Asked")
                    Text("waiting for approval").foregroundStyle(EmpireStyle.quiet(dark: 0x8F9390))
                }
            }
            .font(AppFont.text(11)).foregroundStyle(EmpireStyle.heading(dark: 0xC3C9C1))
            .multilineTextAlignment(.trailing)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Asked, waiting for approval"))
        } else if province.canRequest {
            let asking = requesting == province.slug
            Button { Task { await actions.request(province.slug) } } label: {
                HStack(spacing: 6) {
                    if asking { ProgressView().controlSize(.mini).tint(EmpireStyle.gold2) }
                    Text(asking ? "Asking…" : "Ask for access")
                }
            }
            .buttonStyle(AskButtonStyle())
            .disabled(requesting != nil)
            .accessibilityLabel(asking ? Text("Asking for \(province.name)") : Text("Ask for access to \(province.name)"))
        }
    }
}

/// The "+" sheet's Ask for access: a quiet capsule with the hub's gold ink and a thin gold edge (gold as an accent only).
private struct AskButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.text(11.5, weight: .semibold))
            .foregroundStyle(EmpireStyle.gold2)
            .lineLimit(1)
            .padding(.horizontal, 13).frame(minHeight: 32)
            .background(Color(light: Color(hex: 0x9A6B1F, opacity: 0.06), dark: Color(hex: 0xCFA24F, opacity: 0.06)),
                        in: .capsule)
            .overlay(Capsule().strokeBorder(Color(light: Color(hex: 0x9A6B1F, opacity: 0.42),
                                                  dark: Color(hex: 0xCFA24F, opacity: 0.40))))
            .contentShape(.capsule)
            .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.45)
    }
}

// MARK: - approvals

/// New sign-ups first, then approved accounts asking for more apps (each with the apps it asked for). Approving grants
/// what was asked; declining deletes a new sign-up, or only clears an approved account's request.
private struct ApprovalsPage: View {
    let status: EmpireHomeStatus
    let actions: EmpireHomeActions
    @State private var declining: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if status.approvalsLoading && status.approvals.isEmpty {
                Text("Loading pending accounts…").font(AppFont.text(12)).foregroundStyle(EmpireStyle.quiet(dark: 0x9B9F9D)).padding(.vertical, 12)
            } else if status.approvals.isEmpty && status.approvalsError != nil {
                Text("Pending accounts could not be loaded.").font(AppFont.text(12)).foregroundStyle(EmpireStyle.quiet(dark: 0x9B9F9D))
            } else if status.approvals.isEmpty {
                EmptyState(symbol: "checkmark", title: String(localized: "No pending accounts."), note: nil)
            } else {
                let newAccounts = status.approvals.filter { !$0.approved }
                let requests = status.approvals.filter(\.approved)
                if !newAccounts.isEmpty {
                    group(Text("Pending accounts"), newAccounts)
                }
                if !requests.isEmpty {
                    group(Text("Access requests"), requests).padding(.top, newAccounts.isEmpty ? 0 : 34)
                }
            }
            if status.deciding {
                Text("Updating account…").font(AppFont.text(12)).foregroundStyle(EmpireStyle.quiet(dark: 0x9B9F9D)).padding(.top, 14)
            }
        }
        // A card that went (decided here or elsewhere) takes its open confirmation with it.
        .onChange(of: status.approvals.map(\.id)) { _, ids in
            if let declining, !ids.contains(declining) { self.declining = nil }
        }
    }

    private func group(_ title: Text, _ accounts: [PendingAccount]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                title.font(AppFont.text(13, weight: .medium)).foregroundStyle(Sheet.heading)
                Spacer()
                Text(String(format: "%02d", accounts.count)).font(AppFont.number(11, weight: .regular))
                    .foregroundStyle(EmpireStyle.quiet(dark: 0x858A8A))
            }
            .padding(.bottom, 25)
            VStack(spacing: 18) {
                ForEach(accounts) { account in card(account) }
            }
        }
    }

    private func card(_ account: PendingAccount) -> some View {
        let name = account.name.isEmpty ? String(localized: "New account") : account.name
        let who = account.name.isEmpty ? account.email : account.name
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text(String(who.prefix(1)).uppercased())
                    .font(AppFont.text(14)).foregroundStyle(EmpireStyle.heading(dark: 0xC3C9C1))
                    .frame(width: 38, height: 38)
                    .background(EmpireStyle.fill(dark: 0x06 / 255), in: .circle)
                    .overlay(Circle().strokeBorder(EmpireStyle.edge(dark: 0x17 / 255)))
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(AppFont.text(15, weight: .medium)).foregroundStyle(EmpireStyle.title(dark: 0xE0E4DC))
                    Text(account.email).font(AppFont.text(11)).foregroundStyle(EmpireStyle.quiet(dark: 0x969E97))
                    if account.awaitsEmailConfirmation {
                        Text("Email not confirmed yet").font(AppFont.text(11)).foregroundStyle(EmpireStyle.quiet(dark: 0x879089))
                    }
                }
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 9) {
                if !account.requested.isEmpty {
                    GridRow {
                        Text("Asks for").font(AppFont.text(10)).foregroundStyle(EmpireStyle.quiet(dark: 0x879089))
                        Text(verbatim: account.requestedApps).font(AppFont.text(12, weight: .medium))
                            .foregroundStyle(EmpireStyle.heading(dark: 0xC3C9C1))
                    }
                }
                if !account.approved {
                    GridRow {
                        Text("Signed up").font(AppFont.text(10))
                        Text(String(account.created.prefix(10))).font(AppFont.number(9, weight: .regular))
                    }
                    .foregroundStyle(EmpireStyle.quiet(dark: 0x879089))
                }
            }
            .padding(.vertical, 20)
            if declining == account.id {
                (account.approved
                    ? Text("Decline \(who)'s request? The account stays; only the request is cleared.")
                    : Text("Decline \(who)? This deletes their pending sign-up."))
                    .font(AppFont.text(12)).lineSpacing(5).foregroundStyle(Color(light: Color(hex: 0x8C5A4E), dark: Color(hex: 0xC6B1AB))).padding(.bottom, 14)
                HStack(spacing: 10) {
                    Button(account.approved ? "Keep request" : "Keep account") { declining = nil }
                        .buttonStyle(HubButtonStyle(kind: .secondary))
                    Button("Confirm decline") {
                        Task { if await actions.decide(account, false) { declining = nil } }
                    }
                    .buttonStyle(HubButtonStyle(kind: .danger))
                }
                .disabled(status.deciding)
            } else {
                HStack(spacing: 10) {
                    Button { Task { _ = await actions.decide(account, true) } } label: {
                        HStack(spacing: 8) { Image(systemName: "checkmark").font(.system(size: 12)); Text("Approve") }
                    }
                    .buttonStyle(HubButtonStyle(kind: .primary))
                    Button("Decline") { declining = account.id }.buttonStyle(HubButtonStyle(kind: .secondary))
                }
                .disabled(status.deciding)
            }
        }
        .hubCard()
    }
}

private struct EmptyState: View {
    let symbol: String
    let title: String
    let note: String?
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(EmpireStyle.icon(dark: 0xA0A9A1))
            Text(title).font(AppFont.text(15, weight: .medium)).foregroundStyle(EmpireStyle.heading(dark: 0xC9CFC5))
            if let note { Text(note).font(AppFont.text(12)).foregroundStyle(EmpireStyle.quiet(dark: 0x969F96)) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 25).padding(.bottom, 30)
    }
}

private extension View {
    /// .em-account / .em-catalog-card
    func hubCard(padding inset: CGFloat = 20) -> some View {
        padding(inset)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
                ZStack {
                    shape.fill(EmpireStyle.card)
                    shape.fill(LinearGradient(colors: [Color(light: .white.opacity(0.6), dark: .white.opacity(0x06 / 255)), .clear],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Sheet.cardStroke))
    }
}
