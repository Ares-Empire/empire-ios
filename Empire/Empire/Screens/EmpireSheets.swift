import SwiftUI
import UIKit

/// The phone hub's dialogs (mobile.jsx `Dialog`, `Province`, `Approvals`, the add sheet and the idea page), as native
/// sheets: a quiet header with the section's name and a close button, then the page. Plain ivory buttons, no gold.
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
                Text(title).font(AppFont.text(13, weight: .medium)).foregroundStyle(Color(hex: 0xB8BCB8))
                Spacer()
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 15, weight: .regular)).foregroundStyle(Color(hex: 0xA8A9A7))
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Close")
            }
            .padding(.leading, 26).padding(.trailing, 14).padding(.top, sheet.isSmall ? 10 : 8).padding(.bottom, 4)
            .overlay(alignment: .bottom) { Rectangle().fill(.white.opacity(0.05)).frame(height: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let error { ErrorNote(text: error).padding(.bottom, 20) }
                    page
                }
                .padding(.horizontal, 26).padding(.top, sheet.isSmall ? 22 : 26).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .interactiveDismissDisabled(status.ringBusy || status.deciding)
    }

    private var title: String {
        switch sheet {
        case .province: String(localized: "Provinces")
        case .idea: String(localized: "Expansions")
        case .add: String(localized: "Add a province")
        case .approvals: String(localized: "Approvals")
        }
    }

    private var error: String? {
        switch sheet {
        case .province, .add: status.ringError
        case .approvals: status.approvalsError
        case .idea: nil
        }
    }

    @ViewBuilder private var page: some View {
        switch sheet {
        case .province(let province):
            // the live copy, so a refresh while the page is open shows through
            ProvincePage(province: data.projects.first { $0.slug == province.slug } ?? province, data: data,
                         mark: marks[province.slug], marks: marks, busy: status.ringBusy, actions: actions, close: close)
        case .idea(let idea):
            IdeaPage(idea: idea)
        case .add:
            AddPage(addable: data.addable, marks: marks, busy: status.ringBusy, actions: actions, close: close)
        case .approvals:
            ApprovalsPage(status: status, actions: actions)
        }
    }
}

// MARK: - pieces shared by the pages

private enum Sheet {
    static let heading = Color(hex: 0xC2C4BF)
    static let body = Color(hex: 0xADB2AD)
    static let cardStroke = Color.white.opacity(0x16 / 255)
}

private struct ErrorNote: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.text(12)).lineSpacing(5).foregroundStyle(Color(hex: 0xD9B4A6))
            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            .background(Color(hex: 0x3A2222, opacity: 0.19), in: .rect(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(hex: 0xCF8F78, opacity: 0.2)))
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
        case .primary: Color(hex: 0x141617)
        case .secondary: Color(hex: 0xC0C4BF)
        case .danger: Color(hex: 0xE4AAAA)
        }
    }
    private var background: Color {
        switch kind {
        case .primary: Color(hex: 0xEEEEE8)
        case .secondary: .white.opacity(0x04 / 255)
        case .danger: Color(hex: 0x5E2929, opacity: 0x2B / 255)
        }
    }
    private var stroke: Color {
        switch kind {
        case .primary: Color(hex: 0xEEEEE8)
        case .secondary: .white.opacity(0x20 / 255)
        case .danger: Color(hex: 0xBC6D6D, opacity: 0x44 / 255)
        }
    }
}

private struct StatusWord: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.number(9, weight: .regular)).tracking(1.1).foregroundStyle(Color(hex: 0xC5AE7E))
    }
}

