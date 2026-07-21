import Foundation

enum TVTimeImportMerger {
    static func merge(
        _ archive: TVTimeArchive,
        into current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async -> LibraryImportPreview {
        let resolved = await TVTimeCatalogResolver.resolveTitles(
            archive.entities,
            current: current,
            catalog: catalog,
            region: region
        )
        return mergedPreview(
            archive,
            into: current,
            automaticResolution: resolved,
            manualResolutions: [:]
        )
    }

    static func mergedPreview(
        _ archive: TVTimeArchive,
        into current: LibrarySnapshot,
        automaticResolution: TVTimeTitleResolution,
        manualResolutions: [ImportResolutionIssue.ID: MediaTitle]
    ) -> LibraryImportPreview {
        var state = PreviewMergeState(snapshot: current)
        for entity in archive.entities {
            merge(
                entity,
                automaticResolution: automaticResolution,
                manualResolutions: manualResolutions,
                state: &state
            )
        }
        state.snapshot.importResolutionAliases = state.aliases
        state.snapshot.importResolutionSeasonOverrides = state.seasonOverrides
        let remainingIssues = remainingIssues(
            automaticResolution,
            manualResolutions: manualResolutions
        )

        return LibraryImportPreview(
            snapshot: state.snapshot,
            matchedCount: state.matchedCount,
            addedCount: state.addedCount,
            duplicateCount: archive.duplicateCount,
            skippedCount: state.skippedCount,
            sourceName: "TV Time",
            watchedEpisodeCount: state.watchedEpisodeCount,
            watchEventCount: state.watchEventCount,
            importNotice: importNotice(for: remainingIssues),
            resolutionIssues: remainingIssues
        )
    }

    private static func merge(
        _ entity: TVTimeEntity,
        automaticResolution: TVTimeTitleResolution,
        manualResolutions: [ImportResolutionIssue.ID: MediaTitle],
        state: inout PreviewMergeState
    ) {
        guard let resolved = resolvedTitle(
            for: entity,
            automaticResolution: automaticResolution,
            manualResolutions: manualResolutions
        ) else {
            state.skippedCount += 1
            return
        }
        var title = resolved.title
        let aliasedTitleID = state.aliases[entity.identity]
        let existingIndex = aliasedTitleID.flatMap { alias in
            state.snapshot.titles.firstIndex { $0.id == alias }
        } ?? state.snapshot.titles.firstIndex {
            $0.id == title.id
        } ?? state.snapshot.titles.firstIndex {
            CatalogImportMatcher.matches($0, entity: entity)
        }
        if let existingIndex {
            title = state.snapshot.titles[existingIndex]
            state.matchedCount += 1
        } else {
            state.addedCount += 1
        }
        let applied = apply(
            entity,
            to: &title,
            memberID: state.memberID,
            existingEventIDs: &state.existingEventIDs,
            seasonNumberOverride: resolved.seasonNumberOverride
        )
        state.apply(applied)
        if let existingIndex {
            state.snapshot.titles[existingIndex] = title
        } else {
            state.snapshot.titles.append(title)
        }
        state.record(title, for: entity, seasonNumberOverride: resolved.seasonNumberOverride)
    }

    private static func resolvedTitle(
        for entity: TVTimeEntity,
        automaticResolution: TVTimeTitleResolution,
        manualResolutions: [ImportResolutionIssue.ID: MediaTitle]
    ) -> CatalogResolvedTitle? {
        if let manual = manualResolutions[entity.identity] {
            let seasonNumber = CatalogImportMatcher.safeAnimeSeasonNumber(in: entity.title)
            let safeOverride = seasonNumber.flatMap { number in
                manual.seasons?.contains(where: { $0.number == number }) == true ? number : nil
            }
            return CatalogResolvedTitle(title: manual, seasonNumberOverride: safeOverride)
        }
        return automaticResolution.resolved[entity.identity]
    }

    private static func remainingIssues(
        _ resolution: TVTimeTitleResolution,
        manualResolutions: [ImportResolutionIssue.ID: MediaTitle]
    ) -> [ImportResolutionIssue] {
        resolution.issues.values
            .filter { manualResolutions[$0.id] == nil }
            .sorted { $0.displayTitle.localizedStandardCompare($1.displayTitle) == .orderedAscending }
    }

    private static func importNotice(for issues: [ImportResolutionIssue]) -> String? {
        guard !issues.isEmpty else { return nil }
        let noun = issues.count == 1 ? "match needs" : "matches need"
        return "\(issues.count) catalog \(noun) manual confirmation. Unresolved records stay out of this preview instead of being skipped silently."
    }

    private static func apply(
        _ entity: TVTimeEntity,
        to title: inout MediaTitle,
        memberID: String,
        existingEventIDs: inout Set<String>,
        seasonNumberOverride: Int?
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
            existingEventIDs: &existingEventIDs,
            seasonNumberOverride: seasonNumberOverride
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
        existingEventIDs: inout Set<String>,
        seasonNumberOverride: Int?
    ) -> AppliedHistory {
        let episodeWatches = episodeWatches(
            watches,
            seasonNumberOverride: seasonNumberOverride
        )
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

    private static func episodeWatches(
        _ watches: [TVTimeWatch],
        seasonNumberOverride: Int?
    ) -> [TVTimeWatch] {
        watches.compactMap { watch in
            guard watch.season != nil, watch.episode != nil else { return nil }
            guard let seasonNumberOverride, watch.season == 1 else { return watch }
            var mapped = watch
            mapped.season = seasonNumberOverride
            return mapped
        }
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

private struct PreviewMergeState {
    var snapshot: LibrarySnapshot
    var matchedCount = 0
    var addedCount = 0
    var skippedCount = 0
    var watchedEpisodeCount = 0
    var watchEventCount = 0
    let memberID: String
    var existingEventIDs: Set<String>
    var aliases: [String: MediaTitle.ID]
    var seasonOverrides: [String: Int]

    init(snapshot: LibrarySnapshot) {
        self.snapshot = snapshot
        memberID = snapshot.sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        existingEventIDs = Set((snapshot.sharedSpace.watchEvents ?? []).map(\.id))
        aliases = snapshot.importResolutionAliases ?? [:]
        seasonOverrides = snapshot.importResolutionSeasonOverrides ?? [:]
    }

    mutating func apply(_ applied: AppliedHistory) {
        watchedEpisodeCount += applied.watchedEpisodes
        watchEventCount += applied.watchEvents.count
        skippedCount += applied.unmatchedEpisodes
        snapshot.sharedSpace.watchEvents =
            (snapshot.sharedSpace.watchEvents ?? []) + applied.watchEvents
    }

    mutating func record(
        _ title: MediaTitle,
        for entity: TVTimeEntity,
        seasonNumberOverride: Int?
    ) {
        if !snapshot.sharedSpace.titleIDs.contains(title.id) {
            snapshot.sharedSpace.titleIDs.append(title.id)
        }
        aliases[entity.identity] = title.id
        if let seasonNumberOverride {
            seasonOverrides[entity.identity] = seasonNumberOverride
        } else {
            seasonOverrides.removeValue(forKey: entity.identity)
        }
    }
}
