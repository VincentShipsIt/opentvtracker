import Foundation

enum TVTimeHistoryApplier {
    static func apply(
        _ entity: TVTimeEntity,
        to title: inout MediaTitle,
        state: inout TVTimeMergeState
    ) -> TVTimeAppliedHistory {
        title.userRating = entity.rating ?? title.userRating
        let importedWatchlist = !entity.isArchived
            && (entity.isForLater || (entity.isFollowed && entity.watches.isEmpty))
        if entity.isArchived {
            title.state = .dropped
            title.personalWatchlist = false
        } else if entity.isForLater || (entity.isFollowed && entity.watches.isEmpty) {
            title.personalWatchlist = true
            if entity.watches.isEmpty { title.state = .planned }
        }

        var applied: TVTimeAppliedHistory
        if title.kind == .movie {
            applied = applyMovieHistory(
                entity.watches,
                importedRewatchCount: entity.importedRewatchCount,
                to: &title,
                state: &state,
                fallbackRating: entity.rating
            )
        } else {
            applied = applyEpisodeHistory(
                entity.watches,
                to: &title,
                state: &state,
                fallbackRating: entity.rating
            )
        }
        applied.watchlisted = importedWatchlist
        return applied
    }

    private static func applyMovieHistory(
        _ watches: [TVTimeWatch],
        importedRewatchCount: Int,
        to title: inout MediaTitle,
        state: inout TVTimeMergeState,
        fallbackRating: Double?
    ) -> TVTimeAppliedHistory {
        guard !watches.isEmpty else { return TVTimeAppliedHistory() }
        title.state = .completed
        title.rewatchCount = max(title.completedRewatches, importedRewatchCount)
        title.lastWatchedAt = watches.compactMap(\.occurredAt).max() ?? title.lastWatchedAt
        let events = TVTimeWatchEventFactory.make(
            watches,
            title: title,
            memberID: state.memberID,
            existingEventIDs: &state.existingEventIDs
        )
        let diaryEntries = TVTimeDiaryEntryFactory.make(
            watches,
            title: title,
            fallbackRating: fallbackRating,
            existingDiaryIDs: &state.existingDiaryIDs
        )
        return TVTimeAppliedHistory(
            rewatches: importedRewatchCount,
            watchEvents: events,
            diaryEntries: diaryEntries
        )
    }

    private static func applyEpisodeHistory(
        _ watches: [TVTimeWatch],
        to title: inout MediaTitle,
        state: inout TVTimeMergeState,
        fallbackRating: Double?
    ) -> TVTimeAppliedHistory {
        let episodeWatches = watches.filter { $0.season != nil && $0.episode != nil }
        guard !episodeWatches.isEmpty else { return TVTimeAppliedHistory() }
        var watchedIDs = title.watchedEpisodeIDs ?? []
        var matchedWatches: [TVTimeWatch] = []
        var unmatchedEpisodes = 0

        for watch in episodeWatches {
            guard let seasonNumber = watch.season, let episodeNumber = watch.episode,
                  let episode = title.seasons?
                    .first(where: { $0.number == seasonNumber })?
                    .episodes.first(where: { $0.number == episodeNumber }) else {
                unmatchedEpisodes += 1
                continue
            }
            watchedIDs.insert(episode.id)
            matchedWatches.append(watch)
        }

        guard !matchedWatches.isEmpty else {
            return TVTimeAppliedHistory(unmatchedEpisodes: unmatchedEpisodes)
        }
        applyEpisodeTracking(matchedWatches, watchedIDs: watchedIDs, to: &title)
        let rewatchCounts = rewatchCounts(for: matchedWatches)
        title.rewatchCount = max(title.completedRewatches, rewatchCounts.title)
        let events = TVTimeWatchEventFactory.make(
            matchedWatches,
            title: title,
            memberID: state.memberID,
            existingEventIDs: &state.existingEventIDs
        )
        let diaryEntries = TVTimeDiaryEntryFactory.make(
            matchedWatches,
            title: title,
            fallbackRating: fallbackRating,
            existingDiaryIDs: &state.existingDiaryIDs
        )
        return TVTimeAppliedHistory(
            watchedEpisodes: matchedWatches.count,
            unmatchedEpisodes: unmatchedEpisodes,
            rewatches: rewatchCounts.episodes,
            watchEvents: events,
            diaryEntries: diaryEntries
        )
    }

