import Foundation

extension AppModel {
    func markNextWatched(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        let watchedAt = Date.now

        if titles[index].kind == .movie {
            guard titles[index].state != .completed else { return }
            titles[index].state = .completed
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
            titles[index].state = progress.episode == progress.totalEpisodes ? .completed : .watching
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

    var completedTitlesByRecency: [MediaTitle] {
        titles(in: .completed).sorted(by: isMoreRecentlyWatched)
    }

    var watchlistTitlesByRecency: [MediaTitle] {
        titles(in: .planned).sorted(by: isMoreRecentlyWatched)
    }

    func markWatched(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id), titles[index].state != .completed else { return }
        let watchedAt = Date.now

        let regularSeasons = (titles[index].seasons ?? [])
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
        let previouslyWatchedEpisodeIDs = Set(regularSeasons.flatMap { season in
            season.episodes.filter { episode in
                isEpisodeWatched(
                    titleID: id,
                    seasonNumber: season.number,
                    episodeID: episode.id
                )
            }.map(\.id)
        })
        if titles[index].kind == .series, !regularSeasons.isEmpty {
            titles[index].watchedEpisodeIDs = Set(regularSeasons.flatMap(\.episodes).map(\.id))
            if let lastSeason = regularSeasons.last {
                titles[index].progress = EpisodeProgress(
                    season: lastSeason.number,
                    episode: lastSeason.episodes.count,
                    totalEpisodes: lastSeason.episodes.count
                )
            }
        }

        titles[index].state = .completed
        titles[index].personalWatchlist = false
        titles[index].lastWatchedAt = watchedAt
        if titles[index].kind == .movie {
            appendDiaryWatch(title: titles[index], watchedAt: watchedAt, isRewatch: false)
        } else {
            for season in regularSeasons {
                for episode in season.episodes where !previouslyWatchedEpisodeIDs.contains(episode.id) {
                    appendDiaryWatch(
                        title: titles[index],
                        season: season,
                        episode: episode,
                        watchedAt: watchedAt,
                        isRewatch: false
                    )
                }
            }
        }
        appendWatchEvent(title: titles[index], kind: .watched, occurredAt: watchedAt)
        persist()
        refreshRecommendationsSoon()
    }

    func appendWatchEvent(
        title: MediaTitle,
        kind: WatchEventKind,
        memberID: SpaceMember.ID? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        supersedesEventID: String? = nil,
        occurredAt: Date = .now
    ) {
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
    }

    private func isMoreRecentlyWatched(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        if lhs.lastWatchedAt != rhs.lastWatchedAt {
            return (lhs.lastWatchedAt ?? .distantPast) > (rhs.lastWatchedAt ?? .distantPast)
        }
        if lhs.year != rhs.year { return lhs.year > rhs.year }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
