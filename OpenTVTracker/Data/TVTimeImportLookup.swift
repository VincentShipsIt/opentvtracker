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
    private var byKindAndTitle: [String: [Int]] = [:]
    private var byKindTitleAndYear: [String: [Int]] = [:]

    init(_ titles: [MediaTitle]) {
        for (index, title) in titles.enumerated() {
            insert(title, at: index)
        }
    }

    mutating func insert(_ title: MediaTitle, at index: Int) {
        byID[title.id] = byID[title.id] ?? index
        let titleKey = Self.titleKey(kind: title.kind, title: title.title)
        if byKindAndTitle[titleKey]?.contains(index) != true {
            byKindAndTitle[titleKey, default: []].append(index)
        }
        let yearKey = Self.yearKey(titleKey, year: title.year)
        if byKindTitleAndYear[yearKey]?.contains(index) != true {
            byKindTitleAndYear[yearKey, default: []].append(index)
        }
    }

    func index(for title: MediaTitle, matching entity: TVTimeEntity) -> Int? {
        byID[title.id] ?? index(matching: entity)
    }

    func index(matching entity: TVTimeEntity) -> Int? {
        let titleKey = Self.titleKey(kind: entity.kind, title: entity.title)
        if let year = entity.year {
            return uniqueIndex(in: byKindTitleAndYear[Self.yearKey(titleKey, year: year)])
        }
        return uniqueIndex(in: byKindAndTitle[titleKey])
    }

    private func uniqueIndex(in indexes: [Int]?) -> Int? {
        guard let indexes, indexes.count == 1 else { return nil }
        return indexes[0]
    }

    private static func titleKey(kind: MediaKind, title: String) -> String {
        "\(kind.rawValue):\(TVTimeCSV.normalizedTitle(title))"
    }

    private static func yearKey(_ titleKey: String, year: Int) -> String {
        "\(titleKey):\(year)"
    }
}
