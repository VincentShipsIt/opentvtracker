import Foundation

enum TraktSyncEngine {
    static func plan(
        local snapshot: LibrarySnapshot,
        remote: TraktRemoteSnapshot
    ) -> TraktSyncPlan {
        let previousState = snapshot.traktSyncState ?? .empty
        var merged = snapshot
        var nextState = previousState
        addMissingTitles(remote.titles, to: &merged)

        let historyImportCount = mergeHistory(remote.history, into: &merged)
        let watchlistResult = reconcileWatchlist(
            local: snapshot,
            merged: &merged,
            remote: remote.watchlist,
            baseline: previousState.syncedWatchlist
        )
        let ratingResult = reconcileRatings(
            local: snapshot,
            merged: &merged,
            remote: remote.ratings,
            baseline: previousState.syncedRatings
        )
        let historyCandidates = historyMutations(
            in: merged,
            excluding: previousState.uploadedHistoryEventIDs
        )
        let confirmedHistoryIDs = Set(historyCandidates.compactMap { mutation in
            remote.history.contains(where: { matches($0, mutation) }) ? mutation.eventID : nil
        })
        let pendingHistory = historyCandidates.filter {
            !confirmedHistoryIDs.contains($0.eventID)
        }

        nextState.lastRemoteActivityAt = remote.activityAt ?? previousState.lastRemoteActivityAt
        nextState.uploadedHistoryEventIDs.formUnion(confirmedHistoryIDs)
        nextState.syncedWatchlist = watchlistResult.agreed
        nextState.syncedRatings = ratingResult.agreed
        nextState.importedLists = remote.lists
        nextState.lastError = nil
        merged.traktSyncState = nextState

        return TraktSyncPlan(
            snapshot: merged,
            outbound: TraktOutboundChanges(
                history: pendingHistory,
                ratingsToAdd: ratingResult.toAdd,
                ratingsToRemove: ratingResult.toRemove,
                watchlistToAdd: watchlistResult.toAdd,
                watchlistToRemove: watchlistResult.toRemove
            ),
            importedHistoryCount: historyImportCount,
            importedRatingCount: remote.ratings.count,
            importedWatchlistCount: remote.watchlist.count,
            importedListCount: remote.lists.count
        )
    }

    static func pendingChangeCount(in snapshot: LibrarySnapshot) -> Int {
        let state = snapshot.traktSyncState ?? .empty
        let historyCount = historyMutations(
            in: snapshot,
            excluding: state.uploadedHistoryEventIDs
        ).count
        let currentWatchlist = watchlist(in: snapshot)
        let watchlistCount = currentWatchlist.symmetricDifference(state.syncedWatchlist).count
        let currentRatings = ratings(in: snapshot)
        let baselineRatings = Dictionary(uniqueKeysWithValues: state.syncedRatings.map { ($0.media, $0.rating) })
        let ratingKeys = Set(currentRatings.keys).union(baselineRatings.keys)
        let ratingCount = ratingKeys.lazy.filter { currentRatings[$0] != baselineRatings[$0] }.count
        return historyCount + watchlistCount + ratingCount
    }

    static func hasPendingHistory(in snapshot: LibrarySnapshot) -> Bool {
        let state = snapshot.traktSyncState ?? .empty
        return !historyMutations(
            in: snapshot,
            excluding: state.uploadedHistoryEventIDs
        ).isEmpty
    }
}

private extension TraktSyncEngine {
    struct WatchlistReconciliation {
        let agreed: Set<TraktMediaKey>
        let toAdd: Set<TraktMediaKey>
        let toRemove: Set<TraktMediaKey>
    }

    struct RatingReconciliation {
        let agreed: [TraktRatingBaseline]
        let toAdd: [TraktRatingBaseline]
        let toRemove: Set<TraktMediaKey>
    }

    static func addMissingTitles(
        _ remoteTitles: [TraktRemoteTitle],
        to snapshot: inout LibrarySnapshot
    ) {
        var existing = Set(snapshot.titles.compactMap { title -> TraktMediaKey? in
            guard title.catalogID > 0 else { return nil }
            return TraktMediaKey(kind: title.kind, tmdbID: title.catalogID)
        })
        for remoteTitle in remoteTitles where existing.insert(remoteTitle.media).inserted {
            snapshot.titles.append(remoteTitle.mediaTitle)
        }
    }

