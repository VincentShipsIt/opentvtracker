import Foundation

struct TVTimeMergeState {
    var existingEventIDs: Set<String>
    var titleIDs: Set<MediaTitle.ID>
    var titleLookup: TVTimeMediaTitleLookup

    init(snapshot: LibrarySnapshot) {
        existingEventIDs = Set((snapshot.sharedSpace.watchEvents ?? []).map(\.id))
        titleIDs = Set(snapshot.sharedSpace.titleIDs)
        titleLookup = TVTimeMediaTitleLookup(snapshot.titles)
    }
}

struct TVTimeMediaTitleLookup {
    private var byID: [MediaTitle.ID: Int] = [:]
    private var byKindAndTitle: [String: Int] = [:]
    private var byKindTitleAndYear: [String: Int] = [:]

    init(_ titles: [MediaTitle]) {
        for (index, title) in titles.enumerated() {
            insert(title, at: index)
        }
    }

    mutating func insert(_ title: MediaTitle, at index: Int) {
        byID[title.id] = byID[title.id] ?? index
        let titleKey = Self.titleKey(kind: title.kind, title: title.title)
        byKindAndTitle[titleKey] = byKindAndTitle[titleKey] ?? index
        if let year = title.year {
            let yearKey = Self.yearKey(titleKey, year: year)
            byKindTitleAndYear[yearKey] = byKindTitleAndYear[yearKey] ?? index
        }
    }

    func index(for title: MediaTitle, matching entity: TVTimeEntity) -> Int? {
        byID[title.id] ?? index(matching: entity)
    }

    func index(matching entity: TVTimeEntity) -> Int? {
        let titleKey = Self.titleKey(kind: entity.kind, title: entity.title)
        if let year = entity.year {
            return byKindTitleAndYear[Self.yearKey(titleKey, year: year)]
        }
        return byKindAndTitle[titleKey]
    }

    private static func titleKey(kind: MediaKind, title: String) -> String {
        "\(kind.rawValue):\(TVTimeCSV.normalizedTitle(title))"
    }

    private static func yearKey(_ titleKey: String, year: Int) -> String {
        "\(titleKey):\(year)"
    }
}
