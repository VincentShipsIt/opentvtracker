import Foundation

extension AppModel {
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

        var watchedIDs = resolvedWatchedEpisodeIDs(for: titles[index])
        guard watchedIDs.contains(episode.id) != watched else { return }

        if watched {
            watchedIDs.insert(episode.id)
            titles[index].watchedEpisodeIDs = watchedIDs
            updateEpisodeProgress(at: index, watchedIDs: watchedIDs)
            titles[index].lastWatchedAt = .now
            appendWatchEvent(
                title: titles[index],
                kind: .watched,
                season: season.number,
                episode: episode.number
            )
            addActivity(
                description: "watched \(titles[index].title) S\(season.number) E\(episode.number)",
                titleID: titles[index].id
            )
        } else {
            watchedIDs.remove(episode.id)
            titles[index].watchedEpisodeIDs = watchedIDs
            updateEpisodeProgress(at: index, watchedIDs: watchedIDs)
            supersedePersonalWatchEvents(
                title: titles[index],
                seasonNumber: season.number,
                episodeNumber: episode.number
            )
            addActivity(
                description: "marked \(titles[index].title) S\(season.number) E\(episode.number) unwatched",
                titleID: titles[index].id,
                symbol: "arrow.uturn.backward"
            )
        }

        persist()
        syncSharedStateSoon()
    }

    func nextUnwatchedEpisode(
        for title: MediaTitle
    ) -> (season: SeasonSummary, episode: EpisodeSummary)? {
        let watchedIDs = resolvedWatchedEpisodeIDs(for: title)
        for season in regularSeasons(for: title) {
            if let episode = season.episodes.sorted(by: { $0.number < $1.number })
                .first(where: { !watchedIDs.contains($0.id) }) {
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
    func resolvedWatchedEpisodeIDs(for title: MediaTitle) -> Set<EpisodeSummary.ID> {
        if let watchedEpisodeIDs = title.watchedEpisodeIDs { return watchedEpisodeIDs }
        let seasons = regularSeasons(for: title)
        if title.state == .completed {
            return Set(seasons.flatMap(\.episodes).map(\.id))
        }
        guard let progress = title.progress else { return [] }
        let episodeIDs: [EpisodeSummary.ID] = seasons.flatMap { season -> [EpisodeSummary.ID] in
            guard season.number <= progress.season else { return [] }
            if season.number < progress.season { return season.episodes.map(\.id) }
            return season.episodes.filter { $0.number <= progress.episode }.map(\.id)
        }
        return Set(episodeIDs)
    }

    func regularSeasons(for title: MediaTitle) -> [SeasonSummary] {
        (title.seasons ?? [])
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
    }

    func updateEpisodeProgress(at index: Int, watchedIDs: Set<EpisodeSummary.ID>) {
        let seasons = regularSeasons(for: titles[index])
        let regularEpisodes = seasons.flatMap(\.episodes)
        let isComplete = !regularEpisodes.isEmpty && regularEpisodes.allSatisfy { watchedIDs.contains($0.id) }

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

        if isComplete {
            titles[index].state = .completed
        } else if !watchedIDs.isEmpty {
            titles[index].state = .watching
        } else if titles[index].state == .watching || titles[index].state == .completed {
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
