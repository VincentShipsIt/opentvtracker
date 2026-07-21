import Foundation

extension AppModel {
    var diaryRecords: [ViewingDiaryRecord] {
        let titlesByID = Dictionary(uniqueKeysWithValues: titles.map { ($0.id, $0) })
        return diaryEntries
            .compactMap { entry -> ViewingDiaryRecord? in
                guard entry.watchedAt != nil, let title = titlesByID[entry.titleID] else { return nil }
                let season = entry.seasonNumber.flatMap { seasonNumber in
                    title.seasons?.first(where: { $0.number == seasonNumber })
                }
                let episode = entry.episodeID.flatMap { episodeID in
                    season?.episodes.first(where: { $0.id == episodeID })
                }
                return ViewingDiaryRecord(entry: entry, title: title, season: season, episode: episode)
            }
            .sorted { lhs, rhs in
                if lhs.entry.watchedAt != rhs.entry.watchedAt {
                    return (lhs.entry.watchedAt ?? .distantPast) > (rhs.entry.watchedAt ?? .distantPast)
                }
                return lhs.id < rhs.id
            }
    }

    var diaryDays: [ViewingDiaryDay] {
        diaryDays(from: diaryRecords)
    }

    func diaryDays(from records: [ViewingDiaryRecord]) -> [ViewingDiaryDay] {
        let calendar = Calendar.autoupdatingCurrent
        let grouped = Dictionary(grouping: records) { record in
            calendar.startOfDay(for: record.entry.watchedAt ?? .distantPast)
        }
        return grouped
            .map { ViewingDiaryDay(date: $0.key, records: $0.value) }
            .sorted { $0.date > $1.date }
    }

    func diaryEntries(for target: ViewingDiaryTarget) -> [ViewingDiaryEntry] {
        diaryEntries
            .filter { entryMatches($0, target: target) }
            .sorted { lhs, rhs in
                if lhs.watchedAt != rhs.watchedAt {
                    return (lhs.watchedAt ?? .distantPast) > (rhs.watchedAt ?? .distantPast)
                }
                return lhs.createdAt > rhs.createdAt
            }
    }

    func diaryRating(for target: ViewingDiaryTarget) -> Double? {
        if target.scope == .title, let rating = mediaTitle(withID: target.titleID)?.userRating {
            return rating
        }
        let entries = diaryEntries(for: target)
        return entries.first(where: { !$0.isRewatch && $0.rating != nil })?.rating
            ?? entries.compactMap(\.rating).first
    }

    func diaryNote(for target: ViewingDiaryTarget) -> String? {
        if target.scope == .title, let note = mediaTitle(withID: target.titleID)?.notes {
            return note
        }
        let entries = diaryEntries(for: target)
        return entries.first(where: { !$0.isRewatch && $0.note?.isEmpty == false })?.note
            ?? entries.compactMap(\.note).first
    }

    func isDiaryTargetWatched(_ target: ViewingDiaryTarget) -> Bool {
        switch target {
        case .title(let titleID):
            return mediaTitle(withID: titleID)?.state == .completed
                || diaryEntries(for: target).contains(where: { $0.watchedAt != nil })
        case .season(let titleID, let seasonID, let seasonNumber):
            if diaryEntries(for: target).contains(where: { $0.watchedAt != nil }) {
                return true
            }
            guard let title = mediaTitle(withID: titleID),
                  let season = title.seasons?.first(where: {
                      $0.id == seasonID && $0.number == seasonNumber
                  }),
                  !season.episodes.isEmpty else {
                return false
            }
            let watchedIDs = resolvedWatchedEpisodeIDs(for: title)
            return season.episodes.allSatisfy { watchedIDs.contains($0.id) }
        case .episode(let titleID, _, let seasonNumber, let episodeID, _):
            return isEpisodeWatched(
                titleID: titleID,
                seasonNumber: seasonNumber,
                episodeID: episodeID
            )
        }
    }

    func updateDiaryRating(_ rating: Double?, for target: ViewingDiaryTarget) {
        let clampedRating = rating.map { min(max($0, 0), 10) }
        updateDiaryMetadata(for: target) { entry in
            entry.rating = clampedRating
        }
        if target.scope == .title, let index = trackableTitleIndex(for: target.titleID) {
            titles[index].userRating = clampedRating
        }
        persist()
    }

