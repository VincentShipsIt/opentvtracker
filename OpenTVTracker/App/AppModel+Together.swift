import Foundation

enum TogetherConnectionPhase: Hashable, Sendable {
    case unconnected
    case waitingForPartner
    case connected
    case revoked
    case expired
    case left
}

extension AppModel {
    var togetherConnectionPhase: TogetherConnectionPhase {
        switch sharedSpace.resolvedMembershipState {
        case .local: .unconnected
        case .pending: .waitingForPartner
        case .accepted: .connected
        case .revoked: .revoked
        case .expired: .expired
        case .left: .left
        }
    }

    var togetherActivity: [SharedActivity] {
        let currentMemberID = sharedSpace.members.first(where: \.isCurrentUser)?.id
        return sharedSpace.activity.filter { activity in
            activity.memberID != currentMemberID
                || activity.description.localizedCaseInsensitiveContains(" together")
                || activity.description.lowercased().hasPrefix("added ")
        }
    }

    @discardableResult
    func addActivity(
        description: String,
        titleID: MediaTitle.ID? = nil,
        symbol: String = "checkmark",
        kind: SharedActivityKind = .general,
        occurredAt: Date = .now,
        watchEventID: SharedWatchEvent.ID? = nil,
        season: Int? = nil,
        episode: Int? = nil
    ) -> SharedActivity {
        let currentMember = sharedSpace.members.first(where: \.isCurrentUser)
        let activity = SharedActivity(
            id: UUID().uuidString,
            memberID: currentMember?.id ?? "local-user",
            description: description.trimmingCharacters(in: .whitespaces),
            relativeDate: "Now",
            symbol: symbol,
            titleID: titleID,
            kind: kind,
            occurredAt: occurredAt,
            watchEventID: watchEventID,
            season: season,
            episode: episode
        )
        sharedSpace.activity.insert(activity, at: 0)
        return activity
    }

