import SwiftUI
import UIKit

/// The extension reads providers into group-owned files, restores the shared login, and hosts the same send flow.
/// Completing the request only happens after Send has durably queued the files and submitted eligible uploads to iOS.
///
/// Its look (brief 100) is the send sheet's: every state stands in the sheet's own frame (the title "Send to MacBook" and
/// the close button on Aresus's wall), so the screen keeps its place from the first frame to Send. It speaks the app's
/// language and shows the app's appearance, which the app publishes into the App Groups as it does for its widget:
/// iOS starts an extension in the iPhone's language and look.
final class ShareViewController: UIViewController {
    private var model: ShareModel?

    isolated deinit { model?.temporary.clear() }

    override func viewDidLoad() {
        super.viewDidLoad()
        AppFont.register()
        // Before any text is looked up: the app's choice, else the iPhone's language (`WidgetLanguage`).
        WidgetLanguage.aresus.follow()
        // The app's light or dark; "like the iPhone" leaves the look iOS gives the share sheet.
        overrideUserInterfaceStyle = ExtensionAppearance.aresus.choice.interfaceStyle
        let model = ShareModel(items: extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? [])
        self.model = model
        let host = UIHostingController(rootView: ShareScreen(model: model, sent: { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }, cancel: { [weak self] in
            model.temporary.clear()
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

@MainActor @Observable
private final class ShareModel {
    /// What the share sheet shows: the shared items being read (and the login restored), no login on this iPhone,
    /// nothing readable, or the send sheet.
    enum Phase: Equatable { case loading, loggedOut, unreadable, ready }

    let session: EmpireSession
    let temporary: SendTemporaryFiles
    let items: [NSExtensionItem]
    /// The shared items' kinds as their providers name them, for the loading row (before anything is read).
    let kinds: [DropFileKind]
    private(set) var phase = Phase.loading
    private(set) var drops: DropsStore?
    private(set) var answer: ShareItems.Answer?
    private var loaded = false

    init(items: [NSExtensionItem]) {
        self.items = items
        kinds = items.flatMap { $0.attachments ?? [] }.prefix(20).map { DropFileKind(types: $0.registeredTypeIdentifiers) }
        temporary = SendTemporaryFiles(base: (DropContainer.url ?? URL.temporaryDirectory)
            .appending(path: "ShareDrafts/\(UUID())", directoryHint: .isDirectory))
        #if DEBUG
        if SharePreview.isOn {
            session = SampleAccount.session(app: .aresus, start: SharePreview.state == "loggedOut" ? .login : .signedIn).session
            return
        }
        #endif
        session = EmpireSession(app: .aresus, sharedDefaults: EmpireShared.defaults)
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        #if DEBUG
        if SharePreview.isOn, SharePreview.state == "loading" { return }      // screenshots of the loading row
        #endif
        await session.restore()
        guard session.isSignedIn else { phase = .loggedOut; return }
        #if DEBUG
        drops = DropsStore(session: session, samples: SharePreview.isOn ? SharePreview() : nil)
        #else
        drops = DropsStore(session: session)
        #endif
        var answer = await ShareItems(temporary: temporary).read(items)
        #if DEBUG
        if SharePreview.isOn, SharePreview.state == "unreadable" { answer.unreadable += 2 }
        #endif
        self.answer = answer
        phase = answer.files.isEmpty ? .unreadable : .ready
    }
}

private struct ShareScreen: View {
    let model: ShareModel
    let sent: () -> Void
    let cancel: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if model.phase == .ready, let drops = model.drops, let answer = model.answer {
                SendSheet(drops: drops, files: answer.files, unreadable: answer.unreadable, sharing: true,
                          temporary: model.temporary, sent: sent, cancelled: cancel)
            } else {
                ShareFrame(cancel: cancel) {
                    switch model.phase {
                    case .loading, .ready: ShareLoading(kinds: model.kinds)
                    case .loggedOut:
                        CalmMessage(text: String(localized: LocalizedStringResource("Log in to Aresus on this iPhone first.",
                                                                                     table: "AresusDrops", locale: .appLanguage)),
                                    actionTitle: String(localized: LocalizedStringResource("Cancel", table: "Shared", locale: .appLanguage)),
                                    action: cancel)
                            .frame(maxHeight: .infinity).padding(.bottom, 90)
                    case .unreadable:
                        CalmMessage(text: SendPickText.unreadable(model.answer?.unreadable ?? 0),
                                    actionTitle: String(localized: LocalizedStringResource("Cancel", table: "Shared", locale: .appLanguage)),
                                    action: cancel)
                            .frame(maxHeight: .infinity).padding(.bottom, 90)
                    }
                }
            }
        }
        .transition(.opacity)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: model.phase)
        .foregroundStyle(Ink.primary)
        .environment(\.locale, AppLanguage.current.locale)
        .task { await model.load() }
    }
}

/// The share sheet's frame before the send sheet is there: the send sheet's own bar (its title and the close button,
/// which cancels the share) over Aresus's wall, so nothing moves when the sheet takes over.
private struct ShareFrame<Content: View>: View {
    let cancel: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background { ProvinceWall(accent: .aresus) }
                .navigationTitle(Text("Send to MacBook", tableName: "AresusDrops"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) { Button(role: .close, action: cancel) }
                }
        }
        .tint(Ink.primary)
    }
}

