import Foundation

extension AppModel {
    func markNextWatched(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        let watchedAt = Date.now

        if titles[index].kind == .movie {
            guard !titles[index].state.isCurrentViewingComplete else { return }
            titles[index].state = .completed
            titles[index].personalWatchlist = false
        } else if let next = nextUnwatchedEpisode(for: titles[index]) {
            setEpisodeWatched(
                true,
                titleID: id,
                seasonNumber: next.season.number,
                episodeID: next.episode.id
            )
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
            appendDiaryWatch(title: titles[index], watchedAt: watchedAt, isRewatch: false)
        }
        appendWatchEvent(title: titles[index], kind: .watched, occurredAt: watchedAt)
        addActivity(
            description: "watched \(titles[index].title) \(titles[index].progress?.label ?? "")",
            titleID: titles[index].id
        )
        persist()
        syncSharedStateSoon()
    }

    var recentlyWatchedTitles: [MediaTitle] {
        titles
            .filter { $0.lastWatchedAt != nil }
            .sorted(by: isMoreRecentlyWatched)
    }

    var watchingTitlesByRecency: [MediaTitle] {
        titles(in: .watching).sorted(by: isMoreRecentlyWatched)
    }

    var caughtUpTitlesByRecency: [MediaTitle] {
        titles(in: .caughtUp).sorted(by: isMoreRecentlyWatched)
    }

    var completedTitlesByRecency: [MediaTitle] {
        titles(in: .completed).sorted(by: isMoreRecentlyWatched)
    }

    var watchlistTitlesByRecency: [MediaTitle] {
        titles(in: .planned).sorted(by: isMoreRecentlyWatched)
    }

    func markWatched(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        if titles[index].kind == .movie {
            guard !titles[index].state.isCurrentViewingComplete else { return }
        } else if titles[index].state.isCurrentViewingComplete {
            let watchedIDs = resolvedWatchedEpisodeIDs(for: titles[index])
            guard releasedEpisodes(for: titles[index]).contains(where: { !watchedIDs.contains($0.id) }) else {
                return
            }
        }

        let watchedAt = Date.now
        let previouslyWatchedEpisodeIDs = resolvedWatchedEpisodeIDs(for: titles[index])
        let releasedSeasons = releasedRegularSeasons(for: titles[index])
        if titles[index].kind == .series, !releasedSeasons.isEmpty {
            titles[index].watchedEpisodeIDs = Set(releasedSeasons.flatMap(\.episodes).map(\.id))
            if let lastSeason = releasedSeasons.last {
                titles[index].progress = EpisodeProgress(
                    season: lastSeason.number,
                    episode: lastSeason.episodes.count,
                    totalEpisodes: lastSeason.episodes.count
                )
            }
        }

        titles[index].state = finishedState(for: titles[index])
        titles[index].personalWatchlist = false
        titles[index].lastWatchedAt = watchedAt
        appendCompletedWatchDiary(
            title: titles[index],
            releasedSeasons: releasedSeasons,
            previouslyWatchedEpisodeIDs: previouslyWatchedEpisodeIDs,
            watchedAt: watchedAt
        )
        appendWatchEvent(title: titles[index], kind: .watched, occurredAt: watchedAt)
        persist()
        refreshRecommendationsSoon()
    }

    @discardableResult
    func appendWatchEvent(
        title: MediaTitle,
        kind: WatchEventKind,
        memberID: SpaceMember.ID? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        supersedesEventID: String? = nil,
        occurredAt: Date = .now
    ) -> SharedWatchEvent {
        let resolvedMemberID = memberID ?? sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let event = SharedWatchEvent(
            id: UUID().uuidString,
            titleID: title.id,
            memberID: resolvedMemberID,
            kind: kind,
            season: season ?? title.progress?.season,
            episode: episode ?? title.progress?.episode,
            occurredAt: occurredAt,
            supersedesEventID: supersedesEventID
        )
        var events = sharedSpace.watchEvents ?? []
        events.append(event)
        sharedSpace.watchEvents = events
        return event
    }

    func resolvedWatchedEpisodeIDs(for title: MediaTitle) -> Set<EpisodeSummary.ID> {
        if let watchedEpisodeIDs = title.watchedEpisodeIDs { return watchedEpisodeIDs }
        if title.progress != nil { return title.episodeIDsThroughProgress }
        if title.state.isCurrentViewingComplete {
            return Set(releasedEpisodes(for: title).map(\.id))
        }
        return []
    }

    private func isMoreRecentlyWatched(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        if lhs.lastWatchedAt != rhs.lastWatchedAt {
            return (lhs.lastWatchedAt ?? .distantPast) > (rhs.lastWatchedAt ?? .distantPast)
        }
        if lhs.year != rhs.year { return lhs.year > rhs.year }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}

private extension AppModel {
    func releasedRegularSeasons(for title: MediaTitle) -> [SeasonSummary] {
        let releasedIDs = Set(releasedEpisodes(for: title).map(\.id))
        return regularSeasons(for: title).compactMap { season in
            let episodes = season.episodes.filter { releasedIDs.contains($0.id) }
            guard !episodes.isEmpty else { return nil }
            return SeasonSummary(
                id: season.id,
                number: season.number,
                title: season.title,
                episodes: episodes
            )
        }
    }

    func appendCompletedWatchDiary(
        title: MediaTitle,
        releasedSeasons: [SeasonSummary],
        previouslyWatchedEpisodeIDs: Set<EpisodeSummary.ID>,
        watchedAt: Date
    ) {
        guard title.kind == .series else {
            appendDiaryWatch(title: title, watchedAt: watchedAt, isRewatch: false)
            return
        }
        for season in releasedSeasons {
            for episode in season.episodes where !previouslyWatchedEpisodeIDs.contains(episode.id) {
                appendDiaryWatch(
                    title: title,
                    season: season,
                    episode: episode,
                    watchedAt: watchedAt,
                    isRewatch: false
                )
            }
        }
    }
}