    static func reconcileWatchlist(
        local: LibrarySnapshot,
        merged: inout LibrarySnapshot,
        remote: Set<TraktMediaKey>,
        baseline: Set<TraktMediaKey>
    ) -> WatchlistReconciliation {
        let localWatchlist = watchlist(in: local)
        let localAdded = localWatchlist.subtracting(baseline)
        let localRemoved = baseline.subtracting(localWatchlist)
        let remoteAdded = remote.subtracting(baseline)
        let remoteRemoved = baseline.subtracting(remote)
        let agreed = baseline
            .subtracting(localRemoved)
            .subtracting(remoteRemoved)
            .union(localAdded)
            .union(remoteAdded)
        let affected = baseline.union(localWatchlist).union(remote)

        for media in affected {
            guard let index = titleIndex(for: media, in: merged.titles) else { continue }
            merged.titles[index].personalWatchlist = agreed.contains(media)
        }

        return WatchlistReconciliation(
            agreed: agreed,
            toAdd: agreed.subtracting(remote),
            toRemove: remote.subtracting(agreed)
        )
    }

    static func reconcileRatings(
        local: LibrarySnapshot,
        merged: inout LibrarySnapshot,
        remote: [TraktRatingItem],
        baseline: [TraktRatingBaseline]
    ) -> RatingReconciliation {
        let localRatings = ratings(in: local)
        let rawLocalRatings = local.titles.reduce(into: [TraktMediaKey: Double]()) { result, title in
            guard title.catalogID > 0, let rating = title.userRating else { return }
            result[TraktMediaKey(kind: title.kind, tmdbID: title.catalogID)] = rating
        }
        let baselineRatings = Dictionary(uniqueKeysWithValues: baseline.map { ($0.media, $0.rating) })
        let remoteRatings = latestRemoteRatings(remote)
        let keys = Set(localRatings.keys)
            .union(baselineRatings.keys)
            .union(remoteRatings.keys)
        var agreed: [TraktMediaKey: Int] = [:]

        for key in keys {
            let baselineValue = baselineRatings[key]
            let localValue = localRatings[key]
            let rawLocalValue = rawLocalRatings[key]
            let remoteValue = remoteRatings[key]
            let isUnsupportedLocalValue = rawLocalValue != nil && localValue == nil
            let localChanged = localValue != baselineValue
            let remoteChanged = remoteValue != baselineValue

            // Local wins a true tie. Otherwise the side that changed from the
            // previous agreed baseline wins, including an intentional removal.
            let resolved: Int?
            if isUnsupportedLocalValue {
                resolved = remoteValue ?? baselineValue
            } else if localChanged {
                resolved = localValue
            } else if remoteChanged {
                resolved = remoteValue
            } else {
                resolved = baselineValue
            }
            agreed[key] = resolved

            guard let index = titleIndex(for: key, in: merged.titles) else { continue }
            if !isUnsupportedLocalValue && !localChanged && remoteChanged {
                merged.titles[index].userRating = resolved.map(Double.init)
            } else if rawLocalValue == nil && baselineValue == nil {
                merged.titles[index].userRating = resolved.map(Double.init)
            }
        }

        let agreedRatings = agreed
            .map { TraktRatingBaseline(media: $0.key, rating: $0.value) }
            .sorted(by: isEarlierRating)
        let toAdd = agreedRatings.filter { remoteRatings[$0.media] != $0.rating }
        let toRemove = Set(remoteRatings.keys.filter { agreed[$0] == nil })
        return RatingReconciliation(agreed: agreedRatings, toAdd: toAdd, toRemove: toRemove)
    }

    static func latestRemoteRatings(_ ratings: [TraktRatingItem]) -> [TraktMediaKey: Int] {
        Dictionary(grouping: ratings, by: \.media).reduce(into: [:]) { result, pair in
            result[pair.key] = pair.value.max(by: { $0.ratedAt < $1.ratedAt })?.rating
        }
    }

    static func watchlist(in snapshot: LibrarySnapshot) -> Set<TraktMediaKey> {
        Set(snapshot.titles.compactMap { title in
            guard title.catalogID > 0, title.isOnPersonalWatchlist else { return nil }
            return TraktMediaKey(kind: title.kind, tmdbID: title.catalogID)
        })
    }

    static func ratings(in snapshot: LibrarySnapshot) -> [TraktMediaKey: Int] {
        snapshot.titles.reduce(into: [:]) { result, title in
            guard title.catalogID > 0, let rating = title.userRating else { return }
            guard let traktRating = normalizedTraktRating(rating) else { return }
            result[TraktMediaKey(kind: title.kind, tmdbID: title.catalogID)] = traktRating
        }
    }

    static func normalizedTraktRating(_ rating: Double) -> Int? {
        guard rating > 0 else { return nil }
        return min(max(Int(rating.rounded()), 1), 10)
    }

    static func isEarlierRating(_ lhs: TraktRatingBaseline, _ rhs: TraktRatingBaseline) -> Bool {
        if lhs.media.kind != rhs.media.kind {
            return lhs.media.kind.rawValue < rhs.media.kind.rawValue
        }
        return lhs.media.tmdbID < rhs.media.tmdbID
    }
}
