import CloudKit
import Foundation

extension AppModel {
    func startCloudSyncIfNeeded() async {
        guard sharedSpace.isCloudSharingEnabled else { return }
        await CloudKitSyncCoordinator.shared.start()
        await applyCachedSharedState()
        await syncSharedState()
    }

    func applyLatestCloudSharedState() async {
        guard sharedSpace.isCloudSharingEnabled else { return }
        await applyCachedSharedState()
    }

    func syncSharedStateSoon() {
        guard sharedSpace.isCloudSharingEnabled else { return }
        Task { await syncSharedState() }
    }

    func flushSharedState() async {
        await syncSharedState()
    }

    private func syncSharedState() async {
        guard sharedSpace.isCloudSharingEnabled else { return }
        let context = cloudSyncContext
        do {
            await CloudKitSyncCoordinator.shared.start()
            await applyCachedSharedState()
            prepareSharedTitleMetadataForSync()
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
        guard let payload = await CloudKitSyncCoordinator.shared.cachedPayload(
                stableID: "space-state",
                scope: context.scope
              ),
              var remoteSpace = try? JSONDecoder.openTV.decode(SharedSpace.self, from: payload) else { return }
        let currentMemberID = sharedSpace.members.first(where: \.isCurrentUser)?.id
        let localActivityIDs = Set(sharedSpace.activity.map(\.id))
        let newRemoteActivities = remoteSpace.activity.filter { !localActivityIDs.contains($0.id) }
        remoteSpace.members = mergingMembers(
            remote: remoteSpace.members,
            local: sharedSpace.members,
            currentMemberID: currentMemberID
        )
        remoteSpace.titleIDs = Array(Set(remoteSpace.titleIDs + sharedSpace.titleIDs)).sorted()
        remoteSpace.activity = merging(remoteSpace.activity, sharedSpace.activity)
        remoteSpace.watchEvents = merging(remoteSpace.watchEvents ?? [], sharedSpace.watchEvents ?? [])
        remoteSpace.reactions = merging(remoteSpace.reactions ?? [], sharedSpace.reactions ?? [])
        remoteSpace.notes = merging(remoteSpace.notes ?? [], sharedSpace.notes ?? [])
        let remoteMetadata = remoteSpace.titleMetadata ?? []
        let localMetadata = sharedSpace.titleMetadata ?? []
        remoteSpace.titleMetadata = mergingTitleMetadata(remote: remoteMetadata, local: localMetadata)
        mergeSharedTitleMetadataIntoLibrary(remoteSpace.titleMetadata ?? [])
        let hasPartner = remoteSpace.members.contains { !$0.isCurrentUser }
        remoteSpace.membershipState = sharedSpace.isCurrentUserShareOwner == true && !hasPartner
            ? .pending
            : .accepted
        remoteSpace.isCloudSharingEnabled = true
        remoteSpace.cloudZoneName = context.zoneID.zoneName
        remoteSpace.cloudOwnerName = context.zoneID.ownerName
        remoteSpace.isCurrentUserShareOwner = sharedSpace.isCurrentUserShareOwner
        sharedSpace = remoteSpace
        persist()
        await partnerActivityNotifier.notify(
            about: newRemoteActivities,
            in: remoteSpace
        )
    }

    private func mergingMembers(
        remote: [SpaceMember],
        local: [SpaceMember],
        currentMemberID: SpaceMember.ID?
    ) -> [SpaceMember] {
        var membersByID = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
        for member in local {
            membersByID[member.id] = member
        }
        return membersByID.values
            .map { member in
                SpaceMember(
                    id: member.id,
                    name: member.name,
                    initials: member.initials,
                    isCurrentUser: member.id == currentMemberID
                )
            }
            .sorted { $0.id < $1.id }
    }

    private func merging<Value: Identifiable>(_ remote: [Value], _ local: [Value]) -> [Value] {
        var seen = Set<Value.ID>()
        return (remote + local).filter { seen.insert($0.id).inserted }
    }

    private func mergingTitleMetadata(
        remote: [MediaTitle],
        local: [MediaTitle]
    ) -> [MediaTitle] {
        var valuesByID = Dictionary(uniqueKeysWithValues: local.map { ($0.id, $0) })
        for title in remote {
            valuesByID[title.id] = title
        }
        return valuesByID.values.sorted { $0.id < $1.id }
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
