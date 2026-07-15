import Foundation

extension AppModel {
    var togetherActivity: [SharedActivity] {
        let currentMemberID = sharedSpace.members.first(where: \.isCurrentUser)?.id
        return sharedSpace.activity.filter { activity in
            activity.memberID != currentMemberID
                || activity.description.localizedCaseInsensitiveContains(" together")
                || activity.description.lowercased().hasPrefix("added ")
        }
    }

    func addActivity(
        description: String,
        titleID: MediaTitle.ID? = nil,
        symbol: String = "checkmark"
    ) {
        let currentMember = sharedSpace.members.first(where: \.isCurrentUser)
        let activity = SharedActivity(
            id: UUID().uuidString,
            memberID: currentMember?.id ?? "local-user",
            description: description.trimmingCharacters(in: .whitespaces),
            relativeDate: "Now",
            symbol: symbol,
            titleID: titleID
        )
        sharedSpace.activity.insert(activity, at: 0)
    }

    func toggleTogether(_ id: MediaTitle.ID) {
        if let index = sharedSpace.titleIDs.firstIndex(of: id) {
            sharedSpace.titleIDs.remove(at: index)
        } else {
            sharedSpace.titleIDs.append(id)
            if let title = titles.first(where: { $0.id == id }) {
                addActivity(description: "added \(title.title)", titleID: title.id, symbol: "plus")
            }
        }
        persist()
        syncSharedStateSoon()
    }

    func setSharedMembershipState(_ state: SharedMembershipState) {
        let wasOwner = sharedSpace.isCurrentUserShareOwner != false
        sharedSpace.membershipState = state
        sharedSpace.isCloudSharingEnabled = state == .pending || state == .accepted
        persist()
        if sharedSpace.isCloudSharingEnabled {
            syncSharedStateSoon()
        } else {
            Task {
                await CloudKitSyncCoordinator.shared.purge(
                    scope: wasOwner ? .privateDatabase : .sharedDatabase
                )
            }
        }
    }

    func markPartnerShareCreated() {
        let zoneID = CloudKitPartnerSharingService.zoneID(for: sharedSpace.id)
        sharedSpace.cloudZoneName = zoneID.zoneName
        sharedSpace.cloudOwnerName = zoneID.ownerName
        sharedSpace.isCurrentUserShareOwner = true
        sharedSpace.membershipState = .pending
        sharedSpace.isCloudSharingEnabled = true
        persist()
    }

    func acceptPartnerShare(_ location: PartnerShareLocation) {
        sharedSpace.cloudZoneName = location.zoneName
        sharedSpace.cloudOwnerName = location.ownerName
        sharedSpace.isCurrentUserShareOwner = false
        sharedSpace.members = [PartnerDeviceIdentity.currentMember]
        sharedSpace.membershipState = .accepted
        sharedSpace.isCloudSharingEnabled = true
        persist()
        Task { await startCloudSyncIfNeeded() }
    }

    func markWatchedTogether(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        if titles[index].kind == .movie {
            titles[index].state = .completed
        } else if let next = nextUnwatchedEpisode(for: titles[index]) {
            markEpisodeWatchedTogether(titleID: id, season: next.season, episode: next.episode)
            return
        } else if var progress = titles[index].progress {
            progress.episode = min(progress.episode + 1, progress.totalEpisodes)
            titles[index].progress = progress
            titles[index].state = progress.episode == progress.totalEpisodes ? .completed : .watching
        }
        titles[index].lastWatchedAt = .now
        for member in sharedSpace.members {
            appendWatchEvent(title: titles[index], kind: .watchedTogether, memberID: member.id)
        }
        addActivity(
            description: "watched \(titles[index].title) together",
            titleID: titles[index].id
        )
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

private enum PartnerDeviceIdentity {
    private static let defaultsKey = "opentv.partner.member-id"

    static var currentMember: SpaceMember {
        let defaults = UserDefaults.standard
        let id: String
        if let existingID = defaults.string(forKey: defaultsKey) {
            id = existingID
        } else {
            id = "partner-\(UUID().uuidString.lowercased())"
            defaults.set(id, forKey: defaultsKey)
        }
        return SpaceMember(id: id, name: "Partner", initials: "P", isCurrentUser: true)
    }
}
