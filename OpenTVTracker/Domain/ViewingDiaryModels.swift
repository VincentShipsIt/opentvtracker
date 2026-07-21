import Foundation

enum ViewingDiaryScope: String, Codable, Sendable {
    case title
    case season
    case episode
}

struct ViewingDiaryEntry: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let titleID: MediaTitle.ID
    let scope: ViewingDiaryScope
    var seasonNumber: Int?
    var episodeID: EpisodeSummary.ID?
    var episodeNumber: Int?
    var watchedAt: Date?
    var rating: Double?
    var note: String?
    var isRewatch: Bool
    let createdAt: Date
    var updatedAt: Date

    var hasPrivateContent: Bool {
        watchedAt != nil || rating != nil || note?.isEmpty == false
    }
}

enum ViewingDiaryTarget: Hashable, Identifiable, Sendable {
    case title(titleID: MediaTitle.ID)
    case season(titleID: MediaTitle.ID, seasonID: SeasonSummary.ID, seasonNumber: Int)
    case episode(
        titleID: MediaTitle.ID,
        seasonID: SeasonSummary.ID,
        seasonNumber: Int,
        episodeID: EpisodeSummary.ID,
        episodeNumber: Int
    )

    var id: String {
        switch self {
        case .title(let titleID):
            "title:\(titleID)"
        case .season(let titleID, _, let seasonNumber):
            "season:\(titleID):\(seasonNumber)"
        case .episode(let titleID, _, let seasonNumber, let episodeID, _):
            "episode:\(titleID):\(seasonNumber):\(episodeID)"
        }
    }

    var titleID: MediaTitle.ID {
        switch self {
        case .title(let titleID), .season(let titleID, _, _), .episode(let titleID, _, _, _, _):
            titleID
        }
    }

    var scope: ViewingDiaryScope {
        switch self {
        case .title: .title
        case .season: .season
        case .episode: .episode
        }
    }

    var seasonNumber: Int? {
        switch self {
        case .title: nil
        case .season(_, _, let seasonNumber), .episode(_, _, let seasonNumber, _, _): seasonNumber
        }
    }

    var episodeID: EpisodeSummary.ID? {
        guard case .episode(_, _, _, let episodeID, _) = self else { return nil }
        return episodeID
    }

    var episodeNumber: Int? {
        guard case .episode(_, _, _, _, let episodeNumber) = self else { return nil }
        return episodeNumber
    }
}

struct ViewingDiaryRecord: Identifiable, Sendable {
    let entry: ViewingDiaryEntry
    let title: MediaTitle
    let season: SeasonSummary?
    let episode: EpisodeSummary?

    var id: ViewingDiaryEntry.ID { entry.id }
}

struct ViewingDiaryDay: Identifiable, Sendable {
    let date: Date
    let records: [ViewingDiaryRecord]

    var id: Date { date }
}

enum ViewingDiaryMigration {
    static func resolvedEntries(from snapshot: LibrarySnapshot) -> [ViewingDiaryEntry] {
        if let diaryEntries = snapshot.diaryEntries { return diaryEntries }

        let currentMemberID = snapshot.sharedSpace.members.first(where: \.isCurrentUser)?.id ?? "local-user"
        let events = snapshot.sharedSpace.watchEvents ?? []
        let supersededIDs = Set(events.compactMap { event in
            event.kind == .correction ? event.supersedesEventID : nil
        })
        let titlesByID = Dictionary(uniqueKeysWithValues: snapshot.titles.map { ($0.id, $0) })

        return events.compactMap { event in
            guard event.memberID == currentMemberID,
                  event.kind != .correction,
                  !supersededIDs.contains(event.id),
                  let title = titlesByID[event.titleID] else {
                return nil
            }
            let season = event.season.flatMap { seasonNumber in
                title.seasons?.first(where: { $0.number == seasonNumber })
            }
            let episode = event.episode.flatMap { episodeNumber in
                season?.episodes.first(where: { $0.number == episodeNumber })
            }
            let scope: ViewingDiaryScope
            if episode != nil {
                scope = .episode
            } else if event.season != nil {
                scope = .season
            } else {
                scope = .title
            }
            return ViewingDiaryEntry(
                id: "diary:\(event.id)",
                titleID: event.titleID,
                scope: scope,
                seasonNumber: event.season,
                episodeID: episode?.id,
                episodeNumber: event.episode,
                watchedAt: event.occurredAt,
                rating: nil,
                note: nil,
                isRewatch: event.kind == .rewatch,
                createdAt: event.occurredAt,
                updatedAt: event.occurredAt
            )
        }
    }
}
