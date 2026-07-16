import Foundation

enum ViewingAnalyticsScope: String, Sendable {
    case personal
    case together
}

struct ViewingAnalyticsMetric: Hashable, Identifiable, Sendable {
    let id: String
    let label: String
    let minutes: Int
}

struct ViewingAnalyticsSummary: Hashable, Sendable {
    let scope: ViewingAnalyticsScope
    let totalMinutes: Int
    let titleCount: Int
    let movieCount: Int
    let seriesCount: Int
    let episodeCount: Int
    let playCount: Int
    let kindBreakdown: [ViewingAnalyticsMetric]
    let genreBreakdown: [ViewingAnalyticsMetric]
    let serviceBreakdown: [ViewingAnalyticsMetric]
    let memberBreakdown: [ViewingAnalyticsMetric]
    let periodStart: Date?
    let periodEnd: Date?
    let includesEstimates: Bool

    var isEmpty: Bool { playCount == 0 }
    var topGenre: String? { genreBreakdown.first?.label }

    var shareText: String {
        let hours = Double(totalMinutes) / 60
        let duration = hours.formatted(.number.precision(.fractionLength(hours < 10 ? 1 : 0)))
        let noun = titleCount == 1 ? "title" : "titles"
        let genre = topGenre.map { " Top genre: \($0)." } ?? ""
        switch scope {
        case .personal:
            return "I've tracked \(duration) hours across \(titleCount) \(noun) on OpenTV.\(genre) 🍿"
        case .together:
            return "We've watched \(duration) hours together across \(titleCount) \(noun) on OpenTV.\(genre) 🍿"
        }
    }
}

enum ViewingAnalyticsEngine {
    static func summarize(
        snapshot: LibrarySnapshot,
        scope: ViewingAnalyticsScope
    ) -> ViewingAnalyticsSummary {
        let titleByID = Dictionary(uniqueKeysWithValues: snapshot.titles.map { ($0.id, $0) })
        let validEvents = validEvents(in: snapshot.sharedSpace)
        let result: AnalyticsResult

        switch scope {
        case .personal:
            result = personalResult(
                events: validEvents,
                titles: snapshot.titles,
                titleByID: titleByID,
                space: snapshot.sharedSpace
            )
        case .together:
            result = togetherResult(
                events: validEvents,
                titleByID: titleByID,
                space: snapshot.sharedSpace
            )
        }

        return summary(
            from: result.plays,
            scope: scope,
            members: snapshot.sharedSpace.members,
            includesEstimates: result.includesEstimates
        )
    }
}

private extension ViewingAnalyticsEngine {
    struct AnalyticsResult {
        let plays: [ViewingPlay]
        let includesEstimates: Bool
    }

    struct ViewingPlay {
        let title: MediaTitle
        let runtimeMinutes: Int
        let occurredAt: Date?
        let memberIDs: Set<SpaceMember.ID>
        let isEstimated: Bool
        let season: Int?
        let episode: Int?
    }

    static func validEvents(in space: SharedSpace) -> [SharedWatchEvent] {
        let events = space.watchEvents ?? []
        let supersededIDs = Set(events.compactMap { event in
            event.kind == .correction ? event.supersedesEventID : nil
        })
        return events.filter { event in
            event.kind != .correction && !supersededIDs.contains(event.id)
        }
    }

