import XCTest
@testable import OpenTVTracker

@MainActor
final class ReminderPermissionFlowTests: XCTestCase {
    func testOrdinaryTrackingChangesNeverRequestNotificationPermission() async {
        let scheduler = ReminderSchedulerSpy()
        let model = AppModel(
            store: MemoryLibraryStore(),
            reminderScheduler: scheduler,
            seed: .sample
        )

        model.markNextWatched("severance")
        await model.flushPendingPersistence()

        let requestCount = await scheduler.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testExplicitEnableRequestsPermissionAndPersistsSettings() async throws {
        let scheduler = ReminderSchedulerSpy()
        let store = MemoryLibraryStore()
        let model = AppModel(
            store: store,
            reminderScheduler: scheduler,
            seed: .sample
        )

        await model.enableReminder(for: "severance", leadTime: .fifteenMinutes)
        await model.flushPendingPersistence()
        await model.flushPendingReminders()

        let requestCount = await scheduler.requestCount()
        let storedSnapshot = try await store.load()
        let saved = try XCTUnwrap(storedSnapshot)
        XCTAssertEqual(requestCount, 1)
        XCTAssertTrue(model.isReminderEnabled(for: "severance"))
        XCTAssertFalse(model.isReminderEnabled(for: "fallout"))
        XCTAssertEqual(model.reminderLeadTime(for: "severance"), .fifteenMinutes)
        XCTAssertTrue(saved.reminderSettings?.isEnabled == true)
    }

    func testGlobalTogglePreservesPerTitleOnlyPreference() async {
        let scheduler = ReminderSchedulerSpy()
        let model = AppModel(
            store: MemoryLibraryStore(),
            reminderScheduler: scheduler,
            seed: .sample
        )
        model.reminderSettings.isEnabled = true
        model.reminderSettings.automaticallyRemindTrackedTitles = false
        model.reminderSettings.enabledTitleIDs = ["severance"]

        await model.setRemindersEnabled(false)
        await model.setRemindersEnabled(true)

        XCTAssertFalse(model.reminderSettings.automaticallyRemindTrackedTitles)
        XCTAssertEqual(model.reminderSettings.enabledTitleIDs, ["severance"])
    }

    func testDisablingTitlePreservesItsLeadTime() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        model.reminderSettings.isEnabled = true
        model.reminderSettings.enabledTitleIDs = ["severance"]
        model.reminderSettings.titleLeadTimes["severance"] = .fifteenMinutes

        model.disableReminder(for: "severance")

        XCTAssertEqual(model.reminderLeadTime(for: "severance"), .fifteenMinutes)
    }

    func testLegacyImportPreservesCurrentReminderSettings() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)
        model.reminderSettings.isEnabled = true
        model.reminderSettings.enabledTitleIDs = ["severance"]
        model.reminderSettings.titleLeadTimes["severance"] = .oneDay
        var legacySnapshot = LibrarySnapshot.sample
        legacySnapshot.reminderSettings = nil

        model.replaceLibrary(with: legacySnapshot)

        XCTAssertTrue(model.reminderSettings.isEnabled)
        XCTAssertEqual(model.reminderSettings.enabledTitleIDs, ["severance"])
        XCTAssertEqual(model.reminderLeadTime(for: "severance"), .oneDay)
    }

    func testImportReconcilesDisabledReminderSettings() async {
        let scheduler = ReminderSchedulerSpy()
        let model = AppModel(
            store: MemoryLibraryStore(),
            reminderScheduler: scheduler,
            seed: .sample
        )
        model.reminderSettings.isEnabled = true
        var importedSnapshot = LibrarySnapshot.sample
        importedSnapshot.reminderSettings = ReminderSettings()

        model.replaceLibrary(with: importedSnapshot)
        await model.flushPendingReminders()

        let reconciledSettings = await scheduler.latestSettings()
        XCTAssertEqual(reconciledSettings?.isEnabled, false)
    }
}

private actor ReminderSchedulerSpy: ReminderScheduling {
    private var authorizationRequests = 0
    private var authorization = ReminderAuthorization.notDetermined
    private var reconciledSettings: ReminderSettings?

    func requestAuthorization() async -> ReminderAuthorization {
        authorizationRequests += 1
        authorization = .authorized
        return authorization
    }

    func capability() async -> ReminderCapability {
        ReminderCapability(authorization: authorization, backgroundRefreshAvailable: true)
    }

    func reconcile(
        titles _: [MediaTitle],
        selectedProviderIDs _: Set<StreamingProvider.ID>,
        settings: ReminderSettings,
        now _: Date
    ) async throws {
        reconciledSettings = settings
    }

    func requestCount() -> Int {
        authorizationRequests
    }

    func latestSettings() -> ReminderSettings? {
        reconciledSettings
    }
}
