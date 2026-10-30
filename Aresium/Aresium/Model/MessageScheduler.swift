import Foundation
import UserNotifications
import os

nonisolated protocol MessageNotificationCenter: Sendable {
    func authorization() async -> MessageAuthorization
    func requestPermission() async throws -> Bool
    func pendingIdentifiers() async -> [String]
    func deliveredIdentifiers() async -> [String]
    func removePending(_ identifiers: [String]) async
    func removeDelivered(_ identifiers: [String]) async
    func add(_ message: PlannedMessage, calendar: Calendar) async throws
}

/// Aresium's local notifications only. No badge, device token, push registration or server request.
actor LocalMessageCenter: MessageNotificationCenter {
    static let permissionOptions: UNAuthorizationOptions = [.alert, .sound]

    func authorization() async -> MessageAuthorization {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .authorized, .provisional, .ephemeral: .allowed
        default: .denied
        }
    }

    func requestPermission() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: Self.permissionOptions)
    }

    func pendingIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
    }

    func deliveredIdentifiers() async -> [String] {
        await UNUserNotificationCenter.current().deliveredNotifications().map { $0.request.identifier }
    }

    func removePending(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    func removeDelivered(_ identifiers: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
    }

    func add(_ message: PlannedMessage, calendar: Calendar) async throws {
        let content = UNMutableNotificationContent()
        content.title = message.title
        content.body = message.body
        content.sound = .default
        content.userInfo = ["url": message.url.absoluteString]
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: message.date)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: message.identifier, content: content, trigger: trigger))
    }
}

/// One worker per model, called through its serial queue so an old build never overtakes an off/delete/lock change.
actor MessageScheduler {
    let center: any MessageNotificationCenter
    private let now: @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar
    private var progress: MessageProgress

    init(center: any MessageNotificationCenter, now: @escaping @Sendable () -> Date,
         calendar: @escaping @Sendable () -> Calendar, progress: MessageProgress = MessageProgress()) {
        self.center = center
        self.now = now
        self.calendar = calendar
        self.progress = progress
    }

    func update(preferences: MessagePreferences, history: MessageHistory, context: MessageContext,
                dashboard: Dashboard?, ledger: PhoneLedger?, accounts: [String: Set<String>]? = nil,
                askPermission: Bool, clearDelivered: Bool, resetProgress: Bool = false) async throws
        -> (authorization: MessageAuthorization, progress: MessageProgress) {
        let anchor = history.lastImport ?? history.reminderStarted
        if resetProgress || progress.anchor != anchor { progress = MessageProgress(anchor: anchor) }
        let now = now()
        for (slot, date) in progress.scheduled where date <= now { progress.consumed = max(progress.consumed, slot) }
        progress.scheduled = [:]
        var authorization = await center.authorization()
        if askPermission, preferences.enabled, context.permitsMessages, authorization == .notAsked {
            _ = try await center.requestPermission()
            authorization = await center.authorization()
        }
        await center.removePending(await center.pendingIdentifiers().filter(MessagePlan.owns))
        if clearDelivered || !preferences.enabled || !context.permitsMessages || authorization != .allowed {
            await center.removeDelivered(await center.deliveredIdentifiers().filter(MessagePlan.owns))
        }
        guard authorization == .allowed, preferences.enabled, context.permitsMessages else { return (authorization, progress) }
        let membership: [String: Set<String>]
        if let accounts { membership = accounts }
        else if let ledger { membership = try await ledger.messageAccountsByMonth() }
        else { membership = [:] }
        let calendar = calendar()
        for request in MessagePlan.requests(preferences: preferences, history: history, context: context,
                                            dashboard: dashboard, accountsByMonth: membership, now: now, calendar: calendar,
                                            remindersConsumed: progress.consumed) {
            try await center.add(request, calendar: calendar)
            if request.identifier.hasPrefix("aresium.reminder."),
               let slot = Int(request.identifier.split(separator: ".").last ?? "") {
                progress.scheduled[slot] = request.date
            }
        }
        return (authorization, progress)
    }

    #if DEBUG
    func logPending() async {
        let identifiers = await center.pendingIdentifiers().filter(MessagePlan.owns).sorted()
        Logger(subsystem: "de.ares-empire.aresium", category: "messages")
            .notice("Pending local messages: \(identifiers.joined(separator: ", "), privacy: .public)")
    }
    #endif
}

/// These reductions run on the ledger's executor; its large payment array never crosses to the main actor.
extension PhoneLedger {
    func messageAccountsByMonth() throws -> [String: Set<String>] {
        var result: [String: Set<String>] = [:]
        for payment in try payments() { result[String(payment.bookingDate.prefix(7)), default: []].insert(payment.account) }
        return result
    }

    func messageAccountsForNewPayments(_ ids: Set<String>) throws -> Set<String> {
        Set(try payments().filter { ids.contains($0.id) }.map(\.account))
    }
}
