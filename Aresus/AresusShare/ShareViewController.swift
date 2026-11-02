import SwiftUI
import UIKit

/// The extension reads providers into group-owned files, restores the shared login, and hosts the same send flow.
/// Completing the request only happens after Send has durably queued the files and submitted eligible uploads to iOS.
final class ShareViewController: UIViewController {
    private var model: ShareModel?

    isolated deinit { model?.temporary.clear() }

    override func viewDidLoad() {
        super.viewDidLoad()
        AppFont.register()
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
    let session: EmpireSession
    let temporary: SendTemporaryFiles
    let items: [NSExtensionItem]
    var drops: DropsStore?
    var answer: ShareItems.Answer?
    var ready = false
    private var loaded = false

    init(items: [NSExtensionItem]) {
        self.items = items
        temporary = SendTemporaryFiles(base: (DropContainer.url ?? URL.temporaryDirectory)
            .appending(path: "ShareDrafts/\(UUID())", directoryHint: .isDirectory))
        #if DEBUG
        if UserDefaults(suiteName: DropContainer.appGroup)?.bool(forKey: "aresus.drops.preview") == true {
            session = SampleAccount.session(app: .aresus, start: .signedIn).session
            return
        }
        #endif
        session = EmpireSession(app: .aresus, sharedDefaults: EmpireShared.defaults)
    }

    func load() async {
        guard !loaded else { return }
        loaded = true
        await session.restore()
        guard session.isSignedIn else { ready = true; return }
        #if DEBUG
        let preview = UserDefaults(suiteName: DropContainer.appGroup)?.bool(forKey: "aresus.drops.preview") == true
        drops = DropsStore(session: session, samples: preview ? SharePreview() : nil)
        #else
        drops = DropsStore(session: session)
        #endif
        answer = await ShareItems(temporary: temporary).read(items)
        ready = true
    }
}

private struct ShareScreen: View {
    let model: ShareModel
    let sent: () -> Void
    let cancel: () -> Void

    var body: some View {
        Group {
            if !model.ready { ProgressView() }
            else if !model.session.isSignedIn {
                VStack(spacing: 16) {
                    Text("Log in to Aresus on this iPhone first.", tableName: "AresusDrops")
                    Button(action: cancel) { Text("Cancel", tableName: "Shared") }
                }
            } else if let drops = model.drops, let answer = model.answer {
                VStack(spacing: 8) {
                    if answer.unreadable > 0 {
                        Text("\(answer.unreadable) items could not be read.", tableName: "AresusDrops")
                    }
                    SendSheet(drops: drops, files: answer.files, sharing: true, temporary: model.temporary,
                              sent: sent, cancelled: cancel)
                }
            }
        }
        .foregroundStyle(Ink.primary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.background)
        .environment(\.locale, AppLanguage.current.locale)
        .task { await model.load() }
    }
}

#if DEBUG
/// Made-up folder data for checking the extension from Photos/Files without a Keychain login or network.
private struct SharePreview: DropSamples {
    func folders() throws -> FolderList {
        FolderList(updated: .now, documents: ["Examples"], downloads: [], fallback: "Sort later", fallbackCount: 0)
    }
    func drops() throws -> [Drop] { [] }
}
#endif
