import Foundation

enum TVTimeHistoryApplier {
    static func apply(
        _ entity: TVTimeEntity,
        to title: inout MediaTitle,
        memberID: String,
        existingEventIDs: inout Set<String>
    ) -> TVTimeAppliedHistory {
        title.userRating = entity.rating ?? title.userRating
        let importedWatchlist = !entity.isArchived
            && (entity.isForLater || (entity.isFollowed && entity.watches.isEmpty))
        if entity.isArchived {
            title.state = .paused
            title.personalWatchlist = false
        } else if entity.isForLater || (entity.isFollowed && entity.watches.isEmpty) {
            title.personalWatchlist = true
            if entity.watches.isEmpty { title.state = .planned }
        }

        var applied: TVTimeAppliedHistory
        if title.kind == .movie {
            applied = applyMovieHistory(
                entity.watches,
                rewatchCount: entity.rewatchCount,
                to: &title,
                memberID: memberID,
                existingEventIDs: &existingEventIDs
            )
        } else {
            applied = applyEpisodeHistory(
                entity.watches,
                to: &title,
                memberID: memberID,
                existingEventIDs: &existingEventIDs
            )
        }
        applied.watchlisted = importedWatchlist
        return applied
    }

    private static func applyMovieHistory(
        _ watches: [TVTimeWatch],
        rewatchCount: Int,
        to title: inout MediaTitle,
        memberID: String,
        existingEventIDs: inout Set<String>
    ) -> TVTimeAppliedHistory {
        guard !watches.isEmpty else { return TVTimeAppliedHistory() }
        title.state = .completed
        let importedRewatches = [
            rewatchCount,
            watches.count - 1,
            watches.filter(\.isRewatch).count
        ].max() ?? 0
        title.rewatchCount = max(title.completedRewatches, importedRewatches)
        title.lastWatchedAt = watches.compactMap(\.occurredAt).max() ?? title.lastWatchedAt
        let events = TVTimeWatchEventFactory.make(
            watches,
            title: title,
            memberID: memberID,
            existingEventIDs: &existingEventIDs
        )
        return TVTimeAppliedHistory(rewatches: importedRewatches, watchEvents: events)
    }

    private static func applyEpisodeHistory(
        _ watches: [TVTimeWatch],
        to title: inout MediaTitle,
        memberID: String,
        existingEventIDs: inout Set<String>
    ) -> TVTimeAppliedHistory {
        let episodeWatches = watches.filter { $0.season != nil && $0.episode != nil }
        guard !episodeWatches.isEmpty else { return TVTimeAppliedHistory() }
        var watchedIDs = title.watchedEpisodeIDs ?? []
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
        }

        title.watchedEpisodeIDs = watchedIDs
        title.lastWatchedAt = episodeWatches.compactMap(\.occurredAt).max() ?? title.lastWatchedAt
        if let latest = episodeWatches.max(by: {
            ($0.season ?? 0, $0.episode ?? 0) < ($1.season ?? 0, $1.episode ?? 0)
        }), let seasonNumber = latest.season, let episodeNumber = latest.episode {
            let total = title.seasons?.first(where: { $0.number == seasonNumber })?.episodes.count ?? episodeNumber
            title.progress = EpisodeProgress(
                season: seasonNumber,
                episode: episodeNumber,
                totalEpisodes: max(total, 1)
            )
        }

        let releasedEpisodeIDs = Set((title.seasons ?? []).flatMap { season in
            guard season.number > 0 else { return [EpisodeSummary.ID]() }
            return season.episodes.compactMap { episode in
                guard let airDate = episode.airDate, airDate <= Date() else { return nil }
                return episode.id
            }
        })
        title.state = !releasedEpisodeIDs.isEmpty && releasedEpisodeIDs.isSubset(of: watchedIDs)
            ? .completed : .watching

        let events = TVTimeWatchEventFactory.make(
            episodeWatches,
            title: title,
            memberID: memberID,
            existingEventIDs: &existingEventIDs
        )
        return TVTimeAppliedHistory(
            watchedEpisodes: episodeWatches.count - unmatchedEpisodes,
            unmatchedEpisodes: unmatchedEpisodes,
            rewatches: episodeWatches.filter(\.isRewatch).count,
            watchEvents: events
        )
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

struct TVTimeAppliedHistory {
    var watchedEpisodes = 0
    var unmatchedEpisodes = 0
    var rewatches = 0
    var watchlisted = false
    var watchEvents: [SharedWatchEvent] = []
}
