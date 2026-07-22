enum CSVRowResult {
    case matched
    case duplicate
    case skipped
}

struct LibraryTitleImportCounts {
    let matched: Int
    let added: Int
    let duplicates: Int
}
