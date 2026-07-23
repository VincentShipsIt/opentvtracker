import CloudKit
import SwiftUI
import UIKit
import UserNotifications

struct PartnerShareLocation: Sendable {
    let zoneName: String
    let ownerName: String
}

final class OpenTVAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    func application(
        _ application: UIApplication,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task {
            do {
                guard let rootRecordID = cloudKitShareMetadata.hierarchicalRootRecordID else {
                    throw PartnerSharingError.shareUnavailable
                }
                try await CloudKitPartnerSharingService().accept(metadata: cloudKitShareMetadata)
                let zoneID = rootRecordID.zoneID
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .openTVPartnerShareAccepted,
                        object: PartnerShareLocation(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName)
                    )
                }
            } catch {
                await MainActor.run {
                    NotificationCenter.default.post(
                        name: .openTVPartnerShareAcceptanceFailed,
                        object: error.localizedDescription
                    )
                }
            }
        }
    }
}

extension Notification.Name {
    static let openTVPartnerShareAccepted = Notification.Name("OpenTVPartnerShareAccepted")
    static let openTVPartnerShareAcceptanceFailed = Notification.Name("OpenTVPartnerShareAcceptanceFailed")
}

@main
struct OpenTVTrackerApp: App {
    @UIApplicationDelegateAdaptor(OpenTVAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AppModel
    private let partnerSharingService: any PartnerSharingProviding
    private let allowsRemoteArtwork: Bool
    private let forcesTrailerPlaybackFailure: Bool

    init() {
        #if DEBUG
        let processInfo = ProcessInfo.processInfo
        let isBulkWatchUITest = processInfo.arguments.contains("-ui-testing-bulk-watch")
        let isFirstRunUITest = processInfo.arguments.contains("-ui-testing-first-run")
        let isCoreJourneyUITest = processInfo.arguments.contains("-ui-testing-core-journeys")
        let uiTestSeed: LibrarySnapshot? = if isBulkWatchUITest {
            .bulkWatchUITest
        } else if isFirstRunUITest {
            .firstRunUITest
        } else if isCoreJourneyUITest {
            .coreJourneyUITest
        } else {
            nil
        }

        if let uiTestSeed {
            _model = State(initialValue: AppModel(
                store: MemoryLibraryStore(),
                recommendationService: DeterministicRecommendationService(),
                sharedConversationNotifier: NoopSharedConversationNotifier(),
                reminderScheduler: NoopReminderScheduler(),
                catalogService: LocalCatalogService(titles: uiTestSeed.titles),
                traktService: UnconfiguredTraktSyncService(),
                seed: uiTestSeed
            ))
        } else {
            _model = State(initialValue: AppModel())
        }
        partnerSharingService = uiTestSeed != nil
            || processInfo.environment["XCTestConfigurationFilePath"] != nil
            ? PreviewPartnerSharingService()
            : CloudKitPartnerSharingService()
        allowsRemoteArtwork = uiTestSeed == nil
        forcesTrailerPlaybackFailure = isCoreJourneyUITest
        #else
        _model = State(initialValue: AppModel())
        partnerSharingService = CloudKitPartnerSharingService()
        allowsRemoteArtwork = true
        forcesTrailerPlaybackFailure = false
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView(partnerSharingService: partnerSharingService)
                .environment(model)
                .environment(\.allowsRemoteArtwork, allowsRemoteArtwork)
                .environment(\.forcesTrailerPlaybackFailure, forcesTrailerPlaybackFailure)
                .task {
                    await model.load()
                    await model.startCloudSyncIfNeeded()
                }
                .onReceive(NotificationCenter.default.publisher(for: .openTVPartnerShareAccepted)) { notification in
                    if let location = notification.object as? PartnerShareLocation {
                        model.acceptPartnerShare(location)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .openTVPartnerShareAcceptanceFailed)) { notification in
                    model.persistenceError = notification.object as? String
                }
                .onReceive(NotificationCenter.default.publisher(for: .openTVCloudSharedStateChanged)) { _ in
                    Task { await model.applyLatestCloudSharedState() }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task {
                        await model.startCloudSyncIfNeeded()
                        await model.refreshReminderCapability()
                        await model.refreshReminders()
                        model.publishWidgetSnapshot()
                    }
                }
        }
    }
}
