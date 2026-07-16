import Foundation

extension AppModel {
    func refreshUpcomingCalendar(force: Bool = false) async {
        guard !shouldSkipUpcomingCalendarRefresh(force: force) else { return }
        isRefreshingUpcomingCalendar = true
        upcomingCalendarLastAttemptedAt = .now
        defer { isRefreshingUpcomingCalendar = false }

        let candidates = upcomingCalendarCandidates
        guard !candidates.isEmpty else {
            upcomingCalendarRefreshError = nil
            return
        }

        let results = await loadUpcomingCalendarDetails(candidates)
        applyUpcomingCalendarRefresh(results)
    }
}

private extension AppModel {
    var upcomingCalendarCandidates: [MediaTitle] {
        titles.filter { title in
            title.state != .completed
                && (title.state != .planned || title.isOnPersonalWatchlist)
        }
    }

    func shouldSkipUpcomingCalendarRefresh(force: Bool) -> Bool {
        if isRefreshingUpcomingCalendar { return true }
        guard !force, let attemptedAt = upcomingCalendarLastAttemptedAt else { return false }
        return attemptedAt > Date.now.addingTimeInterval(-15 * 60)
    }

    func loadUpcomingCalendarDetails(
        _ candidates: [MediaTitle]
    ) async -> [UpcomingCalendarTitleRefresh] {
        let service = catalogService
        let region = streamingRegion
        return await withTaskGroup(
            of: UpcomingCalendarTitleRefresh.self,
            returning: [UpcomingCalendarTitleRefresh].self
        ) { group in
            var remaining = candidates.makeIterator()
            for _ in 0..<min(candidates.count, 4) {
                if let title = remaining.next() {
                    group.addTask { await refreshCalendarTitle(title, service: service, region: region) }
                }
            }

            var values: [UpcomingCalendarTitleRefresh] = []
            while let value = await group.next() {
                values.append(value)
                if let title = remaining.next() {
                    group.addTask { await refreshCalendarTitle(title, service: service, region: region) }
                }
            }
            return values
        }
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
) async -> UpcomingCalendarTitleRefresh {
    do {
        let details = try await service.title(
            kind: title.kind,
            catalogID: title.catalogID,
            region: region
        )
        return UpcomingCalendarTitleRefresh(titleID: title.id, details: details)
    } catch {
        return UpcomingCalendarTitleRefresh(titleID: title.id, details: nil)
    }
}

private struct UpcomingCalendarTitleRefresh: Sendable {
    let titleID: MediaTitle.ID
    let details: MediaTitle?
}
