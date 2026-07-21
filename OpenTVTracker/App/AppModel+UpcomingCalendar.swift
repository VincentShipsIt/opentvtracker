import Foundation

extension AppModel {
    func refreshUpcomingCalendar(force: Bool = false) async {
        if isRefreshingUpcomingCalendar {
            if force { queueUpcomingCalendarRefresh() }
            return
        }
        guard !shouldSkipUpcomingCalendarRefresh(force: force) else { return }
        isRefreshingUpcomingCalendar = true
        defer { isRefreshingUpcomingCalendar = false }

        repeat {
            hasQueuedUpcomingCalendarRefresh = false
            let revision = upcomingCalendarRefreshRevision
            let region = streamingRegion
            upcomingCalendarLastAttemptedAt = .now

            let candidates = upcomingCalendarCandidates
            guard !candidates.isEmpty else {
                upcomingCalendarRefreshError = nil
                return
            }

            let results: [UpcomingCalendarTitleRefresh]
            do {
                results = try await loadUpcomingCalendarDetails(candidates, region: region)
            } catch is CancellationError {
                if revision == upcomingCalendarRefreshRevision {
                    upcomingCalendarLastAttemptedAt = nil
                }
                return
            } catch {
                upcomingCalendarRefreshError = "The schedule could not be refreshed. Showing saved metadata when available."
                return
            }
            guard revision == upcomingCalendarRefreshRevision,
                  region == streamingRegion else {
                continue
            }
            applyUpcomingCalendarRefresh(results)
        } while hasQueuedUpcomingCalendarRefresh
    }

    func invalidateUpcomingCalendarRefresh() {
        upcomingCalendarRefreshRevision += 1
        hasQueuedUpcomingCalendarRefresh = false
        upcomingCalendarLastAttemptedAt = nil
        upcomingCalendarLastRefreshedAt = nil
        upcomingCalendarRefreshError = nil
    }
}

private extension AppModel {
    var upcomingCalendarCandidates: [MediaTitle] {
        titles.filter { title in
            title.state != .completed
                && title.isUpcomingCalendarTracked
                && (title.kind == .series || supportsUpcomingCalendarMovieRefresh)
        }
    }

    var supportsUpcomingCalendarMovieRefresh: Bool {
        !(catalogService is TVMazeCatalogService)
    }

    func shouldSkipUpcomingCalendarRefresh(force: Bool) -> Bool {
        guard !force, let attemptedAt = upcomingCalendarLastAttemptedAt else { return false }
        return attemptedAt > Date.now.addingTimeInterval(-15 * 60)
    }

    func loadUpcomingCalendarDetails(
        _ candidates: [MediaTitle],
        region: StreamingRegion
    ) async throws -> [UpcomingCalendarTitleRefresh] {
        let service = catalogService
        return try await withThrowingTaskGroup(
            of: UpcomingCalendarTitleRefresh.self,
            returning: [UpcomingCalendarTitleRefresh].self
        ) { group in
            var remaining = candidates.makeIterator()
            for _ in 0..<min(candidates.count, 4) {
                if let title = remaining.next() {
                    group.addTask { try await refreshCalendarTitle(title, service: service, region: region) }
                }
            }

            var values: [UpcomingCalendarTitleRefresh] = []
            while let value = try await group.next() {
                values.append(value)
                if let title = remaining.next() {
                    group.addTask { try await refreshCalendarTitle(title, service: service, region: region) }
                }
            }
            return values
        }
    }

    func queueUpcomingCalendarRefresh() {
        upcomingCalendarRefreshRevision += 1
        hasQueuedUpcomingCalendarRefresh = true
    }

    func applyUpcomingCalendarRefresh(_ results: [UpcomingCalendarTitleRefresh]) {
        let successful = results.compactMap { result -> (MediaTitle.ID, MediaTitle)? in
            guard let details = result.details else { return nil }
            return (result.titleID, details)
        }
        var refreshedTitles = titles
        for (titleID, details) in successful {
            guard let index = refreshedTitles.firstIndex(where: { $0.id == titleID }) else { continue }
            refreshedTitles[index] = mergingCatalogDetails(details, into: refreshedTitles[index])
        }

        if refreshedTitles != titles {
            titles = refreshedTitles
            persist()
        }

        let failureCount = results.count - successful.count
        if successful.isEmpty {
            upcomingCalendarRefreshError = "The schedule could not be refreshed. Showing saved metadata when available."
        } else {
            upcomingCalendarLastRefreshedAt = .now
            upcomingCalendarRefreshError = failureCount == 0
                ? nil
                : "Some titles could not be refreshed. Their saved schedule may be out of date."
        }
    }
}

private func refreshCalendarTitle(
    _ title: MediaTitle,
    service: any CatalogProviding,
    region: StreamingRegion
) async throws -> UpcomingCalendarTitleRefresh {
    do {
        let details = try await service.title(
            kind: title.kind,
            catalogID: title.catalogID,
            region: region
        )
        return UpcomingCalendarTitleRefresh(titleID: title.id, details: details)
    } catch is CancellationError {
        throw CancellationError()
    } catch {
        return UpcomingCalendarTitleRefresh(titleID: title.id, details: nil)
    }
}

private struct UpcomingCalendarTitleRefresh: Sendable {
    let titleID: MediaTitle.ID
    let details: MediaTitle?
}
