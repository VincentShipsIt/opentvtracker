import Foundation

extension MediaTitle {
    var episodeIDsThroughProgress: Set<EpisodeSummary.ID> {
        guard let progress else { return [] }
        let episodeIDs: [EpisodeSummary.ID] = (seasons ?? [])
            .filter { $0.number > 0 }
            .flatMap { season -> [EpisodeSummary.ID] in
                guard season.number <= progress.season else { return [] }
                if season.number < progress.season { return season.episodes.map(\.id) }
                return season.episodes.filter { $0.number <= progress.episode }.map(\.id)
            }
        return Set(episodeIDs)
    }
}

extension AppModel {
    func progressSummary(for title: MediaTitle) -> MediaProgressSummary {
        guard title.kind == .series else {
            return MediaProgressSummary(
                label: title.state == .completed ? "Watched" : "Not watched yet",
                fraction: title.state == .completed ? 1 : 0
            )
        }

        let releasedEpisodeIDs = Set(releasedEpisodes(for: title).map(\.id))
        let totalEpisodeCount = releasedEpisodeIDs.count
        guard totalEpisodeCount > 0 else {
            return MediaProgressSummary(
                label: title.progress?.label ?? title.state.label,
                fraction: title.state.isCurrentViewingComplete ? 1 : title.progress?.fraction ?? 0
            )
        }

        let watchedCount = releasedEpisodeIDs.intersection(resolvedWatchedEpisodeIDs(for: title)).count
        return MediaProgressSummary(
            label: "\(watchedCount) of \(totalEpisodeCount) episodes",
            fraction: Double(watchedCount) / Double(totalEpisodeCount)
        )
    }

    func togetherProgressSummary(for title: MediaTitle) -> MediaProgressSummary {
        let togetherEvents = (sharedSpace.watchEvents ?? []).filter {
            $0.titleID == title.id && $0.kind == .watchedTogether
        }
        guard !togetherEvents.isEmpty else { return progressSummary(for: title) }

        guard title.kind == .series else {
            return MediaProgressSummary(label: "Watched together", fraction: 1)
        }

        let totalEpisodeCount = (title.seasons ?? [])
            .filter { $0.number > 0 }
            .reduce(0) { $0 + $1.episodes.count }
        let watchedEpisodes = Set(togetherEvents.compactMap { event -> String? in
            guard let season = event.season, let episode = event.episode else { return nil }
            return "\(season):\(episode)"
        })
        guard totalEpisodeCount > 0, !watchedEpisodes.isEmpty else {
            return MediaProgressSummary(label: "Watched together", fraction: title.state.isCurrentViewingComplete ? 1 : 0)
        }
        return MediaProgressSummary(
            label: "\(watchedEpisodes.count) of \(totalEpisodeCount) episodes together",
            fraction: Double(watchedEpisodes.count) / Double(totalEpisodeCount)
        )
    }

    func isEpisodeWatched(
        titleID: MediaTitle.ID,
        seasonNumber: Int,
        episodeID: EpisodeSummary.ID
    ) -> Bool {
        guard let title = mediaTitle(withID: titleID),
              title.seasons?.contains(where: { season in
                  season.number == seasonNumber && season.episodes.contains(where: { $0.id == episodeID })
              }) == true else {
            return false
        }
        return resolvedWatchedEpisodeIDs(for: title).contains(episodeID)
    }

    func watchedEpisodeCount(titleID: MediaTitle.ID, season: SeasonSummary) -> Int {
        guard let title = mediaTitle(withID: titleID) else { return 0 }
        let watchedIDs = resolvedWatchedEpisodeIDs(for: title)
        return season.episodes.lazy.filter { watchedIDs.contains($0.id) }.count
    }

    func setEpisodeWatched(
        _ watched: Bool,
        titleID: MediaTitle.ID,
        seasonNumber: Int,
        episodeID: EpisodeSummary.ID
    ) {
        guard let index = trackableTitleIndex(for: titleID),
              let season = titles[index].seasons?.first(where: { $0.number == seasonNumber }),
              let episode = season.episodes.first(where: { $0.id == episodeID }) else {
            return
        }

        applyEpisodeWatchState(
            watched,
            at: index,
            episodes: [(season, episode)],
            activityDescription: watched
                ? "watched \(titles[index].title) S\(season.number) E\(episode.number)"
                : "marked \(titles[index].title) S\(season.number) E\(episode.number) unwatched",
            activitySymbol: watched ? "checkmark" : "arrow.uturn.backward"
        )
    }

