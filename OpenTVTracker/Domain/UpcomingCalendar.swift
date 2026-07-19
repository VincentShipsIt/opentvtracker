import Foundation

enum UpcomingCalendarEventKind: Hashable, Sendable {
    case seriesPremiere
    case returningSeason
    case seasonFinale
    case episode
    case movieRelease

    var label: LocalizedStringResource {
        switch self {
        case .seriesPremiere: "Series premiere"
        case .returningSeason: "Returning season"
        case .seasonFinale: "Season finale"
        case .episode: "New episode"
        case .movieRelease: "Movie release"
        }
    }

    var symbol: String {
        switch self {
        case .seriesPremiere: "sparkles.tv"
        case .returningSeason: "arrow.clockwise.circle.fill"
        case .seasonFinale: "flag.checkered.circle.fill"
        case .episode: "play.rectangle.fill"
        case .movieRelease: "film.fill"
        }
    }
}

struct UpcomingCalendarItem: Hashable, Identifiable, Sendable {
    let id: String
    let titleID: MediaTitle.ID
    let title: String
    let date: Date
    let isAllDay: Bool
    let kind: UpcomingCalendarEventKind
    let watchState: WatchState
    let seasonID: SeasonSummary.ID?
    let seasonNumber: Int?
    let episodeID: EpisodeSummary.ID?
    let episodeNumber: Int?
    let episodeTitle: String?
}

struct UpcomingCalendarDay: Hashable, Identifiable, Sendable {
    let date: Date
    let items: [UpcomingCalendarItem]

    var id: Date { date }
}

enum UpcomingCalendarEngine {
    static func items(
        from titles: [MediaTitle],
        in dateRange: ClosedRange<Date>,
        includedStates: Set<WatchState>,
        providerIDs: Set<StreamingProvider.ID>?,
        calendar: Calendar
    ) -> [UpcomingCalendarItem] {
        let start = calendar.startOfDay(for: dateRange.lowerBound)
        guard let endExclusive = calendar.date(
            byAdding: .day,
            value: 1,
            to: calendar.startOfDay(for: dateRange.upperBound)
        ) else {
            return []
        }

        return titles
            .filter { title in
                title.isUpcomingCalendarTracked
                    && includedStates.contains(title.state)
                    && matchesProviderFilter(title, providerIDs: providerIDs)
            }
            .flatMap { title in
                events(for: title, start: start, endExclusive: endExclusive, calendar: calendar)
            }
            .sorted(by: eventSort)
    }

    static func days(from items: [UpcomingCalendarItem], calendar: Calendar) -> [UpcomingCalendarDay] {
        Dictionary(grouping: items) { calendar.startOfDay(for: $0.date) }
            .map { date, items in
                UpcomingCalendarDay(date: date, items: items.sorted(by: eventSort))
            }
            .sorted { $0.date < $1.date }
    }
}

extension MediaTitle {
    var isUpcomingCalendarTracked: Bool {
        state != .planned || isOnPersonalWatchlist
    }
}

private extension UpcomingCalendarEngine {
    static func matchesProviderFilter(
        _ title: MediaTitle,
        providerIDs: Set<StreamingProvider.ID>?
    ) -> Bool {
        guard let providerIDs else { return true }
        return !providerIDs.isDisjoint(with: Set(title.providers.map(\.id)))
    }

    static func events(
        for title: MediaTitle,
        start: Date,
        endExclusive: Date,
        calendar: Calendar
    ) -> [UpcomingCalendarItem] {
        switch title.kind {
        case .movie:
            guard let releaseDate = title.releaseDate,
                  let displayDate = displayDate(for: releaseDate, isAllDay: true, calendar: calendar),
                  isInRange(displayDate, start: start, endExclusive: endExclusive, calendar: calendar) else {
                return []
            }
            return [
                UpcomingCalendarItem(
                    id: "movie-release:\(title.id)",
                    titleID: title.id,
                    title: title.title,
                    date: displayDate,
                    isAllDay: true,
                    kind: .movieRelease,
                    watchState: title.state,
                    seasonID: nil,
                    seasonNumber: nil,
                    episodeID: nil,
                    episodeNumber: nil,
                    episodeTitle: nil
                )
            ]
        case .series:
            return seriesEvents(
                for: title,
                start: start,
                endExclusive: endExclusive,
                calendar: calendar
            )
        }
    }