private struct Note: View {
    let text: String
    var body: some View {
        Text(text).font(AppFont.text(12)).lineSpacing(6).foregroundStyle(Color(hex: 0xB3BAB3))
            .frame(maxWidth: .infinity, alignment: .leading).padding(15)
            .background(.white.opacity(0x04 / 255), in: .rect(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.white.opacity(0x15 / 255)))
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
                Text(blurb).font(AppFont.text(13)).lineSpacing(5.5).foregroundStyle(Color(hex: 0xA9AEAA)).padding(.top, 18)
            }
            if let live {
                Text(live).font(AppFont.number(11, weight: .regular)).foregroundStyle(Color(hex: 0xC4C8C2)).padding(.top, 18)
            }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.bottom, 24)
    }

    private var title: some View {
        VStack(spacing: 0) {
            mark.frame(width: 72, height: 80).padding(.bottom, 14)
            Text(name).font(AppFont.text(26, weight: .medium)).foregroundStyle(Color(hex: 0xEEEEE8))
                .overlay(alignment: .trailing) {
                    if open != nil {
                        Image(systemName: "arrow.up.right").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Color(hex: 0x8F9390)).offset(x: 20)
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

/// A province's mark at page size: the image, else its initial in a thin circle (.em-monogram).
private struct PageMark: View {
    let name: String
    let image: UIImage?
    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            Text(String(name.prefix(1)).uppercased()).font(AppFont.text(22)).foregroundStyle(Color(hex: 0xE6E6DF))
                .frame(width: 48, height: 48)
                .overlay(Circle().strokeBorder(.white.opacity(0x22 / 255)))
        }
    }
}

// MARK: - province

private struct ProvincePage: View {
    let province: Province
    let data: EmpireData
    let mark: UIImage?
    let marks: [String: UIImage]
    let busy: Bool
    let actions: EmpireHomeActions
    let close: () -> Void

    private var admin: Bool { data.me.admin }
    private var comingSoon: Bool { !admin && province.isComingSoon }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHero(name: province.name, status: comingSoon ? "COMING SOON" : province.status,
                       blurb: province.blurb, live: province.live,
                       open: province.canOpen ? { actions.open(province) } : nil) {
                PageMark(name: province.name, image: mark)
            }
            if comingSoon {
                Note(text: String(localized: "Coming soon. You’ll be able to open \(province.name) here when it’s available."))
                    .padding(.bottom, 8)
            }
            DetailSection(title: String(localized: "About")) { Paragraph(text: province.detail.about.isEmpty ? province.blurb : province.detail.about) }
            DetailSection(title: String(localized: "Features")) {
                if province.detail.features.isEmpty {
                    Paragraph(text: String(localized: "No features listed yet."))
                } else {
                    VStack(alignment: .leading, spacing: 11) {
                        ForEach(Array(province.detail.features.enumerated()), id: \.offset) { _, feature in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Image(systemName: "checkmark").font(.system(size: 11, weight: .medium)).foregroundStyle(Color(hex: 0x8C9391))
                                Paragraph(text: feature)
                            }
                        }
                    }
                }
            }
            Rectangle().fill(.white.opacity(0x10 / 255)).frame(height: 1).padding(.top, 14)
            ChronicleList(title: String(localized: "What's new"), entries: data.chronicle.filter { $0.project == province.slug }, marks: marks)
                .padding(.top, 23)
            if !admin {
                Button {
                    Task { if await actions.remove(province.slug) { close() } }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: "minus").font(.system(size: 12))
                        Text(busy ? "Removing…" : "Remove from my ring")
                    }
                    .font(AppFont.text(11)).foregroundStyle(Color(hex: 0xB1B7B0))
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0x18 / 255)))
                }
                .buttonStyle(.plain).disabled(busy).opacity(busy ? 0.5 : 1)
                .padding(.top, 34)
            }
        }
    }
}

// MARK: - idea

private struct IdeaPage: View {
    let idea: Idea
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            DetailHero(name: idea.title, status: "PLANNED") {
                Image(systemName: "square.stack.3d.up").font(.system(size: 30, weight: .light)).foregroundStyle(Color(hex: 0xBCC0BD))
            }
            DetailSection(title: String(localized: "About")) { Paragraph(text: idea.note) }
        }
    }
}

// MARK: - add

private struct AddPage: View {
    let addable: [Province]
    let marks: [String: UIImage]
    let busy: Bool
    let actions: EmpireHomeActions
    let close: () -> Void