/// While the shared items are copied and the login restored: the send sheet's picked row as it will stand, one quiet
/// tile per item (a photo's square, a file's wider card, by the type its provider names) under the heading it will
/// have, and one small spinner with "Preparing …". The tiles are filled in place when the sheet takes over.
private struct ShareLoading: View {
    let kinds: [DropFileKind]
    private let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !kinds.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    SectionHeading(text: SendPickText.heading(kinds.map(\.source)))
                    if kinds.count > 1 {
                        Text(verbatim: "\(kinds.count)").font(AppFont.number(11, weight: .regular)).foregroundStyle(Ink.muted)
                    }
                }
                .padding(.leading, 4)
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(kinds.enumerated()), id: \.offset) { _, kind in tile(kind) }
                    }
                    .padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
                .scrollClipDisabled()
                .padding(.horizontal, -18)
                .padding(.top, 12)
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small).tint(Ink.muted)
                Text(SendPickText.preparing()).font(AppFont.text(12.5)).foregroundStyle(Ink.muted)
            }
            .padding(.leading, 4).padding(.top, kinds.isEmpty ? 0 : 16)
        }
        .padding(.horizontal, 18).padding(.top, 14)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(SendPickText.preparing()))
    }

    /// The tile an item will have on the picked row, empty: a photo's square with its symbol, a file's card.
    @ViewBuilder private func tile(_ kind: DropFileKind) -> some View {
        if kind.source == .photo {
            Image(systemName: kind.symbol).font(.system(size: 20, weight: .regular)).foregroundStyle(Ink.muted)
                .frame(width: 88, height: 88)
                .background(Ink.card2, in: shape)
                .overlay(shape.strokeBorder(Ink.line))
        } else {
            Image(systemName: kind.symbol).font(.system(size: 19, weight: .regular)).foregroundStyle(Ink.muted)
                .padding(12)
                .frame(width: 136, height: 88, alignment: .topLeading)
                .glassCard(radius: 14)
        }
    }
}

#if DEBUG
/// Made-up folder data for checking the extension from Photos/Files without a Keychain login or network. The app turns
/// it on (`-sampleData -sampleShareExtension`, with `-sampleShareState loading|loggedOut|unreadable` for the other
/// screens) by writing these keys into the group.
private struct SharePreview: DropSamples {
    static var defaults: UserDefaults? { UserDefaults(suiteName: DropContainer.appGroup) }
    static var isOn: Bool { defaults?.bool(forKey: "aresus.drops.preview") == true }
    static var state: String? { defaults?.string(forKey: "aresus.drops.preview.state") }

    func folders() throws -> FolderList {
        // The app's sample names its fallback folder "To sort" too (`Samples/drop-folders.json`).
        FolderList(updated: .now, documents: ["Examples"], downloads: [], fallback: "To sort", fallbackCount: 0)
    }
    func drops() throws -> [Drop] { [] }
}
#endif
