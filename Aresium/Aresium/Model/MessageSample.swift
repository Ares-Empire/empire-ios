#if DEBUG
import Foundation

// The phone sample's messages (brief 46, DEBUG only): Settings → Messages and the offer on made-up data, for
// screenshots. A model of brief 45's on defaults of its own (emptied at every launch) and a center that only pretends:
// nothing reaches iOS's notification center and iOS is never asked. Launch arguments, with `-samplePhone`:
// `-sampleMessages on|reminder|review|none` starts with Messages on (both, only one, or none chosen);
// `-sampleNotifications allowed|denied|notAsked` is what the pretend iOS answers (allowed by default);
// `-sampleReminderOffer` lets the sample offer the messages (after a made-up import at launch, and after the sample's
// own imports, such as `-sampleImport`); `-sampleMessagesFail` makes planning fail, so the page shows its failure.

/// iOS's notification center as the sample pretends it: it answers as told and keeps nothing but the identifiers.
actor SampleMessageCenter: MessageNotificationCenter {
    private var status: MessageAuthorization
    private let fails: Bool
    private var pending: [String] = []

    init(status: MessageAuthorization, fails: Bool) {
        self.status = status
        self.fails = fails
    }

    func authorization() async -> MessageAuthorization { status }

    /// The pretend iOS allows when asked (a denied one is never asked again, as on the iPhone).
    func requestPermission() async throws -> Bool {
        if status == .notAsked { status = .allowed }
        return status == .allowed
    }

    func pendingIdentifiers() async -> [String] { pending }
    func deliveredIdentifiers() async -> [String] { [] }
    func removePending(_ identifiers: [String]) async { pending.removeAll { identifiers.contains($0) } }
    func removeDelivered(_ identifiers: [String]) async {}

    func add(_ message: PlannedMessage, calendar: Calendar) async throws {
        if fails { throw NSError(domain: "UNErrorDomain", code: 1) }
        pending.append(message.identifier)
    }
}

extension AresiumMessages {
    /// The sample's model, as the launch arguments ask (above).
    static func sample(arguments: [String] = LaunchArguments.current) -> AresiumMessages {
        let suite = "de.ares-empire.aresium.sample-messages"
        UserDefaults.standard.removePersistentDomain(forName: suite)
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let status: MessageAuthorization = switch LaunchArguments.value("-sampleNotifications") {
        case "denied": .denied
        case "notAsked": .notAsked
        default: .allowed
        }
        let fails = arguments.contains("-sampleMessagesFail")
        let offers = arguments.contains("-sampleReminderOffer")
        let model = AresiumMessages(defaults: defaults, center: SampleMessageCenter(status: status, fails: fails))
        // Timing uses the live observation and scheduling paths too, with the pretend center above.
        // Other samples neither offer nor plan anything unless requested.
        model.setContext(MessageContext(phone: true, sample: !(offers || fails || arguments.contains("-settingsTimings"))))
        if let start = LaunchArguments.value("-sampleMessages") {
            var preferences = model.preferences
            preferences.enabled = true
            preferences.importReminder = start == "on" || start == "reminder"
            preferences.monthReview = start == "on" || start == "review"
            model.setPreferences(preferences)
        }
        if offers { model.recordImport(accounts: ["sample-account"], addedPayments: 42) }
        return model
    }
}

extension DashboardStore {
    /// The phone sample's messages (`AresiumMessages.sample`), so its Settings show Messages as the iPhone's do.
    func installSampleMessages() {
        guard messages == nil else { return }
        let model = AresiumMessages.sample()
        messages = model
        model.setPhoneMode(true, ledger: phone?.ledger)
        model.dashboardBuilt(dashboard)
    }
}
#endif