    static func personalResult(
        events: [SharedWatchEvent],
        titles: [MediaTitle],
        titleByID: [MediaTitle.ID: MediaTitle],
        space: SharedSpace
    ) -> AnalyticsResult {
        let memberID = space.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let personalEvents = events.filter { $0.memberID == memberID }
        var plays = personalEvents.compactMap { event -> ViewingPlay? in
            guard let title = titleByID[event.titleID] else { return nil }
            return ViewingPlay(
                title: title,
                runtimeMinutes: runtime(for: title, season: event.season, episode: event.episode),
                occurredAt: event.occurredAt,
                memberIDs: [memberID],
                isEstimated: false,
                season: event.season,
                episode: event.episode
            )
        }

        var includesEstimates = false
        for title in titles {
            let titleEvents = personalEvents.filter { $0.titleID == title.id }
            let missingPlays = inferredPlayCount(for: title, recordedEvents: titleEvents)
            guard missingPlays > 0 else { continue }
            includesEstimates = true
            let date = title.lastWatchedAt ?? title.releaseDate
            plays.append(contentsOf: (0..<missingPlays).map { _ in
                ViewingPlay(
                    title: title,
                    runtimeMinutes: title.runtimeMinutes,
                    occurredAt: date,
                    memberIDs: [memberID],
                    isEstimated: true,
                    season: title.progress?.season,
                    episode: nil
                )
            })
        }

        return AnalyticsResult(plays: plays, includesEstimates: includesEstimates)
    }

    static func inferredPlayCount(
        for title: MediaTitle,
        recordedEvents: [SharedWatchEvent]
    ) -> Int {
        let recordedRewatches = recordedEvents.filter { $0.kind == .rewatch }.count
        let missingRewatches = max(title.completedRewatches - recordedRewatches, 0)

        switch title.kind {
        case .movie:
            let expectedInitialWatch = title.state == .completed ? 1 : 0
            let recordedInitialWatches = recordedEvents.filter { $0.kind != .rewatch }.count
            return max(expectedInitialWatch - recordedInitialWatches, 0) + missingRewatches
        case .series:
            let expectedEpisodes: Int
            if let watchedEpisodeIDs = title.watchedEpisodeIDs {
                expectedEpisodes = watchedEpisodeIDs.count
            } else if let progress = title.progress {
                expectedEpisodes = progress.episode
            } else if title.state.isCurrentViewingComplete {
                expectedEpisodes = title.seasons?.reduce(0) { $0 + $1.episodes.count } ?? 0
            } else {
                expectedEpisodes = 0
            }
            let recordedEpisodes = recordedEvents.filter { $0.kind != .rewatch }.count
            return max(expectedEpisodes - recordedEpisodes, 0) + missingRewatches
        }
    }

    static func togetherResult(
        events: [SharedWatchEvent],
        titleByID: [MediaTitle.ID: MediaTitle],
        space: SharedSpace
    ) -> AnalyticsResult {
        let togetherEvents = events
            .filter { $0.kind == .watchedTogether }
            .sorted { $0.occurredAt < $1.occurredAt }
        var plays: [ViewingPlay] = []

        for event in togetherEvents {
            guard let title = titleByID[event.titleID] else { continue }
            if let index = plays.lastIndex(where: { play in
                play.title.id == event.titleID
                    && play.season == event.season
                    && play.episode == event.episode
                    && play.occurredAt.map { abs($0.timeIntervalSince(event.occurredAt)) < 10 } == true
            }) {
                let existing = plays[index]
                plays[index] = ViewingPlay(
                    title: existing.title,
                    runtimeMinutes: existing.runtimeMinutes,
                    occurredAt: existing.occurredAt.map { min($0, event.occurredAt) } ?? event.occurredAt,
                    memberIDs: existing.memberIDs.union([event.memberID]),
                    isEstimated: false,
                    season: existing.season,
                    episode: existing.episode
                )
            } else {
                plays.append(
                    ViewingPlay(
                        title: title,
                        runtimeMinutes: runtime(for: title, season: event.season, episode: event.episode),
                        occurredAt: event.occurredAt,
                        memberIDs: [event.memberID],
                        isEstimated: false,
                        season: event.season,
                        episode: event.episode
                    )
                )
            }
        }

        let knownMemberIDs = Set(space.members.map(\.id))
        plays = plays.map { play in
            ViewingPlay(
                title: play.title,
                runtimeMinutes: play.runtimeMinutes,
                occurredAt: play.occurredAt,
                memberIDs: play.memberIDs.intersection(knownMemberIDs),
                isEstimated: false,
                season: play.season,
                episode: play.episode
            )
        }
        return AnalyticsResult(plays: plays, includesEstimates: false)
    }

