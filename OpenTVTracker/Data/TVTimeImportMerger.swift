import Foundation

enum TVTimeImportMerger {
    static func merge(
        _ archive: TVTimeArchive,
        into current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> LibraryImportPreview {
        let resolved = await resolveTitles(
            archive.entities,
            current: current,
            catalog: catalog,
            region: region
        )
        return mergedPreview(archive, into: current, resolved: resolved)
    }

    private static func resolveTitles(
        _ entities: [TVTimeEntity],
        current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> [String: MediaTitle] {
        var resolved: [String: MediaTitle] = [:]
        var unresolved: [TVTimeEntity] = []

        for entity in entities {
            if let local = current.titles.first(where: { matches($0, entity) }) {
                resolved[entity.identity] = local
            } else {
                unresolved.append(entity)
            }
        }

        for batchStart in stride(from: 0, to: unresolved.count, by: 6) {
            let batch = Array(unresolved[batchStart..<min(batchStart + 6, unresolved.count)])
            await withTaskGroup(of: (String, MediaTitle?).self) { group in
                for entity in batch {
                    group.addTask {
                        let title = await resolve(entity, catalog: catalog, region: region)
                        return (entity.identity, title)
                    }
                }
                for await (identity, title) in group {
                    if let title { resolved[identity] = title }
                }
            }
        }
        return resolved
    }

    private static func mergedPreview(
        _ archive: TVTimeArchive,
        into current: LibrarySnapshot,
        resolved: [String: MediaTitle]
    ) -> LibraryImportPreview {
        var snapshot = current
        var matchedCount = 0
        var addedCount = 0
        var skippedCount = 0
        var watchedEpisodeCount = 0
        var watchEventCount = 0
        let memberID = snapshot.sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        var existingEventIDs = Set((snapshot.sharedSpace.watchEvents ?? []).map(\.id))

        for entity in archive.entities {
            guard var catalogTitle = resolved[entity.identity] else {
                skippedCount += 1
                continue
            }
            let existingIndex = snapshot.titles.firstIndex(where: { matches($0, entity) })
            if let existingIndex {
                catalogTitle = snapshot.titles[existingIndex]
                matchedCount += 1
            } else {
                addedCount += 1
            }

            let applied = apply(
                entity,
                to: &catalogTitle,
                memberID: memberID,
                existingEventIDs: &existingEventIDs
            )
            watchedEpisodeCount += applied.watchedEpisodes
            watchEventCount += applied.watchEvents.count
            skippedCount += applied.unmatchedEpisodes
            snapshot.sharedSpace.watchEvents = (snapshot.sharedSpace.watchEvents ?? []) + applied.watchEvents

            if let existingIndex {
                snapshot.titles[existingIndex] = catalogTitle
            } else {
                snapshot.titles.append(catalogTitle)
            }
            if !snapshot.sharedSpace.titleIDs.contains(catalogTitle.id) {
                snapshot.sharedSpace.titleIDs.append(catalogTitle.id)
            }
        }

        return LibraryImportPreview(
            snapshot: snapshot,
            matchedCount: matchedCount,
            addedCount: addedCount,
            duplicateCount: archive.duplicateCount,
            skippedCount: skippedCount,
            sourceName: "TV Time",
            watchedEpisodeCount: watchedEpisodeCount,
            watchEventCount: watchEventCount
        )
    }

    private static func resolve(
        _ entity: TVTimeEntity,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> MediaTitle? {
        guard !entity.title.isEmpty else { return nil }
        do {
            let results = try await catalog.search(
                MediaSearchQuery(text: entity.title, kind: entity.kind, page: 1, region: region)
            )
            let candidate = results.first { result in
                result.kind == entity.kind
                    && TVTimeCSV.normalizedTitle(result.title) == TVTimeCSV.normalizedTitle(entity.title)
                    && (entity.year == nil || result.year == entity.year)
            } ?? results.first { $0.kind == entity.kind }
            guard let candidate else { return nil }
            return (try? await catalog.title(
                kind: candidate.kind,
                catalogID: candidate.catalogID,
                region: region
            )) ?? candidate
        } catch {
            return nil
        }
    }

    private static func matches(_ title: MediaTitle, _ entity: TVTimeEntity) -> Bool {
        title.kind == entity.kind
            && TVTimeCSV.normalizedTitle(title.title) == TVTimeCSV.normalizedTitle(entity.title)
            && (entity.year == nil || title.year == entity.year)
    }

    private static func apply(
        _ entity: TVTimeEntity,
        to title: inout MediaTitle,
        memberID: String,
        existingEventIDs: inout Set<String>
    ) -> AppliedHistory {
        title.userRating = entity.rating ?? title.userRating
        if entity.isArchived {
            title.state = .paused
            title.personalWatchlist = false
        } else if entity.isForLater || (entity.isFollowed && entity.watches.isEmpty) {
            title.personalWatchlist = true
            if entity.watches.isEmpty { title.state = .planned }
        }

        if title.kind == .movie {
            return applyMovieHistory(
                entity.watches,
                rewatchCount: entity.rewatchCount,
                to: &title,
                memberID: memberID,
                existingEventIDs: &existingEventIDs
            )
        }
        return applyEpisodeHistory(
            entity.watches,
            to: &title,
            memberID: memberID,
            existingEventIDs: &existingEventIDs
        )
    }

    private static func applyMovieHistory(
        _ watches: [TVTimeWatch],
        rewatchCount: Int,
        to title: inout MediaTitle,
        memberID: String,
        existingEventIDs: inout Set<String>
    ) -> AppliedHistory {
        guard !watches.isEmpty else { return AppliedHistory() }
        title.state = .completed
        title.rewatchCount = [
            title.completedRewatches,
            rewatchCount,
            watches.count - 1,
            watches.filter(\.isRewatch).count
        ].max()
        title.lastWatchedAt = watches.compactMap(\.occurredAt).max() ?? title.lastWatchedAt
        let events = TVTimeWatchEventFactory.make(
            watches,
            title: title,
            memberID: memberID,
            existingEventIDs: &existingEventIDs
        )
        return AppliedHistory(watchEvents: events)
    }

    private static func applyEpisodeHistory(
        _ watches: [TVTimeWatch],
        to title: inout MediaTitle,
        memberID: String,
        existingEventIDs: inout Set<String>
    ) -> AppliedHistory {
        let episodeWatches = watches.filter { $0.season != nil && $0.episode != nil }
        guard !episodeWatches.isEmpty else { return AppliedHistory() }
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
        return AppliedHistory(
            watchedEpisodes: episodeWatches.count - unmatchedEpisodes,
            unmatchedEpisodes: unmatchedEpisodes,
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

private struct AppliedHistory {
    var watchedEpisodes = 0
    var unmatchedEpisodes = 0
    var watchEvents: [SharedWatchEvent] = []
}