    func updateDiaryNote(_ note: String, for target: ViewingDiaryTarget) {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        updateDiaryMetadata(for: target) { entry in
            entry.note = trimmed.isEmpty ? nil : trimmed
        }
        if target.scope == .title, let index = trackableTitleIndex(for: target.titleID) {
            titles[index].notes = trimmed.isEmpty ? nil : trimmed
        }
        persist()
    }

    func updateDiaryWatchDate(_ date: Date?, entryID: ViewingDiaryEntry.ID) {
        guard let index = diaryEntries.firstIndex(where: { $0.id == entryID }) else { return }
        diaryEntries[index].watchedAt = date
        diaryEntries[index].updatedAt = .now
        recalculateLastWatchedAt(for: diaryEntries[index].titleID)
        persist()
    }

    func recordDiaryWatch(
        for target: ViewingDiaryTarget,
        watchedAt: Date,
        isRewatch: Bool
    ) {
        guard let index = trackableTitleIndex(for: target.titleID) else { return }
        switch target {
        case .title:
            appendDiaryWatch(
                title: titles[index],
                watchedAt: watchedAt,
                isRewatch: isRewatch
            )
        case .season:
            return
        case .episode(_, let seasonID, _, let episodeID, _):
            guard let season = titles[index].seasons?.first(where: { $0.id == seasonID }),
                  let episode = season.episodes.first(where: { $0.id == episodeID }) else {
                return
            }
            appendDiaryWatch(
                title: titles[index],
                season: season,
                episode: episode,
                watchedAt: watchedAt,
                isRewatch: isRewatch
            )
        }
        titles[index].lastWatchedAt = max(titles[index].lastWatchedAt ?? .distantPast, watchedAt)
        persist()
    }

    func recordEpisodeRewatch(
        titleID: MediaTitle.ID,
        seasonNumber: Int,
        episodeID: EpisodeSummary.ID,
        watchedAt: Date = .now
    ) {
        guard let index = trackableTitleIndex(for: titleID),
              let season = titles[index].seasons?.first(where: { $0.number == seasonNumber }),
              let episode = season.episodes.first(where: { $0.id == episodeID }),
              isEpisodeWatched(titleID: titleID, seasonNumber: seasonNumber, episodeID: episodeID) else {
            return
        }

        appendDiaryWatch(
            title: titles[index],
            season: season,
            episode: episode,
            watchedAt: watchedAt,
            isRewatch: true
        )
        titles[index].rewatchCount = titles[index].completedRewatches + 1
        titles[index].lastWatchedAt = max(
            titles[index].lastWatchedAt ?? .distantPast,
            watchedAt
        )
        appendWatchEvent(
            title: titles[index],
            kind: .rewatch,
            season: season.number,
            episode: episode.number,
            occurredAt: watchedAt
        )
        addActivity(
            description: "rewatched \(titles[index].title) S\(season.number) E\(episode.number)",
            titleID: titleID,
            symbol: "arrow.clockwise"
        )
        persist()
        syncSharedStateSoon()
    }

    static func resolvedDiaryEntries(from snapshot: LibrarySnapshot) -> [ViewingDiaryEntry] {
        ViewingDiaryMigration.resolvedEntries(from: snapshot)
    }
}

extension AppModel {
    func appendDiaryWatch(
        title: MediaTitle,
        season: SeasonSummary? = nil,
        episode: EpisodeSummary? = nil,
        watchedAt: Date,
        isRewatch: Bool,
        id: ViewingDiaryEntry.ID = UUID().uuidString,
        rating: Double? = nil
    ) {
        guard !diaryEntries.contains(where: { $0.id == id }) else { return }
        let target = diaryTarget(title: title, season: season, episode: episode)

        if !isRewatch,
           let metadataIndex = diaryEntries.firstIndex(where: {
               entryMatches($0, target: target)
                   && $0.watchedAt == nil
                   && !$0.isRewatch
           }) {
            diaryEntries[metadataIndex].watchedAt = watchedAt
            diaryEntries[metadataIndex].rating = rating ?? diaryEntries[metadataIndex].rating
            diaryEntries[metadataIndex].updatedAt = .now
            return
        }

        diaryEntries.append(
            ViewingDiaryEntry(
                id: id,
                titleID: target.titleID,
                scope: target.scope,
                seasonNumber: target.seasonNumber,
                episodeID: target.episodeID,
                episodeNumber: target.episodeNumber,
                watchedAt: watchedAt,
                rating: rating.map { min(max($0, 0), 10) },
                note: nil,
                isRewatch: isRewatch,
                createdAt: watchedAt,
                updatedAt: watchedAt
            )
        )
    }