    static func summary(
        from plays: [ViewingPlay],
        scope: ViewingAnalyticsScope,
        members: [SpaceMember],
        includesEstimates: Bool
    ) -> ViewingAnalyticsSummary {
        let uniqueTitles = Dictionary(grouping: plays, by: { $0.title.id }).compactMap { $0.value.first?.title }
        let movieTitles = uniqueTitles.filter { $0.kind == .movie }
        let seriesTitles = uniqueTitles.filter { $0.kind == .series }

        return ViewingAnalyticsSummary(
            scope: scope,
            totalMinutes: plays.reduce(0) { $0 + $1.runtimeMinutes },
            titleCount: uniqueTitles.count,
            movieCount: movieTitles.count,
            seriesCount: seriesTitles.count,
            episodeCount: plays.filter { $0.title.kind == .series }.count,
            playCount: plays.count,
            kindBreakdown: kindMetrics(for: plays),
            genreBreakdown: groupedMetrics(for: plays, values: { $0.title.genres }),
            serviceBreakdown: groupedMetrics(for: plays, values: { $0.title.providers.map(\.name) }),
            memberBreakdown: memberMetrics(for: plays, members: members),
            periodStart: plays.compactMap(\.occurredAt).min(),
            periodEnd: plays.compactMap(\.occurredAt).max(),
            includesEstimates: includesEstimates || plays.contains(where: \.isEstimated)
        )
    }

    static func kindMetrics(for plays: [ViewingPlay]) -> [ViewingAnalyticsMetric] {
        MediaKind.allCases.compactMap { kind in
            let minutes = plays.filter { $0.title.kind == kind }.reduce(0) { $0 + $1.runtimeMinutes }
            guard minutes > 0 else { return nil }
            return ViewingAnalyticsMetric(id: kind.rawValue, label: kind.label, minutes: minutes)
        }
    }

    static func groupedMetrics(
        for plays: [ViewingPlay],
        values: (ViewingPlay) -> [String]
    ) -> [ViewingAnalyticsMetric] {
        let minutes = plays.reduce(into: [String: Int]()) { result, play in
            for value in Set(values(play)) where !value.isEmpty {
                result[value, default: 0] += play.runtimeMinutes
            }
        }
        return minutes
            .map { ViewingAnalyticsMetric(id: $0.key, label: $0.key, minutes: $0.value) }
            .sorted { lhs, rhs in
                lhs.minutes == rhs.minutes ? lhs.label < rhs.label : lhs.minutes > rhs.minutes
            }
    }

    static func memberMetrics(
        for plays: [ViewingPlay],
        members: [SpaceMember]
    ) -> [ViewingAnalyticsMetric] {
        let namesByID = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0.name) })
        let minutes = plays.reduce(into: [String: Int]()) { result, play in
            for memberID in play.memberIDs {
                result[memberID, default: 0] += play.runtimeMinutes
            }
        }
        return minutes
            .map { ViewingAnalyticsMetric(id: $0.key, label: namesByID[$0.key] ?? "Member", minutes: $0.value) }
            .sorted { lhs, rhs in
                lhs.minutes == rhs.minutes ? lhs.label < rhs.label : lhs.minutes > rhs.minutes
            }
    }

    static func runtime(
        for title: MediaTitle,
        season: Int?,
        episode: Int?
    ) -> Int {
        guard title.kind == .series, let season, let episode else { return title.runtimeMinutes }
        return title.seasons?
            .first(where: { $0.number == season })?
            .episodes
            .first(where: { $0.number == episode })?
            .runtimeMinutes ?? title.runtimeMinutes
    }
}