    private static func applyEpisodeTracking(
        _ watches: [TVTimeWatch],
        watchedIDs: Set<EpisodeSummary.ID>,
        to title: inout MediaTitle
    ) {
        title.watchedEpisodeIDs = watchedIDs
        title.lastWatchedAt = watches.compactMap(\.occurredAt).max() ?? title.lastWatchedAt
        if let latest = watches.max(by: {
            ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0)
        }), let seasonNumber = latest.season, let episodeNumber = latest.episode {
            let total = title.seasons?.first(where: { $0.number == seasonNumber })?.episodes.count ?? episodeNumber
            title.progress = EpisodeProgress(
                season: seasonNumber,
                episode: episodeNumber,
                totalEpisodes: max(total, 1)
            )
        }

        let releasedEpisodeIDs = releasedEpisodeIDs(in: title)
        title.state = !releasedEpisodeIDs.isEmpty && releasedEpisodeIDs.isSubset(of: watchedIDs)
            ? title.finishedWatchState : .watching
    }

    private static func rewatchCounts(for watches: [TVTimeWatch]) -> (title: Int, episodes: Int) {
        (
            title: watches.map(\.importedRewatchCount).max() ?? 0,
            episodes: watches.reduce(0) { $0 + $1.importedRewatchCount }
        )
    }

    private static func releasedEpisodeIDs(in title: MediaTitle) -> Set<EpisodeSummary.ID> {
        Set((title.seasons ?? []).flatMap { season in
            guard season.number > 0 else { return [EpisodeSummary.ID]() }
            return season.episodes.compactMap { episode in
                guard episode.airDate.map({ $0 <= Date() }) ?? true else { return nil }
                return episode.id
            }
        })
    }
}

private enum TVTimeWatchEventFactory {
    static func make(
        _ watches: [TVTimeWatch],
        title: MediaTitle,
        memberID: String,
        existingEventIDs: inout Set<String>
    ) -> [SharedWatchEvent] {
        watches.compactMap { watch in
            guard let occurredAt = watch.occurredAt else { return nil }
            let timestamp = Int64(occurredAt.timeIntervalSince1970)
            let kind: WatchEventKind = watch.isRewatch ? .rewatch : .watched
            let eventID = [
                "tvtime", title.id, String(watch.season ?? 0), String(watch.episode ?? 0),
                String(timestamp), kind.rawValue
            ].joined(separator: ":")
            guard existingEventIDs.insert(eventID).inserted else { return nil }
            return SharedWatchEvent(
                id: eventID,
                titleID: title.id,
                memberID: memberID,
                kind: kind,
                season: watch.season,
                episode: watch.episode,
                occurredAt: occurredAt,
                supersedesEventID: nil
            )
        }
    }
}

private enum TVTimeDiaryEntryFactory {
    static func make(
        _ watches: [TVTimeWatch],
        title: MediaTitle,
        fallbackRating: Double?,
        existingDiaryIDs: inout Set<String>
    ) -> [ViewingDiaryEntry] {
        let fallbackIndex = watches.firstIndex { $0.occurredAt != nil && !$0.isRewatch }
            ?? watches.firstIndex { $0.occurredAt != nil }
        return watches.enumerated().compactMap { index, watch -> ViewingDiaryEntry? in
            guard let watchedAt = watch.occurredAt else { return nil }
            let timestamp = Int64(watchedAt.timeIntervalSince1970)
            let kind: WatchEventKind = watch.isRewatch ? .rewatch : .watched
            let eventID = [
                "tvtime", title.id, String(watch.season ?? 0), String(watch.episode ?? 0),
                String(timestamp), kind.rawValue
            ].joined(separator: ":")
            let diaryID = "diary:\(eventID)"
            guard existingDiaryIDs.insert(diaryID).inserted else { return nil }

            let season = watch.season.flatMap { seasonNumber in
                title.seasons?.first(where: { $0.number == seasonNumber })
            }
            let episode = watch.episode.flatMap { episodeNumber in
                season?.episodes.first(where: { $0.number == episodeNumber })
            }
            if title.kind == .series, episode == nil { return nil }

            let rating = (watch.rating ?? (index == fallbackIndex ? fallbackRating : nil))
                .map { min(max($0, 0), 10) }
            return ViewingDiaryEntry(
                id: diaryID,
                titleID: title.id,
                scope: episode == nil ? .title : .episode,
                seasonNumber: watch.season,
                episodeID: episode?.id,
                episodeNumber: watch.episode,
                watchedAt: watchedAt,
                rating: rating,
                note: nil,
                isRewatch: watch.isRewatch,
                createdAt: watchedAt,
                updatedAt: watchedAt
            )
        }
    }
}

struct TVTimeAppliedHistory {
    var watchedEpisodes = 0
    var unmatchedEpisodes = 0
    var rewatches = 0
    var watchlisted = false
    var watchEvents: [SharedWatchEvent] = []
    var diaryEntries: [ViewingDiaryEntry] = []
}