    func toggleTogether(_ id: MediaTitle.ID) {
        if let index = sharedSpace.titleIDs.firstIndex(of: id) {
            sharedSpace.titleIDs.remove(at: index)
            sharedSpace.titleMetadata?.removeAll { $0.id == id }
        } else {
            sharedSpace.titleIDs.append(id)
            if let title = titles.first(where: { $0.id == id }) {
                storeSharedTitleMetadata(title)
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
        let watchedAt = Date.now
        let isRewatch = titles[index].kind == .movie && titles[index].state == .completed
        if titles[index].kind == .movie {
            titles[index].state = .completed
            titles[index].personalWatchlist = false
        } else if let next = nextUnwatchedEpisode(for: titles[index]) {
            markEpisodeWatchedTogether(titleID: id, season: next.season, episode: next.episode)
            return
        } else if var progress = titles[index].progress {
            guard progress.episode < progress.totalEpisodes else { return }
            progress.episode = min(progress.episode + 1, progress.totalEpisodes)
            titles[index].progress = progress
            titles[index].state = progress.episode == progress.totalEpisodes
                ? finishedState(for: titles[index])
                : .watching
        } else {
            return
        }
        titles[index].lastWatchedAt = watchedAt
        if titles[index].kind == .movie {
            if isRewatch {
                titles[index].rewatchCount = titles[index].completedRewatches + 1
            }
            appendDiaryWatch(title: titles[index], watchedAt: watchedAt, isRewatch: isRewatch)
        }
        let currentMemberID = sharedSpace.members.first(where: \.isCurrentUser)?.id
        let watchEventKind: WatchEventKind = isRewatch ? .rewatch : .watchedTogether
        var conversationWatchEvent: SharedWatchEvent?
        for member in sharedSpace.members {
            let event = appendWatchEvent(
                title: titles[index],
                kind: watchEventKind,
                memberID: member.id,
                occurredAt: watchedAt
            )
            if member.id == currentMemberID || conversationWatchEvent == nil {
                conversationWatchEvent = event
            }
        }
        addActivity(
            description: "watched \(titles[index].title) together",
            titleID: titles[index].id,
            kind: .watchedTogether,
            watchEventID: conversationWatchEvent?.id
        )
        persist()
        syncSharedStateSoon()
    }

    func isShared(_ id: MediaTitle.ID) -> Bool {
        sharedSpace.titleIDs.contains(id)
    }

    func togetherMemberProgressSummary(
        for title: MediaTitle,
        memberID: SpaceMember.ID
    ) -> MediaProgressSummary {
        let allEvents = sharedSpace.watchEvents ?? []
        let supersededEventIDs = Set(allEvents.compactMap { event in
            event.kind == .correction ? event.supersedesEventID : nil
        })
        let watchedEvents = allEvents.filter { event in
            event.titleID == title.id
                && event.memberID == memberID
                && !supersededEventIDs.contains(event.id)
                && (event.kind == .watched || event.kind == .watchedTogether || event.kind == .rewatch)
        }

        if title.kind == .movie {
            if !watchedEvents.isEmpty {
                return MediaProgressSummary(label: "Watched", fraction: 1)
            }
            return memberFallbackProgress(for: title, memberID: memberID)
        }

        let countedEpisodeKeys = Set((title.seasons ?? [])
            .filter { $0.number > 0 }
            .flatMap { season in
                season.episodes.map { "\(season.number):\($0.number)" }
            })
        let watchedEpisodes = Set(watchedEvents.compactMap { event -> String? in
            guard let season = event.season, let episode = event.episode else { return nil }
            return "\(season):\(episode)"
        }).intersection(countedEpisodeKeys)
        let totalEpisodeCount = countedEpisodeKeys.count

        if totalEpisodeCount > 0, !watchedEpisodes.isEmpty {
            return MediaProgressSummary(
                label: "\(watchedEpisodes.count) of \(totalEpisodeCount) episodes",
                fraction: Double(watchedEpisodes.count) / Double(totalEpisodeCount)
            )
        }

        if let latestEvent = watchedEvents.max(by: { $0.occurredAt < $1.occurredAt }),
           let season = latestEvent.season,
           let episode = latestEvent.episode {
            return MediaProgressSummary(label: "Season \(season), episode \(episode)", fraction: 0)
        }

        return memberFallbackProgress(for: title, memberID: memberID)
    }

    func prepareSharedTitleMetadataForSync() {
        let existingByID = Dictionary(
            uniqueKeysWithValues: (sharedSpace.titleMetadata ?? []).map { ($0.id, $0) }
        )
        let listTitleIDs = (sharedSpace.sharedLists ?? [])
            .filter { !$0.isDeleted }
            .flatMap(\.titleIDs)
        let sharedTitleIDs = Array(Set(sharedSpace.titleIDs + listTitleIDs)).sorted()
        sharedSpace.titleMetadata = sharedTitleIDs.compactMap { id in
            if let title = titles.first(where: { $0.id == id }) {
                return sharedMetadataCopy(of: title)
            }
            return existingByID[id]
        }
    }

    func mergeSharedTitleMetadataIntoLibrary(_ metadata: [MediaTitle]) {
        mergeCatalogTitles(metadata)
    }

    private func storeSharedTitleMetadata(_ title: MediaTitle) {
        var metadata = sharedSpace.titleMetadata ?? []
        metadata.removeAll { $0.id == title.id }
        metadata.append(sharedMetadataCopy(of: title))
        sharedSpace.titleMetadata = metadata
    }

    private func sharedMetadataCopy(of title: MediaTitle) -> MediaTitle {
        var metadata = title
        metadata.state = .planned
        metadata.progress = nil
        metadata.userRating = nil
        metadata.notes = nil
        metadata.rewatchCount = nil
        metadata.lastWatchedAt = nil
        metadata.isDismissed = nil
        metadata.isDisliked = nil
        metadata.personalWatchlist = false
        metadata.watchedEpisodeIDs = nil
        metadata.isUpNextPinned = nil
        metadata.upNextSnoozedUntil = nil
        metadata.upNextManualOrder = nil
        return metadata
    }

    private func memberFallbackProgress(
        for title: MediaTitle,
        memberID: SpaceMember.ID
    ) -> MediaProgressSummary {
        guard sharedSpace.members.first(where: { $0.id == memberID })?.isCurrentUser == true else {
            return MediaProgressSummary(label: "No progress yet", fraction: 0)
        }
        return progressSummary(for: title)
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