    func clearEpisodeDiaryHistory(
        titleID: MediaTitle.ID,
        seasonNumber: Int,
        episodeID: EpisodeSummary.ID
    ) {
        let matchingIndices = diaryEntries.indices.filter { index in
            diaryEntries[index].titleID == titleID
                && diaryEntries[index].scope == .episode
                && diaryEntries[index].seasonNumber == seasonNumber
                && diaryEntries[index].episodeID == episodeID
        }
        for index in matchingIndices.reversed() {
            if diaryEntries[index].rating != nil || diaryEntries[index].note?.isEmpty == false {
                diaryEntries[index].watchedAt = nil
                diaryEntries[index].isRewatch = false
                diaryEntries[index].updatedAt = .now
            } else {
                diaryEntries.remove(at: index)
            }
        }
        recalculateLastWatchedAt(for: titleID)
    }

    func recordTitleRewatchInDiary(_ title: MediaTitle, watchedAt: Date = .now) {
        appendDiaryWatch(title: title, watchedAt: watchedAt, isRewatch: true)
    }

    func synchronizeTitleDiaryRating(_ rating: Double?, titleID: MediaTitle.ID) {
        updateDiaryMetadata(for: .title(titleID: titleID)) { entry in
            entry.rating = rating
        }
    }

    func synchronizeTitleDiaryNote(_ note: String?, titleID: MediaTitle.ID) {
        updateDiaryMetadata(for: .title(titleID: titleID)) { entry in
            entry.note = note
        }
    }
}

private extension AppModel {
    func updateDiaryMetadata(
        for target: ViewingDiaryTarget,
        update: (inout ViewingDiaryEntry) -> Void
    ) {
        if let index = diaryEntries.firstIndex(where: {
            entryMatches($0, target: target) && !$0.isRewatch
        }) {
            update(&diaryEntries[index])
            diaryEntries[index].updatedAt = .now
            if !diaryEntries[index].hasPrivateContent {
                diaryEntries.remove(at: index)
            }
            return
        }

        let now = Date.now
        var entry = ViewingDiaryEntry(
            id: UUID().uuidString,
            titleID: target.titleID,
            scope: target.scope,
            seasonNumber: target.seasonNumber,
            episodeID: target.episodeID,
            episodeNumber: target.episodeNumber,
            watchedAt: nil,
            rating: nil,
            note: nil,
            isRewatch: false,
            createdAt: now,
            updatedAt: now
        )
        update(&entry)
        if entry.hasPrivateContent { diaryEntries.append(entry) }
    }

    func entryMatches(_ entry: ViewingDiaryEntry, target: ViewingDiaryTarget) -> Bool {
        entry.titleID == target.titleID
            && entry.scope == target.scope
            && entry.seasonNumber == target.seasonNumber
            && entry.episodeID == target.episodeID
    }

    func diaryTarget(
        title: MediaTitle,
        season: SeasonSummary?,
        episode: EpisodeSummary?
    ) -> ViewingDiaryTarget {
        if let season, let episode {
            return .episode(
                titleID: title.id,
                seasonID: season.id,
                seasonNumber: season.number,
                episodeID: episode.id,
                episodeNumber: episode.number
            )
        }
        return .title(titleID: title.id)
    }

    func recalculateLastWatchedAt(for titleID: MediaTitle.ID) {
        guard let index = titles.firstIndex(where: { $0.id == titleID }) else { return }
        titles[index].lastWatchedAt = diaryEntries
            .lazy
            .filter { $0.titleID == titleID }
            .compactMap(\.watchedAt)
            .max()
    }
}
