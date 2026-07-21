import Foundation

extension TraktSyncEngine {
    static func mergeHistory(
        _ history: [TraktHistoryItem],
        into snapshot: inout LibrarySnapshot
    ) -> Int {
        var importedIDs = Set<Int64>()
        let groupedMovies = Dictionary(grouping: history.filter { $0.media.kind == .movie }, by: \.media)

        for (media, watches) in groupedMovies {
            guard let index = titleIndex(for: media, in: snapshot.titles) else { continue }
            importedIDs.formUnion(watches.map(\.id))
            let latestWatch = watches.map(\.watchedAt).max()
            snapshot.titles[index].state = .completed
            snapshot.titles[index].lastWatchedAt = later(
                snapshot.titles[index].lastWatchedAt,
                latestWatch
            )
            snapshot.titles[index].rewatchCount = max(
                snapshot.titles[index].completedRewatches,
                max(watches.count - 1, 0)
            )
        }

        let groupedEpisodes = Dictionary(
            grouping: history.filter { $0.media.kind == .series },
            by: \.media
        )
        for (media, watches) in groupedEpisodes {
            guard let index = titleIndex(for: media, in: snapshot.titles) else { continue }
            var watchedIDs = resolvedWatchedEpisodeIDs(for: snapshot.titles[index])
            var importedForTitle = false

            for watch in watches {
                guard let seasonNumber = watch.season,
                      let episodeNumber = watch.episode else {
                    continue
                }
                let episodeID = ensureEpisode(
                    season: seasonNumber,
                    episode: episodeNumber,
                    in: &snapshot.titles[index]
                )
                importedForTitle = true
                importedIDs.insert(watch.id)
                watchedIDs.insert(episodeID)
            }

            guard importedForTitle else { continue }
            snapshot.titles[index].watchedEpisodeIDs = watchedIDs
            snapshot.titles[index].lastWatchedAt = later(
                snapshot.titles[index].lastWatchedAt,
                watches.map(\.watchedAt).max()
            )
            advanceProgressWithoutMovingBackward(title: &snapshot.titles[index], watchedIDs: watchedIDs)
        }

        return importedIDs.count
    }

    static func historyMutations(
        in snapshot: LibrarySnapshot,
        excluding uploadedIDs: Set<String>
    ) -> [TraktHistoryMutation] {
        let currentMemberID = snapshot.sharedSpace.members.first(where: \.isCurrentUser)?.id
            ?? "local-user"
        let titlesByID = Dictionary(uniqueKeysWithValues: snapshot.titles.map { ($0.id, $0) })
        var mutations = (snapshot.sharedSpace.watchEvents ?? []).compactMap { event -> TraktHistoryMutation? in
            guard !uploadedIDs.contains(event.id),
                  event.memberID == currentMemberID,
                  event.kind != .correction,
                  let title = titlesByID[event.titleID],
                  title.catalogID > 0 else {
                return nil
            }
            if title.kind == .series, event.season == nil || event.episode == nil {
                return nil
            }
            return TraktHistoryMutation(
                eventID: event.id,
                media: TraktMediaKey(kind: title.kind, tmdbID: title.catalogID),
                season: event.season,
                episode: event.episode,
                watchedAt: event.occurredAt
            )
        }

        let titleIDsWithEvents = Set((snapshot.sharedSpace.watchEvents ?? []).map(\.titleID))
        for title in snapshot.titles where
            title.kind == .movie
            && title.catalogID > 0
            && title.state == .completed
            && !titleIDsWithEvents.contains(title.id) {
            guard let watchedAt = title.lastWatchedAt else { continue }
            let eventID = "legacy:\(title.id):\(watchedAt.timeIntervalSince1970)"
            guard !uploadedIDs.contains(eventID) else { continue }
            mutations.append(TraktHistoryMutation(
                eventID: eventID,
                media: TraktMediaKey(kind: .movie, tmdbID: title.catalogID),
                season: nil,
                episode: nil,
                watchedAt: watchedAt
            ))
        }

        return mutations.sorted {
            if $0.watchedAt != $1.watchedAt { return $0.watchedAt < $1.watchedAt }
            return $0.eventID < $1.eventID
        }
    }

