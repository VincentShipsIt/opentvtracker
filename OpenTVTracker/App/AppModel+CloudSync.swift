import CloudKit
import Foundation

extension AppModel {
    func startCloudSyncIfNeeded() async {
        guard sharedSpace.isCloudSharingEnabled else { return }
        await CloudKitSyncCoordinator.shared.start()
        await applyCachedSharedState()
        await syncSharedState()
    }

    func syncSharedStateSoon() {
        guard sharedSpace.isCloudSharingEnabled else { return }
        Task { await syncSharedState() }
    }

    private func syncSharedState() async {
        guard sharedSpace.isCloudSharingEnabled else { return }
        let context = cloudSyncContext
        do {
            await CloudKitSyncCoordinator.shared.start()
            await applyCachedSharedState()
            guard let payload = try? JSONEncoder.openTV.encode(sharedSpace) else { return }
            try await CloudKitSyncCoordinator.shared.enqueue(
                payload: payload,
                recordType: "PartnerSpaceState",
                stableID: "space-state",
                zoneID: context.zoneID,
                parentStableID: "space-root",
                scope: context.scope
            )
        } catch {
            persistenceError = "Your shared changes are saved locally and will retry with iCloud."
        }
    }

    private func applyCachedSharedState() async {
        let context = cloudSyncContext
        guard context.scope == .sharedDatabase,
              let payload = await CloudKitSyncCoordinator.shared.cachedPayload(
                stableID: "space-state",
                scope: .sharedDatabase
              ),
              var remoteSpace = try? JSONDecoder.openTV.decode(SharedSpace.self, from: payload) else { return }
        remoteSpace.titleIDs = Array(Set(remoteSpace.titleIDs + sharedSpace.titleIDs)).sorted()
        remoteSpace.activity = merging(remoteSpace.activity, sharedSpace.activity)
        remoteSpace.watchEvents = merging(remoteSpace.watchEvents ?? [], sharedSpace.watchEvents ?? [])
        remoteSpace.reactions = merging(remoteSpace.reactions ?? [], sharedSpace.reactions ?? [])
        remoteSpace.notes = merging(remoteSpace.notes ?? [], sharedSpace.notes ?? [])
        remoteSpace.membershipState = .accepted
        remoteSpace.isCloudSharingEnabled = true
        remoteSpace.cloudZoneName = context.zoneID.zoneName
        remoteSpace.cloudOwnerName = context.zoneID.ownerName
        remoteSpace.isCurrentUserShareOwner = false
        sharedSpace = remoteSpace
        persist()
    }

    private func merging<Value: Identifiable>(_ remote: [Value], _ local: [Value]) -> [Value] {
        var seen = Set<Value.ID>()
        return (remote + local).filter { seen.insert($0.id).inserted }
    }

    private var cloudSyncContext: (zoneID: CKRecordZone.ID, scope: CloudDatabaseScope) {
        let defaultZoneID = CloudKitPartnerSharingService.zoneID(for: sharedSpace.id)
        let zoneID = CKRecordZone.ID(
            zoneName: sharedSpace.cloudZoneName ?? defaultZoneID.zoneName,
            ownerName: sharedSpace.cloudOwnerName ?? defaultZoneID.ownerName
        )
        let scope: CloudDatabaseScope = sharedSpace.isCurrentUserShareOwner == false
            ? .sharedDatabase
            : .privateDatabase
        return (zoneID, scope)
    }
}

private extension JSONEncoder {
    static var openTV: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
