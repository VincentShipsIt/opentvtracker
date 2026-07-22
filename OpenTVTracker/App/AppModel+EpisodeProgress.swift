import Foundation

extension AppModel {
    func markEpisodeWatchedTogether(
        titleID: MediaTitle.ID,
        season: SeasonSummary,
        episode: EpisodeSummary
    ) {
        guard let index = trackableTitleIndex(for: titleID) else { return }
        let watchedAt = Date.now
        let markedEpisodeWatched = recordEpisodeWatch(
            at: index,
            season: season,
            episode: episode,
            watchedAt: watchedAt
        )
        let events = appendMissingTogetherEvents(
            at: index,
            season: season,
            episode: episode,
            watchedAt: watchedAt
        )
        guard markedEpisodeWatched || events.added else { return }

        titles[index].lastWatchedAt = watchedAt
        if events.added {
            addActivity(
                description: "watched \(titles[index].title) S\(season.number) E\(episode.number) together",
                titleID: titles[index].id,
                kind: .watchedTogether,
                watchEventID: events.conversationEvent?.id,
                season: season.number,
                episode: episode.number
            )
        }
        persist()
        syncSharedStateSoon()
    }

    func updateEpisodeProgress(at index: Int, watchedIDs: Set<EpisodeSummary.ID>) {
        let seasons = regularSeasons(for: titles[index])
        let latest = latestWatchedEpisode(in: seasons, watchedIDs: watchedIDs)

        if let latest {
            titles[index].progress = EpisodeProgress(
                season: latest.season.number,
                episode: latest.episode.number,
                totalEpisodes: latest.season.episodes.count
            )
        } else if let firstSeason = seasons.first {
            titles[index].progress = EpisodeProgress(
                season: firstSeason.number,
                episode: 0,
                totalEpisodes: firstSeason.episodes.count
            )
        } else {
            titles[index].progress = nil
        }

        if !watchedIDs.isEmpty {
            titles[index].state = trackingStateAfterEpisodeUpdate(
                for: titles[index],
                watchedIDs: watchedIDs
            )
        } else if titles[index].state == .watching || titles[index].state.isCurrentViewingComplete {
            titles[index].state = .planned
        }
    }
}

private extension AppModel {
    func recordEpisodeWatch(
        at index: Int,
        season: SeasonSummary,
        episode: EpisodeSummary,
        watchedAt: Date
    ) -> Bool {
        var watchedIDs = resolvedWatchedEpisodeIDs(for: titles[index])
        guard watchedIDs.insert(episode.id).inserted else { return false }
        titles[index].watchedEpisodeIDs = watchedIDs
        updateEpisodeProgress(at: index, watchedIDs: watchedIDs)
        appendDiaryWatch(
            title: titles[index],
            season: season,
            episode: episode,
            watchedAt: watchedAt,
            isRewatch: false
        )
        return true
    }

    func appendMissingTogetherEvents(
        at index: Int,
        season: SeasonSummary,
        episode: EpisodeSummary,
        watchedAt: Date
    ) -> (conversationEvent: SharedWatchEvent?, added: Bool) {
        let existingEvents = (sharedSpace.watchEvents ?? []).filter { event in
            event.titleID == titles[index].id
                && event.kind == .watchedTogether
                && event.season == season.number
                && event.episode == episode.number
        }
        let currentMemberID = sharedSpace.members.first(where: \.isCurrentUser)?.id
        var conversationEvent = existingEvents.first { $0.memberID == currentMemberID }
            ?? existingEvents.first
        let membersWithEvents = Set(existingEvents.map(\.memberID))
        var added = false
        for member in sharedSpace.members where !membersWithEvents.contains(member.id) {
            let event = appendWatchEvent(
                title: titles[index],
                kind: .watchedTogether,
                memberID: member.id,
                season: season.number,
                episode: episode.number,
                occurredAt: watchedAt
            )
            if member.id == currentMemberID || conversationEvent == nil {
                conversationEvent = event
            }
            added = true
        }
        return (conversationEvent, added)
    }

    func latestWatchedEpisode(
        in seasons: [SeasonSummary],
        watchedIDs: Set<EpisodeSummary.ID>
    ) -> (season: SeasonSummary, episode: EpisodeSummary)? {
        seasons.flatMap { season in
            season.episodes
                .filter { watchedIDs.contains($0.id) }
                .map { (season: season, episode: $0) }
        }
        .max { lhs, rhs in
            if lhs.season.number != rhs.season.number {
                return lhs.season.number < rhs.season.number
            }
            return lhs.episode.number < rhs.episode.number
        }
    }
}
