import Foundation

/// O(1) lookup helpers for library title arrays. First occurrence wins for duplicate IDs.
enum LibraryTitleIndex {
    /// Removes duplicate title IDs, keeping the first occurrence.
    static func deduplicated(_ titles: [MediaTitle]) -> [MediaTitle] {
        CollectionUniquing.uniqued(titles, by: \.id)
    }

    /// Map of title ID → array index for the first occurrence of each ID.
    static func indexByID(_ titles: [MediaTitle]) -> [MediaTitle.ID: Int] {
        var indexByID: [MediaTitle.ID: Int] = [:]
        indexByID.reserveCapacity(titles.count)
        for (offset, title) in titles.enumerated() where indexByID[title.id] == nil {
            indexByID[title.id] = offset
        }
        return indexByID
    }

    static func index(of id: MediaTitle.ID, in titles: [MediaTitle], cache: [MediaTitle.ID: Int]) -> Int? {
        if let index = cache[id], titles.indices.contains(index), titles[index].id == id {
            return index
        }
        return titles.firstIndex(where: { $0.id == id })
    }
}
