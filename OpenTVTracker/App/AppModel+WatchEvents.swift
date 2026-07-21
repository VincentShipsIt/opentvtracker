import Foundation

extension AppModel {
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

        let regularSeasons = regularSeasons(for: titles[index])
        if titles[index].kind == .series, !regularSeasons.isEmpty {
            let releasedIDs = Set(releasedEpisodes(for: titles[index]).map(\.id))
            let releasedSeasons = regularSeasons.compactMap { season -> SeasonSummary? in
                let episodes = season.episodes.filter { releasedIDs.contains($0.id) }
                guard !episodes.isEmpty else { return nil }
                return SeasonSummary(
                    id: season.id,
                    number: season.number,
                    title: season.title,
                    episodes: episodes
                )
            }
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
        titles[index].lastWatchedAt = .now
        appendWatchEvent(title: titles[index], kind: .watched)
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
        supersedesEventID: String? = nil
    ) -> SharedWatchEvent {
        let resolvedMemberID = memberID ?? sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let event = SharedWatchEvent(
            id: UUID().uuidString,
            titleID: title.id,
            memberID: resolvedMemberID,
            kind: kind,
            season: season ?? title.progress?.season,
            episode: episode ?? title.progress?.episode,
            occurredAt: .now,
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
