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
        var accumulator = TVTimeMergeAccumulator(snapshot: current)

        for entity in archive.entities {
            accumulator.merge(entity, resolvedTitle: resolved[entity.identity])
        }
        return accumulator.preview(duplicateCount: archive.duplicateCount)
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

    static func matches(_ title: MediaTitle, _ entity: TVTimeEntity) -> Bool {
        title.kind == entity.kind
            && TVTimeCSV.normalizedTitle(title.title) == TVTimeCSV.normalizedTitle(entity.title)
            && (entity.year == nil || title.year == entity.year)
    }

    static func apply(
        _ entity: TVTimeEntity,
        to title: inout MediaTitle,
        memberID: String,
        deduplicator: inout TVTimeHistoryDeduplicator
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
                entity,
                to: &title,
                memberID: memberID,
                deduplicator: &deduplicator
            )
        }
        return applyEpisodeHistory(
            entity.watches,
            to: &title,
            memberID: memberID,
            deduplicator: &deduplicator
        )
    }

    private static func applyMovieHistory(
        _ entity: TVTimeEntity,
        to title: inout MediaTitle,
        memberID: String,
        deduplicator: inout TVTimeHistoryDeduplicator
    ) -> AppliedHistory {
        let watches = entity.watches
        guard !watches.isEmpty else { return AppliedHistory() }
        title.state = .completed
        title.rewatchCount = [
            title.completedRewatches,
            entity.rewatchCount,
            watches.count - 1,
            watches.filter(\.isRewatch).count
        ].max()
        title.lastWatchedAt = watches.compactMap(\.occurredAt).max() ?? title.lastWatchedAt
        let events = TVTimeWatchEventFactory.make(
            watches,
            title: title,
            memberID: memberID,
            existingEventIDs: &deduplicator.eventIDs
        )
        let diaryEntries = TVTimeDiaryEntryFactory.make(
            watches,
            title: title,
            fallbackRating: entity.rating,
            existingDiaryIDs: &deduplicator.diaryIDs
        )
        return AppliedHistory(watchEvents: events, diaryEntries: diaryEntries)
    }

    private static func applyEpisodeHistory(
        _ watches: [TVTimeWatch],
        to title: inout MediaTitle,
        memberID: String,
        deduplicator: inout TVTimeHistoryDeduplicator
    ) -> AppliedHistory {
        let episodeWatches = watches.filter { $0.season != nil && $0.episode != nil }
        guard !episodeWatches.isEmpty else { return AppliedHistory() }
        let unmatchedEpisodes = applyEpisodeProgress(episodeWatches, to: &title)

        let events = TVTimeWatchEventFactory.make(
            episodeWatches,
            title: title,
            memberID: memberID,
            existingEventIDs: &deduplicator.eventIDs
        )
        let diaryEntries = TVTimeDiaryEntryFactory.make(
            episodeWatches,
            title: title,
            fallbackRating: nil,
            existingDiaryIDs: &deduplicator.diaryIDs
        )
        return AppliedHistory(
            watchedEpisodes: episodeWatches.count - unmatchedEpisodes,
            unmatchedEpisodes: unmatchedEpisodes,
            watchEvents: events,
            diaryEntries: diaryEntries
        )
    }

    private static func applyEpisodeProgress(
        _ watches: [TVTimeWatch],
        to title: inout MediaTitle
    ) -> Int {
        var watchedIDs = title.watchedEpisodeIDs ?? []
        var unmatchedEpisodes = 0
        for watch in watches {
            guard let episode = matchedEpisode(for: watch, in: title) else {
                unmatchedEpisodes += 1
                continue
            }
            watchedIDs.insert(episode.id)
        }

        title.watchedEpisodeIDs = watchedIDs
        title.lastWatchedAt = watches.compactMap(\.occurredAt).max() ?? title.lastWatchedAt
        if let latest = watches.max(by: { watchPosition($0) < watchPosition($1) }),
           let seasonNumber = latest.season, let episodeNumber = latest.episode {
            let total = title.seasons?.first(where: { $0.number == seasonNumber })?.episodes.count ?? episodeNumber
            title.progress = EpisodeProgress(
                season: seasonNumber,
                episode: episodeNumber,
                totalEpisodes: max(total, 1)
            )
        }

        let releasedIDs = releasedEpisodeIDs(in: title)
        title.state = !releasedIDs.isEmpty && releasedIDs.isSubset(of: watchedIDs) ? .completed : .watching
        return unmatchedEpisodes
    }

    private static func matchedEpisode(for watch: TVTimeWatch, in title: MediaTitle) -> EpisodeSummary? {
        guard let seasonNumber = watch.season, let episodeNumber = watch.episode else { return nil }
        return title.seasons?
            .first(where: { $0.number == seasonNumber })?
            .episodes.first(where: { $0.number == episodeNumber })
    }

    private static func watchPosition(_ watch: TVTimeWatch) -> (Int, Int) {
        (watch.season ?? 0, watch.episode ?? 0)
    }

    private static func releasedEpisodeIDs(in title: MediaTitle) -> Set<EpisodeSummary.ID> {
        Set((title.seasons ?? []).flatMap { season in
            guard season.number > 0 else { return [EpisodeSummary.ID]() }
            return season.episodes.compactMap { episode in
                guard let airDate = episode.airDate, airDate <= Date() else { return nil }
                return episode.id
            }
        })
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
            let kind: WatchEventKind = watch.isRewatch ? .rewatch : .watched
            let eventID = identifier(for: watch, titleID: title.id)
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

    static func identifier(for watch: TVTimeWatch, titleID: MediaTitle.ID) -> String {
        let timestamp = Int64((watch.occurredAt ?? .distantPast).timeIntervalSince1970)
        let kind: WatchEventKind = watch.isRewatch ? .rewatch : .watched
        return [
            "tvtime", titleID, String(watch.season ?? 0), String(watch.episode ?? 0),
            String(timestamp), kind.rawValue
        ].joined(separator: ":")
    }
}

