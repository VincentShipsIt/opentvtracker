import Foundation

extension AppModel {
    func react(to activityID: SharedActivity.ID, symbol: String) {
        if let activity = sharedSpace.activity.first(where: { $0.id == activityID }),
           let watchEventID = activity.watchEventID,
           let asset = SharedReactionAssetPolicy.allAssets.first(where: {
               $0.displayValue == symbol
                   || ($0.id == "love" && symbol == "heart.fill")
                   || ($0.id == "fire" && symbol == "hand.thumbsup.fill")
                   || ($0.id == "laugh" && symbol == "face.smiling.fill")
           }) {
            react(to: watchEventID, asset: asset)
            return
        }

        let memberID = sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let reactionID = "activity-reaction:\(activityID):\(memberID)"
        var reactions = sharedSpace.reactions ?? []
        let replacedReactions = reactions.filter {
            $0.activityID == activityID && $0.memberID == memberID && $0.id != reactionID
        }
        reactions.removeAll { $0.activityID == activityID && $0.memberID == memberID }
        reactions.append(
            SharedReaction(
                id: reactionID,
                activityID: activityID,
                memberID: memberID,
                symbol: symbol,
                occurredAt: .now
            )
        )
        sharedSpace.reactions = reactions
        var deletions = sharedSpace.conversationDeletions ?? []
        deletions.append(contentsOf: replacedReactions.map {
            SharedConversationDeletion(entryID: $0.id, entryKind: .reaction)
        })
        sharedSpace.conversationDeletions = deletions
        persist()
        syncSharedStateSoon()
    }

    func react(
        to watchEventID: SharedWatchEvent.ID,
        asset: SharedReactionAsset
    ) {
        guard let validatedAsset = SharedReactionAssetPolicy.asset(kind: asset.kind, id: asset.id),
              let watchEvent = sharedSpace.watchEvents?.first(where: { $0.id == watchEventID }) else {
            return
        }
        let memberID = currentSharedMemberID
        let reactionID = "episode-reaction:\(watchEventID):\(memberID)"
        let activityID = sharedSpace.activity.first(where: { $0.watchEventID == watchEventID })?.id
            ?? "watch-event:\(watchEventID)"
        let reaction = SharedReaction(
            id: reactionID,
            activityID: activityID,
            memberID: memberID,
            symbol: validatedAsset.displayValue,
            occurredAt: .now,
            watchEventID: watchEventID,
            titleID: watchEvent.titleID,
            season: watchEvent.season,
            episode: watchEvent.episode,
            assetKind: validatedAsset.kind,
            assetID: validatedAsset.id
        )
        var reactions = sharedSpace.reactions ?? []
        reactions.removeAll { $0.id == reactionID }
        reactions.append(reaction)
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

    func addSharedEpisodeNote(
        _ text: String,
        watchEventID: SharedWatchEvent.ID
    ) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 1_000,
              let watchEvent = sharedSpace.watchEvents?.first(where: { $0.id == watchEventID }) else {
            return
        }
        var notes = sharedSpace.notes ?? []
        notes.append(
            SharedNote(
                id: UUID().uuidString,
                titleID: watchEvent.titleID,
                memberID: currentSharedMemberID,
                text: trimmed,
                createdAt: .now,
                watchEventID: watchEventID,
                season: watchEvent.season,
                episode: watchEvent.episode
            )
        )
        sharedSpace.notes = notes
        persist()
        syncSharedStateSoon()
    }

    func conversationWatchEvent(
        titleID: MediaTitle.ID,
        season: Int,
        episode: Int
    ) -> SharedWatchEvent? {
        let events = sharedSpace.watchEvents ?? []
        if let anchoredEventID = sharedSpace.activity.first(where: {
            $0.titleID == titleID
                && $0.season == season
                && $0.episode == episode
                && $0.watchEventID != nil
        })?.watchEventID,
           let anchoredEvent = events.first(where: { $0.id == anchoredEventID }) {
            return anchoredEvent
        }
        let supersededIDs = Set(events.compactMap { event in
            event.kind == .correction ? event.supersedesEventID : nil
        })
        let matchingEvents = events
            .filter { event in
                event.titleID == titleID
                    && event.season == season
                    && event.episode == episode
                    && event.kind != .correction
                    && !supersededIDs.contains(event.id)
            }
            .sorted {
                if $0.occurredAt != $1.occurredAt {
                    return $0.occurredAt > $1.occurredAt
                }
                return $0.id < $1.id
            }

        return matchingEvents.first(where: { $0.kind == .watchedTogether })
            ?? matchingEvents.first(where: { $0.memberID == currentSharedMemberID })
    }

    func sharedEpisodeNotes(watchEventID: SharedWatchEvent.ID) -> [SharedNote] {
        (sharedSpace.notes ?? [])
            .filter { $0.watchEventID == watchEventID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func sharedEpisodeReactions(watchEventID: SharedWatchEvent.ID) -> [SharedReaction] {
        (sharedSpace.reactions ?? [])
            .filter { $0.watchEventID == watchEventID }
            .sorted { $0.occurredAt < $1.occurredAt }
    }

    func requestSharedConversationNotifications() async -> Bool {
        await sharedConversationNotifier.requestAuthorization()
    }

    func deletePrivateConversationData() {
        guard sharedSpace.isCurrentUserShareOwner != false else { return }
        let deletedAt = Date.now
        var deletions = sharedSpace.conversationDeletions ?? []
        deletions.append(contentsOf: (sharedSpace.reactions ?? []).map {
            SharedConversationDeletion(
                entryID: $0.id,
                entryKind: .reaction,
                deletedAt: deletedAt
            )
        })
        deletions.append(contentsOf: (sharedSpace.notes ?? []).map {
            SharedConversationDeletion(
                entryID: $0.id,
                entryKind: .note,
                deletedAt: deletedAt
            )
        })
        sharedSpace.reactions = []
        sharedSpace.notes = []
        sharedSpace.conversationDeletions = SharedConversationReconciler.reconcile(
            remote: sharedSpace,
            local: sharedSpace
        ).deletions
        persist()
        syncSharedStateSoon()
    }

    func isEpisodeWatchedTogether(
        titleID: MediaTitle.ID,
        season: Int,
        episode: Int
    ) -> Bool {
        (sharedSpace.watchEvents ?? []).contains { event in
            event.titleID == titleID
                && event.kind == .watchedTogether
                && event.season == season
                && event.episode == episode
        }
    }

    private var currentSharedMemberID: SpaceMember.ID {
        sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
    }
}
