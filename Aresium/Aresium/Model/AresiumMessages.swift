import Foundation
import Observation

/// Settings and offer API for brief 46. Only the live app installs this model; tests inject their own center/defaults.
@MainActor @Observable
final class AresiumMessages {
    static let preferencesKey = "aresium.messages.preferences"
    static let historyKey = "aresium.messages.history"
    static let progressKey = "aresium.messages.progress"
    /// Survives the in-app language restart, including its serial queue.
    static let live = AresiumMessages(defaults: .standard, center: LocalMessageCenter())

    private(set) var preferences: MessagePreferences
    private(set) var authorization = MessageAuthorization.notAsked
    private(set) var error: String?
    /// The dashboard observes only eligibility, not the page's individual preferences or scheduling context.
    private(set) var shouldOfferReminder = false
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let scheduler: MessageScheduler
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var history: MessageHistory
    @ObservationIgnored private var context = MessageContext()
    @ObservationIgnored private var dashboard: Dashboard?
    @ObservationIgnored private var ledger: PhoneLedger?
    @ObservationIgnored private var queue: Task<Void, Never>?
    @ObservationIgnored private var dataGeneration = 0

    init(defaults: UserDefaults, center: any MessageNotificationCenter,
         now: @escaping @Sendable () -> Date = Date.init,
         calendar: @escaping @Sendable () -> Calendar = { Calendar.current }) {
        self.defaults = defaults
        self.now = now
        let progress = defaults.data(forKey: Self.progressKey)
            .flatMap { try? JSONDecoder().decode(MessageProgress.self, from: $0) } ?? MessageProgress()
        scheduler = MessageScheduler(center: center, now: now, calendar: calendar, progress: progress)
        preferences = defaults.data(forKey: Self.preferencesKey)
            .flatMap { try? JSONDecoder().decode(MessagePreferences.self, from: $0) } ?? MessagePreferences()
        history = defaults.data(forKey: Self.historyKey)
            .flatMap { try? JSONDecoder().decode(MessageHistory.self, from: $0) } ?? MessageHistory()
    }

    /// Save a page's choice and reschedule. Turning the master switch on requests alert + sound once, if not asked.
    func setPreferences(_ value: MessagePreferences) {
        var value = value
        value.hour = min(23, max(0, value.hour))
        value.minute = min(59, max(0, value.minute))
        let asks = value.enabled && !preferences.enabled
        if value.enabled && value.importReminder && history.reminderStarted == nil {
            history.reminderStarted = now()
        }
        preferences = value
        updateOffer()
        save()
        enqueue(askPermission: asks)
    }

    func setEnabled(_ enabled: Bool) {
        var value = preferences
        value.enabled = enabled
        setPreferences(value)
    }

    /// Called for every successful import's account, also one with no new rows (`PhoneImportResult.accountID`).
    /// An import only moves the reminder / readies the one-time offer when it added payments.
    func recordImport(accounts: Set<String>, addedPayments: Int, at date: Date? = nil) {
        guard context.permitsMessages else { return }
        let date = date ?? now()
        for account in accounts { history.accountImports[account] = date }
        if addedPayments > 0 {
            history.lastImport = date
            if !history.offered && !preferences.enabled { history.offerReady = true }
        }
        updateOffer()
        save()
        enqueue()
    }

    /// The offer's answer (including Not now) consumes it permanently, regardless of the chosen switches.
    func finishReminderOffer() {
        history.offered = true
        history.offerReady = false
        updateOffer()
        save()
    }

    func setContext(_ value: MessageContext) {
        let hidesDelivered = value.locked && !context.locked
        context = value
        updateOffer()
        enqueue(clearDelivered: hidesDelivered)
    }

    func setPhoneMode(_ phone: Bool, ledger: PhoneLedger?) {
        context.phone = phone
        updateOffer()
        self.ledger = ledger
        dashboard = nil
        enqueue(askPermission: preferences.enabled)
    }

    func setTour(_ tour: Bool) { context.tour = tour; updateOffer(); enqueue() }
    func setLocked(_ locked: Bool) {
        let changed = locked != context.locked
        context.locked = locked
        enqueue(clearDelivered: locked && changed)
    }

    /// Every dashboard build and foreground/launch; a language restart uses the same model and the new language.
    func dashboardBuilt(_ dashboard: Dashboard?) {
        self.dashboard = dashboard
        refresh()
    }

    func refresh() { context.language = .current; enqueue() }

    /// Delete all data clears settings, import history, pending and delivered messages before the store is reopened.
    func deleteAll() async {
        dataGeneration += 1
        preferences = MessagePreferences()
        history = MessageHistory()
        updateOffer()
        dashboard = nil
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("aresium.messages.") {
            defaults.removeObject(forKey: key)
        }
        enqueue(clearDelivered: true, resetProgress: true)
        await idle()
    }

    func importFinished(_ results: [ImportFileResult], ledger: PhoneLedger) async {
        guard context.permitsMessages else { return }
        let generation = dataGeneration
        let files = results.compactMap { if case let .phone(value) = $0 { value } else { nil } }
        let ids = Set(files.flatMap(\.newIDs))
        do {
            // Every file read into an account counts as an import of it, also one that brought nothing new.
            let accounts = try await ledger.messageAccountsForNewPayments(ids)
                .union(files.filter { $0.error == nil }.compactMap(\.accountID))
            guard generation == dataGeneration else { return }
            recordImport(accounts: accounts, addedPayments: files.reduce(0) { $0 + $1.added })
        } catch { self.error = error.localizedDescription }
    }

    /// Wait for queued scheduling (tests, and a destructive reset).
    func idle() async { await queue?.value }

    private func save() {
        defaults.set(try? JSONEncoder().encode(preferences), forKey: Self.preferencesKey)
        defaults.set(try? JSONEncoder().encode(history), forKey: Self.historyKey)
    }

    private func updateOffer() {
        let value = context.permitsMessages && !preferences.enabled && history.offerReady && !history.offered
        if shouldOfferReminder != value { shouldOfferReminder = value }
    }

    private func enqueue(askPermission: Bool = false, clearDelivered: Bool = false, resetProgress: Bool = false) {
        let previous = queue
        let preferences = preferences, history = history, context = context, dashboard = dashboard, ledger = ledger
        queue = Task {
            await previous?.value
            do {
                let result = try await scheduler.update(preferences: preferences, history: history, context: context,
                                                            dashboard: dashboard, ledger: ledger,
                                                            askPermission: askPermission, clearDelivered: clearDelivered,
                                                            resetProgress: resetProgress)
                if authorization != result.authorization { authorization = result.authorization }
                if resetProgress { defaults.removeObject(forKey: Self.progressKey) }
                else { defaults.set(try? JSONEncoder().encode(result.progress), forKey: Self.progressKey) }
                if error != nil { error = nil }
            } catch { self.error = error.localizedDescription }
            #if DEBUG
            if LaunchArguments.current.contains("-logMessages") { await scheduler.logPending() }
            #endif
        }
    }
}
