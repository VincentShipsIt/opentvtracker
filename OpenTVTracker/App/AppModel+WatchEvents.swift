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

    var completedTitlesByRecency: [MediaTitle] {
        titles(in: .completed).sorted(by: isMoreRecentlyWatched)
    }

    var watchlistTitlesByRecency: [MediaTitle] {
        titles(in: .planned).sorted(by: isMoreRecentlyWatched)
    }

    func markWatched(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id), titles[index].state != .completed else { return }

        let regularSeasons = (titles[index].seasons ?? [])
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
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
        titles[index].lastWatchedAt = .now
        appendWatchEvent(title: titles[index], kind: .watched)
        persist()
        refreshRecommendationsSoon()
    }

    func appendWatchEvent(
        title: MediaTitle,
        kind: WatchEventKind,
        memberID: SpaceMember.ID? = nil,
        season: Int? = nil,
        episode: Int? = nil,
        supersedesEventID: String? = nil
    ) {
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
    }

    private func isMoreRecentlyWatched(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        if lhs.lastWatchedAt != rhs.lastWatchedAt {
            return (lhs.lastWatchedAt ?? .distantPast) > (rhs.lastWatchedAt ?? .distantPast)
        }
        if lhs.year != rhs.year { return lhs.year > rhs.year }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
