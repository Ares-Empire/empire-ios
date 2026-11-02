import SwiftUI
import UIKit

/// Aresus in the share sheet (ares-empire/docs/ARESYNC-DROP.md): the extension's entry point, which hosts SwiftUI.
/// Until the send sheet moves here (briefs 94 and 100) it only says how many items came and closes again.
final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let count = items.reduce(0) { $0 + ($1.attachments?.count ?? 0) }
        let host = UIHostingController(rootView: SharePlaceholder(count: count) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

/// A stand-in until brief 100 builds the real screen.
private struct SharePlaceholder: View {
    let count: Int
    let close: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text(verbatim: "Aresus · \(count)").font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
            Button("Cancel", action: close)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.background)
    }
}
