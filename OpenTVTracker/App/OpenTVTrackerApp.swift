import CloudKit
import SwiftUI
import UIKit

struct PartnerShareLocation: Sendable {
    let zoneName: String
    let ownerName: String
}

final class OpenTVAppDelegate: NSObject, UIApplicationDelegate {
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
    @State private var model = AppModel()

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
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active else { return }
                    Task { await model.startCloudSyncIfNeeded() }
                }
        }
    }
}
