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

    /// Marks a whole title watched: a movie in one go, a series down to its last aired episode.
    func markWatched(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }

        // A series with episode data is recorded episode by episode, through the same path the
        // season and episode toggles use, so the diary, the progress, the finished state and —
        // the reason this changed — the analytics all match what watching it would have
        // produced. Marking the flags directly and appending one series-scoped event left
        // analytics crediting a whole show with a single episode's runtime.
        if titles[index].kind == .series, !releasedEpisodes(for: titles[index]).isEmpty {
            guard markAllReleasedEpisodesWatched(titleID: id) else { return }
            // Not covered by the episode path, which has no opinion on the watchlist.
            titles[index].personalWatchlist = false
            persist()
            return
        }

        guard !titles[index].state.isCurrentViewingComplete else { return }
        let watchedAt = Date.now
        titles[index].state = finishedState(for: titles[index])
        titles[index].personalWatchlist = false
        titles[index].lastWatchedAt = watchedAt
        appendDiaryWatch(title: titles[index], watchedAt: watchedAt, isRewatch: false)
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

