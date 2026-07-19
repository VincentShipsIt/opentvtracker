import Foundation

extension AppModel {
    var upNext: [MediaTitle] {
        upNextTitles(at: .now)
    }

    var activeUpNext: [MediaTitle] {
        let staleIDs = Set(staleUpNext.map(\.id))
        return upNext.filter { !staleIDs.contains($0.id) }
    }

    var staleUpNext: [MediaTitle] {
        staleUpNext(at: .now)
    }

    func upNextTitles(at date: Date) -> [MediaTitle] {
        titles
            .filter { isUpNextCandidate($0, at: date) && !$0.isSnoozed(at: date) }
            .sorted(by: isHigherUpNextPriority)
    }

    func staleUpNext(at date: Date) -> [MediaTitle] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: date) ?? date
        return upNextTitles(at: date).filter { title in
            title.state == .watching
                && title.isUpNextPinned != true
                && title.lastWatchedAt.map { $0 < cutoff } == true
        }
    }

    func setUpNextPinned(_ pinned: Bool, for id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].isUpNextPinned = pinned ? true : nil
        if pinned {
            titles[index].upNextSnoozedUntil = nil
        }
        persist()
    }

    func snoozeUpNext(_ id: MediaTitle.ID, until date: Date?) {
        guard let index = trackableTitleIndex(for: id) else { return }
        titles[index].upNextSnoozedUntil = date
        persist()
    }

    func moveUpNextLower(_ id: MediaTitle.ID) {
        guard let index = trackableTitleIndex(for: id) else { return }
        let lowestOrder = titles.compactMap(\.upNextManualOrder).max() ?? 0
        titles[index].upNextManualOrder = lowestOrder + 1
        persist()
    }

    func migratedTrackingTitles(
        _ values: [MediaTitle],
        fromSchemaVersion schemaVersion: Int?
    ) -> [MediaTitle] {
        values.map { title in
            refreshedTrackingTitle(
                title.migratedTrackingState(fromSchemaVersion: schemaVersion)
            )
        }
    }

    func refreshedTrackingTitle(_ title: MediaTitle, at date: Date = .now) -> MediaTitle {
        guard title.kind == .series else { return title }
        var result = title

        if result.state == .caughtUp {
            if hasReleasedUnwatchedEpisode(result, at: date) {
                result.state = .watching
            } else if result.resolvedSeriesLifecycle == .ended {
                result.state = .completed
            }
        }

        return result
    }

    func finishedState(for title: MediaTitle) -> WatchState {
        title.finishedWatchState
    }

    func trackingStateAfterEpisodeUpdate(
        for title: MediaTitle,
        watchedIDs: Set<EpisodeSummary.ID>,
        at date: Date = .now
    ) -> WatchState {
        let released = releasedEpisodes(for: title, at: date)
        guard !released.isEmpty else {
            return watchedIDs.isEmpty ? .planned : .watching
        }
        return released.allSatisfy { watchedIDs.contains($0.id) }
            ? finishedState(for: title)
            : .watching
    }

    func releasedEpisodes(for title: MediaTitle, at date: Date = .now) -> [EpisodeSummary] {
        (title.seasons ?? [])
            .filter { $0.number > 0 }
            .flatMap(\.episodes)
            .filter { episode in
                guard let airDate = episode.airDate else { return true }
                return airDate <= date
            }
    }

    private func isUpNextCandidate(_ title: MediaTitle, at date: Date) -> Bool {
        if title.state == .watching { return true }
        guard title.kind == .movie,
              title.state == .planned,
              title.isOnPersonalWatchlist,
              let releaseDate = title.releaseDate else {
            return false
        }
        return releaseDate <= date
    }

    private func hasReleasedUnwatchedEpisode(_ title: MediaTitle, at date: Date) -> Bool {
        let watchedIDs = inferredWatchedEpisodeIDs(for: title, at: date)
        return releasedEpisodes(for: title, at: date).contains { !watchedIDs.contains($0.id) }
    }

    private func inferredWatchedEpisodeIDs(for title: MediaTitle, at date: Date) -> Set<EpisodeSummary.ID> {
        if let watchedEpisodeIDs = title.watchedEpisodeIDs { return watchedEpisodeIDs }
        if title.progress != nil {
            return episodeIDsThroughProgress(for: title)
        }
        return title.state.isCurrentViewingComplete
            ? Set(releasedEpisodes(for: title, at: date).map(\.id))
            : []
    }

    private func isHigherUpNextPriority(_ lhs: MediaTitle, _ rhs: MediaTitle) -> Bool {
        let lhsIsPinned = lhs.isUpNextPinned == true
        let rhsIsPinned = rhs.isUpNextPinned == true
        if lhsIsPinned != rhsIsPinned {
            return lhsIsPinned
        }

        let lhsOrder = lhs.upNextManualOrder ?? 0
        let rhsOrder = rhs.upNextManualOrder ?? 0
        if lhsOrder != rhsOrder { return lhsOrder < rhsOrder }

        if lhs.state != rhs.state { return lhs.state == .watching }

        let lhsDate = lhs.nextEpisodeAirDate ?? lhs.releaseDate
        let rhsDate = rhs.nextEpisodeAirDate ?? rhs.releaseDate
        switch (lhsDate, rhsDate) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate < rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            break
        }

        if lhs.lastWatchedAt != rhs.lastWatchedAt {
            return (lhs.lastWatchedAt ?? .distantPast) > (rhs.lastWatchedAt ?? .distantPast)
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }
}