    func setSeasonEpisodesWatched(
        _ watched: Bool,
        titleID: MediaTitle.ID,
        seasonNumber: Int
    ) {
        guard let index = trackableTitleIndex(for: titleID),
              let season = titles[index].seasons?.first(where: { $0.number == seasonNumber }) else {
            return
        }

        let episodes = season.episodes.map { (season: season, episode: $0) }
        applyEpisodeWatchState(
            watched,
            at: index,
            episodes: episodes,
            activityDescription: watched
                ? "watched all of \(titles[index].title) \(season.title)"
                : "marked \(titles[index].title) \(season.title) unwatched",
            activitySymbol: watched ? "checkmark.circle.fill" : "arrow.uturn.backward.circle.fill"
        )
    }

    func markEpisodesWatchedThrough(
        titleID: MediaTitle.ID,
        seasonNumber: Int,
        episodeNumber: Int
    ) {
        guard let index = trackableTitleIndex(for: titleID) else { return }
        let episodes = episodesThrough(
            title: titles[index],
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
        applyEpisodeWatchState(
            true,
            at: index,
            episodes: episodes,
            activityDescription: "watched \(titles[index].title) through S\(seasonNumber) E\(episodeNumber)",
            activitySymbol: "checkmark.circle.fill"
        )
    }

    func areEpisodesWatchedThrough(
        titleID: MediaTitle.ID,
        seasonNumber: Int,
        episodeNumber: Int
    ) -> Bool {
        guard let title = mediaTitle(withID: titleID) else { return false }
        let episodes = episodesThrough(
            title: title,
            seasonNumber: seasonNumber,
            episodeNumber: episodeNumber
        )
        guard !episodes.isEmpty else { return false }
        let watchedIDs = resolvedWatchedEpisodeIDs(for: title)
        return episodes.allSatisfy { watchedIDs.contains($0.episode.id) }
    }

    func hasUnwatchedEpisodesBefore(
        titleID: MediaTitle.ID,
        seasonNumber: Int,
        episodeNumber: Int
    ) -> Bool {
        guard let title = mediaTitle(withID: titleID),
              let season = regularSeasons(for: title).first(where: { $0.number == seasonNumber }) else {
            return false
        }
        let watchedIDs = resolvedWatchedEpisodeIDs(for: title)
        return season.episodes.contains { episode in
            episode.number < episodeNumber && !watchedIDs.contains(episode.id)
        }
    }

    func regularSeasons(for title: MediaTitle) -> [SeasonSummary] {
        (title.seasons ?? [])
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
    }

    func nextUnwatchedEpisode(
        for title: MediaTitle
    ) -> (season: SeasonSummary, episode: EpisodeSummary)? {
        let watchedIDs = resolvedWatchedEpisodeIDs(for: title)
        let releasedIDs = Set(releasedEpisodes(for: title).map(\.id))
        for season in regularSeasons(for: title) {
            if let episode = season.episodes.sorted(by: { $0.number < $1.number })
                .first(where: { episode in
                    releasedIDs.contains(episode.id) && !watchedIDs.contains(episode.id)
                }) {
                return (season, episode)
            }
        }
        return nil
    }

    func markEpisodeWatchedTogether(
        titleID: MediaTitle.ID,
        season: SeasonSummary,
        episode: EpisodeSummary
    ) {
        guard let index = trackableTitleIndex(for: titleID) else { return }
        var watchedIDs = resolvedWatchedEpisodeIDs(for: titles[index])
        guard watchedIDs.insert(episode.id).inserted else { return }

        titles[index].watchedEpisodeIDs = watchedIDs
        updateEpisodeProgress(at: index, watchedIDs: watchedIDs)
        titles[index].lastWatchedAt = .now
        for member in sharedSpace.members {
            appendWatchEvent(
                title: titles[index],
                kind: .watchedTogether,
                memberID: member.id,
                season: season.number,
                episode: episode.number
            )
        }
        addActivity(
            description: "watched \(titles[index].title) S\(season.number) E\(episode.number) together",
            titleID: titles[index].id
        )
        persist()
        syncSharedStateSoon()
    }
}

private extension AppModel {
    func applyEpisodeWatchState(
        _ watched: Bool,
        at index: Int,
        episodes: [(season: SeasonSummary, episode: EpisodeSummary)],
        activityDescription: String,
        activitySymbol: String
    ) {
        var watchedIDs = resolvedWatchedEpisodeIDs(for: titles[index])
        let changedEpisodes = episodes.filter { watchedIDs.contains($0.episode.id) != watched }
        guard !changedEpisodes.isEmpty else { return }

        for item in changedEpisodes {
            if watched {
                watchedIDs.insert(item.episode.id)
                appendWatchEvent(
                    title: titles[index],
                    kind: .watched,
                    season: item.season.number,
                    episode: item.episode.number
                )
            } else {
                watchedIDs.remove(item.episode.id)
                supersedePersonalWatchEvents(
                    title: titles[index],
                    seasonNumber: item.season.number,
                    episodeNumber: item.episode.number
                )
            }
        }

        titles[index].watchedEpisodeIDs = watchedIDs
        updateEpisodeProgress(at: index, watchedIDs: watchedIDs)
        if watched {
            titles[index].lastWatchedAt = .now
        }
        addActivity(
            description: activityDescription,
            titleID: titles[index].id,
            symbol: activitySymbol
        )
        persist()
        refreshRecommendationsSoon()
        syncSharedStateSoon()
    }

