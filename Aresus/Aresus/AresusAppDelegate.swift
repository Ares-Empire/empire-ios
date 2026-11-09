import UIKit

/// Push behavior is inherited unchanged. Only Aresus reconnects the app's and the share extension's upload sessions.
final class AresusAppDelegate: PushAppDelegate {
    private var deliveries: [String: DropOutbox] = [:]

    func application(_ application: UIApplication, handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard DropContainer.ownsSession(identifier) else { completionHandler(); return }
        let live = DropBackgroundUploads.live()
        let uploads = identifier == live.identifier ? live : DropBackgroundUploads.driver(identifier: identifier)
        let outbox: DropOutbox
        if let existing = uploads.outbox { outbox = existing }
        else {
            let session = EmpireSession(app: .aresus, sharedDefaults: EmpireShared.defaults)
            outbox = DropOutbox(session: session, uploads: uploads)
        }
        deliveries[identifier] = outbox
        let restore = Task { await outbox.restoreForEvents() }
        uploads.completed = { [outbox] id, result, token in
            await restore.value
            await outbox.finished(id, result: result, token: token)
        }
        uploads.finishedEvents = { [weak self, weak uploads] in
            completionHandler()
            self?.deliveries.removeValue(forKey: identifier)
            // A share invocation has a unique id; release it after its event batch. If checksum handling or a 404
            // restart submitted another task, finishTasksAndInvalidate keeps its delegate and outbox until that task
            // has finished too.
            if identifier != DropContainer.appUploadSession { uploads?.invalidate() }
        }
    }
}
