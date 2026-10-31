import Foundation
import Testing
import Observation
import os
@testable import Aresium

@MainActor
struct SettingsWorkTests {
    @Test func lockAvailabilityIsCachedAndRefreshes() async {
        let authenticator = AvailabilityAuthenticator()
        let lock = AppLock(storage: MemoryLockStorage(), marker: nil, authenticator: authenticator, widget: nil)
        await lock.refreshAvailability()
        #expect(lock.biometry == .faceID && lock.canUseFaceID)
        let reads = authenticator.reads
        for _ in 0..<100 {
            _ = lock.biometry
            _ = lock.canUseFaceID
        }
        #expect(authenticator.reads == reads)
        authenticator.value = LockAvailability(biometry: .touchID, canUseFaceID: false)
        await lock.refreshAvailability()
        #expect(lock.biometry == .touchID && !lock.canUseFaceID)
        #expect(authenticator.reads == reads + 1)
    }

    @Test func deviceAvailabilityRunsOffMain() async {
        let recording = PickerTiming.Recording()
        let value = await PickerTiming.$recording.withValue(recording) {
            PickerTiming.measure("settings.legacyLockAvailability") {
                // The old row asked the biometric type once and availability for its line and disabled state.
                let device = DeviceAuthenticator()
                _ = device.biometry
                _ = device.canEvaluate(.biometricsOrIPhoneCode)
                _ = device.canEvaluate(.biometricsOrIPhoneCode)
            }
            return await DeviceAuthenticator().availability()
        }
        for sample in recording.values {
            print("SETTINGS_WORK \(sample.name) \(sample.kind) \(sample.ms) ms")
        }
        #expect(recording.values.contains { $0.name == "settings.lockAvailability" && $0.kind == "worker" })
        #expect(!recording.values.contains { $0.name == "settings.lockAvailability" && $0.kind == "main" })
        // The published snapshot is the value delivered by the worker, including an unavailable simulator.
        let authenticator = AvailabilityAuthenticator(value: value)
        let lock = AppLock(storage: MemoryLockStorage(), marker: nil, authenticator: authenticator, widget: nil)
        await lock.refreshAvailability()
        #expect(lock.availability == value)
    }

    @Test func reminderEligibilityDoesNotObserveUnrelatedSettings() async {
        let suite = "settings-work-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let messages = AresiumMessages(defaults: defaults, center: FakeMessageCenter())
        messages.setContext(MessageContext(phone: true))
        await messages.idle()
        let changes = OSAllocatedUnfairLock(initialState: 0)
        func observe() {
            withObservationTracking { _ = messages.shouldOfferReminder } onChange: {
                changes.withLock { $0 += 1 }
            }
        }
        observe()
        messages.refresh()
        var preferences = messages.preferences
        preferences.importReminder.toggle()
        preferences.monthReview.toggle()
        messages.setPreferences(preferences)
        await messages.idle()
        #expect(changes.withLock { $0 } == 0)
        messages.recordImport(accounts: ["fictional-account"], addedPayments: 1)
        #expect(messages.shouldOfferReminder)
        #expect(changes.withLock { $0 } == 1)
        observe()
        messages.setEnabled(true)
        #expect(!messages.shouldOfferReminder)
        #expect(changes.withLock { $0 } == 2)
        observe()
        messages.setEnabled(false)
        #expect(messages.shouldOfferReminder)
        #expect(changes.withLock { $0 } == 3)
        observe()
        messages.finishReminderOffer()
        #expect(!messages.shouldOfferReminder)
        #expect(changes.withLock { $0 } == 4)
        await messages.idle()
    }

    @Test(arguments: [1250, 5000]) func sizedSampleHasExactCountAndYear(size: Int) async throws {
        let phone = try await PhoneCountingTests.backend()
        _ = try await phone.importFiles([PhoneSample.sizedFile(size: size)], auth: BackendAuth(token: nil))
        #expect(phone.summary.payments == size)
        let payments = try await phone.ledger.payments()
        #expect(Set(payments.map { String($0.bookingDate.prefix(7)) }).count >= 12)
    }
}

@MainActor
private final class AvailabilityAuthenticator: LockAuthenticator {
    var value: LockAvailability
    var reads = 0
    init(value: LockAvailability = LockAvailability(biometry: .faceID, canUseFaceID: true)) { self.value = value }
    var biometry: Biometry { value.biometry }
    func canEvaluate(_ policy: LockPolicy) -> Bool { value.canUseFaceID }
    func authenticate(_ policy: LockPolicy, reason: String) async -> LockAuthResult { .cancelled }
    func availability() async -> LockAvailability { reads += 1; return value }
}
