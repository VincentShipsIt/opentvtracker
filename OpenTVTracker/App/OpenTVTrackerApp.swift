import CloudKit
import SwiftUI
import UIKit
import UserNotifications

struct PartnerShareLocation: Sendable {
    let zoneName: String
    let ownerName: String
}

@MainActor
final class OpenTVAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    private static var appModel: AppModel?

    static func attach(model: AppModel) {
        appModel = model
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        application.registerForRemoteNotifications()
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

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        guard CKNotification(fromRemoteNotificationDictionary: userInfo) != nil else {
            completionHandler(.noData)
            return
        }

        Task { @MainActor in
            let model = Self.appModel ?? AppModel()
            Self.appModel = model
            await model.loadPersistedState()
            guard model.sharedSpace.isCloudSharingEnabled else {
                completionHandler(.noData)
                return
            }
            let result = await model.startCloudSyncIfNeeded()
            await model.flushPendingPersistence()
            await model.flushPendingReminders()
            switch result {
            case .newData:
                completionHandler(.newData)
            case .noData:
                completionHandler(.noData)
            case .failed:
                completionHandler(.failed)
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

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-ui-testing-bulk-watch") {
            let initialModel = AppModel(store: MemoryLibraryStore(), seed: .bulkWatchUITest)
            _model = State(initialValue: initialModel)
            OpenTVAppDelegate.attach(model: initialModel)
        } else {
            let initialModel = AppModel()
            _model = State(initialValue: initialModel)
            OpenTVAppDelegate.attach(model: initialModel)
        }
        #else
        let initialModel = AppModel()
        _model = State(initialValue: initialModel)
        OpenTVAppDelegate.attach(model: initialModel)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(model)
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
                    guard phase == .active, model.hasLoaded else { return }
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