    static func titleIndex(
        for media: TraktMediaKey,
        in titles: [MediaTitle]
    ) -> Array<MediaTitle>.Index? {
        titles.firstIndex { $0.kind == media.kind && $0.catalogID == media.tmdbID }
    }

    static func ensureEpisode(
        season seasonNumber: Int,
        episode episodeNumber: Int,
        in title: inout MediaTitle
    ) -> EpisodeSummary.ID {
        if let episodeID = title.seasons?
            .first(where: { $0.number == seasonNumber })?
            .episodes.first(where: { $0.number == episodeNumber })?.id {
            return episodeID
        }

        let episodeID = "trakt:\(title.catalogID):s\(seasonNumber)e\(episodeNumber)"
        let episode = EpisodeSummary(
            id: episodeID,
            number: episodeNumber,
            title: "Episode \(episodeNumber)",
            airDate: nil,
            runtimeMinutes: nil
        )
        var seasons = title.seasons ?? []
        if let index = seasons.firstIndex(where: { $0.number == seasonNumber }) {
            let current = seasons[index]
            seasons[index] = SeasonSummary(
                id: current.id,
                number: current.number,
                title: current.title,
                episodes: (current.episodes + [episode]).sorted { $0.number < $1.number }
            )
        } else {
            seasons.append(SeasonSummary(
                id: "trakt:\(title.catalogID):s\(seasonNumber)",
                number: seasonNumber,
                title: "Season \(seasonNumber)",
                episodes: [episode]
            ))
            seasons.sort { $0.number < $1.number }
        }
        title.seasons = seasons
        return episodeID
    }

    static func matches(
        _ remote: TraktHistoryItem,
        _ local: TraktHistoryMutation
    ) -> Bool {
        remote.media == local.media
            && remote.season == local.season
            && remote.episode == local.episode
            && abs(remote.watchedAt.timeIntervalSince(local.watchedAt)) <= 1
    }

    static func resolvedWatchedEpisodeIDs(for title: MediaTitle) -> Set<EpisodeSummary.ID> {
        if let watchedEpisodeIDs = title.watchedEpisodeIDs { return watchedEpisodeIDs }
        let regularSeasons = (title.seasons ?? []).filter { $0.number > 0 }
        if title.state == .completed {
            return Set(regularSeasons.flatMap(\.episodes).map(\.id))
        }
        guard let progress = title.progress else { return [] }
        return Set(regularSeasons.flatMap { season -> [EpisodeSummary.ID] in
            guard season.number <= progress.season else { return [] }
            if season.number < progress.season { return season.episodes.map(\.id) }
            return season.episodes.filter { $0.number <= progress.episode }.map(\.id)
        })
    }

    static func advanceProgressWithoutMovingBackward(
        title: inout MediaTitle,
        watchedIDs: Set<EpisodeSummary.ID>
    ) {
        let regularSeasons = (title.seasons ?? [])
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
        let regularEpisodes = regularSeasons.flatMap { season in
            season.episodes.map { (season: season, episode: $0) }
        }
        guard !regularEpisodes.isEmpty else {
            if title.state != .completed { title.state = .watching }
            return
        }

        if regularEpisodes.allSatisfy({ watchedIDs.contains($0.episode.id) }) {
            title.state = .completed
            if let last = regularEpisodes.last {
                title.progress = EpisodeProgress(
                    season: last.season.number,
                    episode: last.episode.number,
                    totalEpisodes: last.season.episodes.count
                )
            }
            return
        }

        let highestWatched = regularEpisodes.last { watchedIDs.contains($0.episode.id) }
        if let highestWatched {
            let candidate = EpisodeProgress(
                season: highestWatched.season.number,
                episode: highestWatched.episode.number,
                totalEpisodes: highestWatched.season.episodes.count
            )
            if isAfter(candidate, title.progress) {
                title.progress = candidate
            }
            if title.state != .completed { title.state = .watching }
        }
    }

    static func isAfter(_ candidate: EpisodeProgress, _ existing: EpisodeProgress?) -> Bool {
        guard let existing else { return true }
        if candidate.season != existing.season { return candidate.season > existing.season }
        return candidate.episode > existing.episode
    }

    static func later(_ lhs: Date?, _ rhs: Date?) -> Date? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?): max(lhs, rhs)
        case let (lhs?, nil): lhs
        case let (nil, rhs?): rhs
        case (nil, nil): nil
        }
    }
}