    var body: some View {
        if addable.isEmpty {
            EmptyState(symbol: "checkmark", title: String(localized: "Your ring is up to date."),
                       note: String(localized: "No other provinces are available to add."))
        } else {
            VStack(spacing: 14) {
                ForEach(addable) { province in
                    VStack(alignment: .leading, spacing: 22) {
                        HStack(spacing: 15) {
                            PageMark(name: province.name, image: marks[province.slug]).frame(width: 48, height: 54)
                            VStack(alignment: .leading, spacing: 8) {
                                Text(province.name).font(AppFont.text(18, weight: .medium)).foregroundStyle(Color(hex: 0xE4E9DF))
                                if province.isComingSoon { StatusWord(text: EmpireStyle.statusWord("COMING SOON")) }
                            }
                        }
                        Button {
                            Task { if await actions.add(province.slug) { close() } }
                        } label: {
                            HStack(spacing: 8) { Image(systemName: "plus").font(.system(size: 12)); Text(busy ? "Adding…" : "Add to my ring") }
                        }
                        .buttonStyle(HubButtonStyle(kind: .primary)).disabled(busy)
                    }
                    .hubCard()
                }
            }
        }
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
                Text("Loading pending accounts…").font(AppFont.text(12)).foregroundStyle(Color(hex: 0x9B9F9D)).padding(.vertical, 12)
            } else if status.approvals.isEmpty && status.approvalsError != nil {
                Text("Pending accounts could not be loaded.").font(AppFont.text(12)).foregroundStyle(Color(hex: 0x9B9F9D))
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
                Text("Updating account…").font(AppFont.text(12)).foregroundStyle(Color(hex: 0x9B9F9D)).padding(.top, 14)
            }
        }
    }

    private func group(_ title: Text, _ accounts: [PendingAccount]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                title.font(AppFont.text(13, weight: .medium)).foregroundStyle(Sheet.heading)
                Spacer()
                Text(String(format: "%02d", accounts.count)).font(AppFont.number(11, weight: .regular))
                    .foregroundStyle(Color(hex: 0x858A8A))
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
                    .font(AppFont.text(14)).foregroundStyle(Color(hex: 0xC3C9C1))
                    .frame(width: 38, height: 38)
                    .background(.white.opacity(0x06 / 255), in: .circle)
                    .overlay(Circle().strokeBorder(.white.opacity(0x17 / 255)))
                VStack(alignment: .leading, spacing: 5) {
                    Text(name).font(AppFont.text(15, weight: .medium)).foregroundStyle(Color(hex: 0xE0E4DC))
                    Text(account.email).font(AppFont.text(11)).foregroundStyle(Color(hex: 0x969E97))
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                if !account.requested.isEmpty {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("Asks for").font(AppFont.text(10)).foregroundStyle(Color(hex: 0x879089))
                        Text(verbatim: account.requestedApps).font(AppFont.text(12, weight: .medium))
                            .foregroundStyle(Color(hex: 0xC3C9C1))
                    }
                }
                if !account.approved {
                    HStack(spacing: 12) {
                        Text("Signed up").font(AppFont.text(10))
                        Text(String(account.created.prefix(10))).font(AppFont.number(9, weight: .regular))
                    }
                    .foregroundStyle(Color(hex: 0x879089))
                }
            }
            .padding(.vertical, 20)
            if declining == account.id {
                (account.approved
                    ? Text("Decline \(who)'s request? The account stays; only the request is cleared.")
                    : Text("Decline \(who)? This deletes their pending sign-up."))
                    .font(AppFont.text(12)).lineSpacing(5).foregroundStyle(Color(hex: 0xC6B1AB)).padding(.bottom, 14)
                HStack(spacing: 10) {
                    Button(account.approved ? "Keep request" : "Keep account") { declining = nil }
                        .buttonStyle(HubButtonStyle(kind: .secondary))
                    Button("Confirm decline") {
                        Task { if await actions.decide(account.id, false) { declining = nil } }
                    }
                    .buttonStyle(HubButtonStyle(kind: .danger))
                }
                .disabled(status.deciding)
            } else {
                HStack(spacing: 10) {
                    Button { Task { _ = await actions.decide(account.id, true) } } label: {
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
            Image(systemName: symbol).font(.system(size: 24, weight: .light)).foregroundStyle(Color(hex: 0xA0A9A1))
            Text(title).font(AppFont.text(15, weight: .medium)).foregroundStyle(Color(hex: 0xC9CFC5))
            if let note { Text(note).font(AppFont.text(12)).foregroundStyle(Color(hex: 0x969F96)) }
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.top, 25).padding(.bottom, 30)
    }
}

private extension View {
    /// .em-account / .em-catalog-card
    func hubCard() -> some View {
        padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                let shape = RoundedRectangle(cornerRadius: 17, style: .continuous)
                ZStack {
                    shape.fill(Color(hex: 0x111417))
                    shape.fill(LinearGradient(colors: [.white.opacity(0x06 / 255), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 17, style: .continuous).strokeBorder(Sheet.cardStroke))
    }
}