    func episodesThrough(
        title: MediaTitle,
        seasonNumber: Int,
        episodeNumber: Int
    ) -> [(season: SeasonSummary, episode: EpisodeSummary)] {
        guard let season = regularSeasons(for: title).first(where: { $0.number == seasonNumber }) else {
            return []
        }
        return season.episodes
            .filter { $0.number <= episodeNumber }
            .sorted { $0.number < $1.number }
            .map { (season: season, episode: $0) }
    }

    func updateEpisodeProgress(at index: Int, watchedIDs: Set<EpisodeSummary.ID>) {
        let seasons = regularSeasons(for: titles[index])

        var latestSeason: SeasonSummary?
        var latestEpisode: EpisodeSummary?
        for season in seasons {
            for episode in season.episodes where watchedIDs.contains(episode.id) {
                guard let currentSeason = latestSeason, let currentEpisode = latestEpisode else {
                    latestSeason = season
                    latestEpisode = episode
                    continue
                }
                if season.number > currentSeason.number
                    || (season.number == currentSeason.number && episode.number > currentEpisode.number) {
                    latestSeason = season
                    latestEpisode = episode
                }
            }
        }

        if let latestSeason, let latestEpisode {
            titles[index].progress = EpisodeProgress(
                season: latestSeason.number,
                episode: latestEpisode.number,
                totalEpisodes: latestSeason.episodes.count
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

    func supersedePersonalWatchEvents(
        title: MediaTitle,
        seasonNumber: Int,
        episodeNumber: Int
    ) {
        let events = sharedSpace.watchEvents ?? []
        let supersededIDs = Set(events.compactMap { event in
            event.kind == .correction ? event.supersedesEventID : nil
        })
        let memberID = sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let matchingEvents = events.filter { event in
            event.titleID == title.id
                && event.memberID == memberID
                && event.kind == .watched
                && event.season == seasonNumber
                && event.episode == episodeNumber
                && !supersededIDs.contains(event.id)
        }
        for event in matchingEvents {
            appendWatchEvent(
                title: title,
                kind: .correction,
                memberID: memberID,
                season: seasonNumber,
                episode: episodeNumber,
                supersedesEventID: event.id
            )
        }
    }
}

extension AppModel {
    func resolvedWatchedEpisodeIDs(for title: MediaTitle) -> Set<EpisodeSummary.ID> {
        if let watchedEpisodeIDs = title.watchedEpisodeIDs { return watchedEpisodeIDs }
        if title.progress != nil { return title.episodeIDsThroughProgress }
        if title.state.isCurrentViewingComplete {
            return Set(releasedEpisodes(for: title).map(\.id))
        }
        return []
    }
}
