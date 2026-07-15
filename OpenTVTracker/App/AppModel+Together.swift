import Foundation

extension AppModel {
    func toggleTogether(_ id: MediaTitle.ID) {
        if let index = sharedSpace.titleIDs.firstIndex(of: id) {
            sharedSpace.titleIDs.remove(at: index)
        } else {
            sharedSpace.titleIDs.append(id)
            if let title = titles.first(where: { $0.id == id }) {
                addActivity(description: "added \(title.title)")
            }
        }
        persist()
        syncSharedStateSoon()
    }

    func setSharedMembershipState(_ state: SharedMembershipState) {
        sharedSpace.membershipState = state
        sharedSpace.isCloudSharingEnabled = state == .pending || state == .accepted
        persist()
        syncSharedStateSoon()
    }

    func markPartnerShareCreated() {
        let zoneID = CloudKitPartnerSharingService.zoneID(for: sharedSpace.id)
        sharedSpace.cloudZoneName = zoneID.zoneName
        sharedSpace.cloudOwnerName = zoneID.ownerName
        sharedSpace.isCurrentUserShareOwner = true
        setSharedMembershipState(.pending)
    }

    func acceptPartnerShare(_ location: PartnerShareLocation) {
        sharedSpace.cloudZoneName = location.zoneName
        sharedSpace.cloudOwnerName = location.ownerName
        sharedSpace.isCurrentUserShareOwner = false
        setSharedMembershipState(.accepted)
        Task { await startCloudSyncIfNeeded() }
    }

    func markWatchedTogether(_ id: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == id }) else { return }
        if titles[index].kind == .movie {
            titles[index].state = .completed
        } else if var progress = titles[index].progress {
            progress.episode = min(progress.episode + 1, progress.totalEpisodes)
            titles[index].progress = progress
            titles[index].state = progress.episode == progress.totalEpisodes ? .completed : .watching
        }
        titles[index].lastWatchedAt = .now
        for member in sharedSpace.members {
            appendWatchEvent(title: titles[index], kind: .watchedTogether, memberID: member.id)
        }
        addActivity(description: "watched \(titles[index].title) together")
        persist()
        syncSharedStateSoon()
    }

    func react(to activityID: SharedActivity.ID, symbol: String) {
        let memberID = sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        var reactions = sharedSpace.reactions ?? []
        reactions.removeAll { $0.activityID == activityID && $0.memberID == memberID }
        reactions.append(
            SharedReaction(
                id: UUID().uuidString,
                activityID: activityID,
                memberID: memberID,
                symbol: symbol,
                occurredAt: .now
            )
        )
        sharedSpace.reactions = reactions
        persist()
        syncSharedStateSoon()
    }

    func addSharedNote(_ text: String, titleID: MediaTitle.ID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let memberID = sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        var notes = sharedSpace.notes ?? []
        notes.append(
            SharedNote(
                id: UUID().uuidString,
                titleID: titleID,
                memberID: memberID,
                text: trimmed,
                createdAt: .now
            )
        )
        sharedSpace.notes = notes
        persist()
        syncSharedStateSoon()
    }

    func isShared(_ id: MediaTitle.ID) -> Bool {
        sharedSpace.titleIDs.contains(id)
    }
}