private enum TVTimeDiaryEntryFactory {
    static func make(
        _ watches: [TVTimeWatch],
        title: MediaTitle,
        fallbackRating: Double?,
        existingDiaryIDs: inout Set<String>
    ) -> [ViewingDiaryEntry] {
        let fallbackIndex = watches.firstIndex { $0.occurredAt != nil && !$0.isRewatch }
            ?? watches.firstIndex { $0.occurredAt != nil }
        watches.enumerated().compactMap { index, watch in
            guard let watchedAt = watch.occurredAt else { return nil }
            let id = "diary:\(TVTimeWatchEventFactory.identifier(for: watch, titleID: title.id))"
            guard existingDiaryIDs.insert(id).inserted else { return nil }

            let season = watch.season.flatMap { seasonNumber in
                title.seasons?.first(where: { $0.number == seasonNumber })
            }
            let episode = watch.episode.flatMap { episodeNumber in
                season?.episodes.first(where: { $0.number == episodeNumber })
            }
            if title.kind == .series, episode == nil { return nil }
            let rawRating: Double?
            if let rating = watch.rating {
                rawRating = rating
            } else if index == fallbackIndex {
                rawRating = fallbackRating
            } else {
                rawRating = nil
            }
            let resolvedRating = rawRating.map { min(max($0, 0), 10) }

            return ViewingDiaryEntry(
                id: id,
                titleID: title.id,
                scope: episode == nil ? .title : .episode,
                seasonNumber: watch.season,
                episodeID: episode?.id,
                episodeNumber: watch.episode,
                watchedAt: watchedAt,
                rating: resolvedRating,
                note: nil,
                isRewatch: watch.isRewatch,
                createdAt: watchedAt,
                updatedAt: watchedAt
            )
        }
    }
}

struct AppliedHistory {
    var watchedEpisodes = 0
    var unmatchedEpisodes = 0
    var watchEvents: [SharedWatchEvent] = []
    var diaryEntries: [ViewingDiaryEntry] = []
}