    static func seriesEvents(
        for title: MediaTitle,
        start: Date,
        endExclusive: Date,
        calendar: Calendar
    ) -> [UpcomingCalendarItem] {
        let seasons = (title.seasons ?? [])
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
        let window = UpcomingCalendarWindow(
            start: start,
            endExclusive: endExclusive,
            calendar: calendar
        )

        let scheduled = seasons.flatMap { season in
            episodeEvents(
                for: title,
                season: season,
                window: window
            )
        }

        let fallbackIsAllDay = title.nextEpisodeAirDateIsAllDay ?? (title.metadataSource == .tmdb)

        guard scheduled.isEmpty,
              let fallbackDate = title.nextEpisodeAirDate,
              let displayDate = displayDate(
                  for: fallbackDate,
                  isAllDay: fallbackIsAllDay,
                  calendar: calendar
              ),
              isInRange(displayDate, start: start, endExclusive: endExclusive, calendar: calendar) else {
            return scheduled
        }

        return [
            UpcomingCalendarItem(
                id: "next-episode:\(title.id):\(fallbackDate.timeIntervalSinceReferenceDate)",
                titleID: title.id,
                title: title.title,
                date: displayDate,
                isAllDay: fallbackIsAllDay,
                kind: .episode,
                watchState: title.state,
                seasonID: nil,
                seasonNumber: nil,
                episodeID: nil,
                episodeNumber: nil,
                episodeTitle: nil
            )
        ]
    }

    static func episodeEvents(
        for title: MediaTitle,
        season: SeasonSummary,
        window: UpcomingCalendarWindow
    ) -> [UpcomingCalendarItem] {
        let episodes = season.episodes.sorted { $0.number < $1.number }
        guard let firstEpisode = episodes.first else { return [] }

        return episodes.compactMap { episode in
            let isAllDay = episode.airDateIsAllDay ?? (title.metadataSource == .tmdb)
            guard let airDate = episode.airDate,
                  let displayDate = displayDate(
                      for: airDate,
                      isAllDay: isAllDay,
                      calendar: window.calendar
                  ),
                  isInRange(
                      displayDate,
                      start: window.start,
                      endExclusive: window.endExclusive,
                      calendar: window.calendar
                  ) else {
                return nil
            }

            let kind: UpcomingCalendarEventKind
            if episode.releaseType == .finale {
                kind = .seasonFinale
            } else if episode.id == firstEpisode.id, episode.number == 1 {
                kind = season.number == 1 ? .seriesPremiere : .returningSeason
            } else {
                kind = .episode
            }

            return UpcomingCalendarItem(
                id: "episode:\(title.id):\(season.id):\(episode.id)",
                titleID: title.id,
                title: title.title,
                date: displayDate,
                isAllDay: isAllDay,
                kind: kind,
                watchState: title.state,
                seasonID: season.id,
                seasonNumber: season.number,
                episodeID: episode.id,
                episodeNumber: episode.number,
                episodeTitle: episode.title
            )
        }
    }

    static func isInRange(
        _ date: Date,
        start: Date,
        endExclusive: Date,
        calendar: Calendar
    ) -> Bool {
        let localDate = calendar.startOfDay(for: date)
        return localDate >= start && localDate < endExclusive
    }

    static func displayDate(for date: Date, isAllDay: Bool, calendar: Calendar) -> Date? {
        guard isAllDay else { return date }
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = sourceCalendar.dateComponents([.year, .month, .day], from: date)
        return calendar.date(from: components)
    }

    static func eventSort(_ lhs: UpcomingCalendarItem, _ rhs: UpcomingCalendarItem) -> Bool {
        if lhs.date != rhs.date { return lhs.date < rhs.date }
        if lhs.title != rhs.title {
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
        return lhs.id < rhs.id
    }
}

private struct UpcomingCalendarWindow {
    let start: Date
    let endExclusive: Date
    let calendar: Calendar
}
