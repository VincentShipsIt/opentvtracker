import Foundation

enum LibraryImportLimits {
    static let maximumLibraryFileSize = 25 * 1_024 * 1_024
    static let maximumZIPFileSize = 100 * 1_024 * 1_024
    static let maximumRecordCount = 250_000
    static let maximumDecodedValueCount = 1_000_000
    static let maximumCSVValueCount = 2_000_000
    static let maximumJSONSeparatorCount = 2_000_000
    static let maximumFieldSize = 1 * 1_024 * 1_024
    static let maximumTVTimeListFieldSize = 8 * 1_024 * 1_024
    static let maximumCSVFieldCount = 128
    static let maximumJSONDepth = 64
    static let maximumZIPEntryCount = 1_024
}

enum LibraryImportSafetyError: LocalizedError, Equatable {
    case fileTooLarge
    case tooManyRecords
    case fieldTooLarge
    case tooManyFields
    case tooManyValues
    case structureTooDeep
    case malformedCSV

    var errorDescription: String? {
        switch self {
        case .fileTooLarge:
            "The selected file is too large to import safely."
        case .tooManyRecords:
            "The selected import contains more records than OpenTV can safely process."
        case .fieldTooLarge:
            "A field in the selected import is larger than OpenTV allows."
        case .tooManyFields:
            "A record in the selected import contains more fields than OpenTV allows."
        case .tooManyValues:
            "The selected import contains more values than OpenTV can safely process."
        case .structureTooDeep:
            "The selected JSON is nested more deeply than OpenTV allows."
        case .malformedCSV:
            "OpenTV could not read the structure of this CSV file."
        }
    }
}

enum LibraryImportFileReader {
    private static let chunkSize = 1_024 * 1_024

    /// Checks the logical file size before allocation, then performs a capped read so a file
    /// replacement between the resource check and the read cannot grow memory without bound.
    static func read(from url: URL) throws -> Data {
        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize >= 0 else {
                throw LibraryTransferError.unreadableFile
            }

            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }

            let prefix = try handle.read(upToCount: 4) ?? Data()
            let maximumSize = TVTimeImportService.isZIPArchive(prefix)
                ? LibraryImportLimits.maximumZIPFileSize
                : LibraryImportLimits.maximumLibraryFileSize
            guard fileSize <= maximumSize else {
                throw LibraryImportSafetyError.fileTooLarge
            }

            var data = Data()
            data.reserveCapacity(fileSize)
            data.append(prefix)
            while true {
                let remaining = maximumSize - data.count
                let readSize = min(chunkSize, remaining + 1)
                guard let chunk = try handle.read(upToCount: readSize), !chunk.isEmpty else {
                    break
                }
                data.append(chunk)
                guard data.count <= maximumSize else {
                    throw LibraryImportSafetyError.fileTooLarge
                }
            }
            return data
        } catch let error as LibraryImportSafetyError {
            throw error
        } catch let error as LibraryTransferError {
            throw error
        } catch {
            throw LibraryTransferError.unreadableFile
        }
    }
}

enum BoundedCSVParser {
    static func rows(
        _ csv: String,
        maximumRecordCount: Int = LibraryImportLimits.maximumRecordCount,
        maximumFieldSize: Int = LibraryImportLimits.maximumFieldSize,
        maximumValueCount: Int = LibraryImportLimits.maximumCSVValueCount
    ) throws -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        let bytes = csv.utf8
        var fieldBytes: [UInt8] = []
        fieldBytes.reserveCapacity(min(maximumFieldSize, 4_096))
        var valueCount = 0
        var isQuoted = false
        var index = bytes.startIndex

        func appendToField(_ byte: UInt8) throws {
            guard fieldBytes.count < maximumFieldSize else {
                throw LibraryImportSafetyError.fieldTooLarge
            }
            fieldBytes.append(byte)
        }

        func finishField() throws {
            guard row.count < LibraryImportLimits.maximumCSVFieldCount else {
                throw LibraryImportSafetyError.tooManyFields
            }
            valueCount += 1
            guard valueCount <= maximumValueCount else {
                throw LibraryImportSafetyError.tooManyValues
            }
            row.append(String(decoding: fieldBytes, as: UTF8.self))
            fieldBytes.removeAll(keepingCapacity: true)
        }

        func finishRow() throws {
            try finishField()
            // The first logical row is the header and is not an imported record.
            guard rows.count < maximumRecordCount + 1 else {
                throw LibraryImportSafetyError.tooManyRecords
            }
            rows.append(row)
            row = []
        }

        while index != bytes.endIndex {
            let byte = bytes[index]
            let next = bytes.index(after: index)
            if byte == 0x22 {
                if isQuoted, next != bytes.endIndex, bytes[next] == 0x22 {
                    try appendToField(0x22)
                    index = bytes.index(after: next)
                    continue
                } else {
                    isQuoted.toggle()
                }
            } else if byte == 0x2C, !isQuoted {
                try finishField()
            } else if byte == 0x0A, !isQuoted {
                try finishRow()
            } else if byte != 0x0D || isQuoted {
                try appendToField(byte)
            }
            index = next
        }

        guard !isQuoted else {
            throw LibraryImportSafetyError.malformedCSV
        }
        if !fieldBytes.isEmpty || !row.isEmpty {
            try finishRow()
        }
        return rows
    }
}

enum LibraryJSONImportValidator {
    static func validateEncodedFields(in data: Data) throws {
        var isInsideString = false
        var isEscaped = false
        var fieldSize = 0
        var depth = 0
        var separatorCount = 0
        var containerSeparatorCounts: [Int] = []

        for byte in data {
            if isInsideString {
                if !isEscaped, byte == 0x22 {
                    isInsideString = false
                    fieldSize = 0
                    continue
                }
                fieldSize += 1
                guard fieldSize <= LibraryImportLimits.maximumFieldSize else {
                    throw LibraryImportSafetyError.fieldTooLarge
                }
                if isEscaped {
                    isEscaped = false
                } else if byte == 0x5C {
                    isEscaped = true
                }
                continue
            }

            switch byte {
            case 0x22:
                isInsideString = true
                fieldSize = 0
            case 0x5B, 0x7B:
                depth += 1
                guard depth <= LibraryImportLimits.maximumJSONDepth else {
                    throw LibraryImportSafetyError.structureTooDeep
                }
                containerSeparatorCounts.append(0)
            case 0x5D, 0x7D:
                depth = max(depth - 1, 0)
                if !containerSeparatorCounts.isEmpty {
                    containerSeparatorCounts.removeLast()
                }
            case 0x2C:
                separatorCount += 1
                if let containerIndex = containerSeparatorCounts.indices.last {
                    containerSeparatorCounts[containerIndex] += 1
                    let containerSeparatorCount = containerSeparatorCounts[containerIndex]
                    guard containerSeparatorCount < LibraryImportLimits.maximumRecordCount else {
                        throw LibraryImportSafetyError.tooManyRecords
                    }
                }
                guard separatorCount <= LibraryImportLimits.maximumJSONSeparatorCount else {
                    throw LibraryImportSafetyError.tooManyValues
                }
            default:
                break
            }
        }
    }

    static func validateCollections(in snapshot: LibrarySnapshot) throws {
        var valueCount = 0
        try validate(snapshot, valueCount: &valueCount)
    }

    private static func validate(_ value: Any, valueCount: inout Int) throws {
        if let string = value as? String {
            guard string.utf8.count <= LibraryImportLimits.maximumFieldSize else {
                throw LibraryImportSafetyError.fieldTooLarge
            }
            return
        }
        if let url = value as? URL {
            guard url.absoluteString.utf8.count <= LibraryImportLimits.maximumFieldSize else {
                throw LibraryImportSafetyError.fieldTooLarge
            }
            return
        }
        if value is Date || value is Data {
            return
        }

        let mirror = Mirror(reflecting: value)
        switch mirror.displayStyle {
        case .collection, .dictionary, .set:
            let count = mirror.children.count
            guard count <= LibraryImportLimits.maximumRecordCount else {
                throw LibraryImportSafetyError.tooManyRecords
            }
            guard count <= LibraryImportLimits.maximumDecodedValueCount - valueCount else {
                throw LibraryImportSafetyError.tooManyValues
            }
            valueCount += count
        default:
            break
        }
        for child in mirror.children {
            try validate(child.value, valueCount: &valueCount)
        }
    }
}

enum ImportedLibraryMetadataSanitizer {
    private static let artworkHosts: Set<String> = [
        "image.tmdb.org",
        "media.themoviedb.org",
        "static.tvmaze.com"
    ]
    private static let avatarHosts: Set<String> = [
        "image.tmdb.org",
        "media.themoviedb.org",
        "secure.gravatar.com"
    ]
    private static let catalogLinkHosts: Set<String> = [
        "themoviedb.org",
        "www.themoviedb.org",
        "trakt.tv",
        "www.trakt.tv",
        "tvmaze.com",
        "www.tvmaze.com"
    ]
    private static let reviewLinkHosts: Set<String> = [
        "themoviedb.org",
        "www.themoviedb.org"
    ]
    private static let trailerHosts: Set<String> = [
        "fxnetworks.com",
        "www.fxnetworks.com",
        "m.youtube.com",
        "netflix.com",
        "www.netflix.com",
        "primevideo.com",
        "www.primevideo.com",
        "tv.apple.com",
        "youtu.be",
        "www.youtu.be",
        "youtube.com",
        "www.youtube.com",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com"
    ]

    static func sanitized(_ snapshot: LibrarySnapshot) -> LibrarySnapshot {
        var result = snapshot
        result.titles = snapshot.titles.map(sanitized)
        result.sharedSpace.titleMetadata = snapshot.sharedSpace.titleMetadata?.map(sanitized)
        return result
    }

    private static func sanitized(_ source: MediaTitle) -> MediaTitle {
        var title = source
        title.posterURL = normalizedArtworkURL(source.posterURL)
        title.backdropURL = normalizedArtworkURL(source.backdropURL)
        title.trailerURL = normalizedHTTPSURL(source.trailerURL, allowedHosts: trailerHosts)
        title.sourceURL = normalizedHTTPSURL(source.sourceURL, allowedHosts: catalogLinkHosts)
        title.reviews = source.reviews.map { review in
            var result = review
            result.avatarURL = normalizedAvatarURL(review.avatarURL)
            result.sourceURL = normalizedHTTPSURL(review.sourceURL, allowedHosts: reviewLinkHosts)
            return result
        }
        title.seasons = source.seasons?.map { season in
            SeasonSummary(
                id: season.id,
                number: season.number,
                title: season.title,
                episodes: season.episodes.map { episode in
                    var result = episode
                    result.stillURL = normalizedArtworkURL(episode.stillURL)
                    return result
                },
                artworkURL: normalizedArtworkURL(season.artworkURL)
            )
        }
        return title
    }

    private static func normalizedArtworkURL(_ url: URL?) -> URL? {
        guard let normalized = normalizedHTTPSURL(url, allowedHosts: artworkHosts),
              var components = URLComponents(
                url: normalized,
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        components.query = nil
        return components.url
    }

    private static func normalizedAvatarURL(_ url: URL?) -> URL? {
        guard let normalized = normalizedHTTPSURL(url, allowedHosts: avatarHosts),
              var components = URLComponents(
                url: normalized,
                resolvingAgainstBaseURL: false
              ) else {
            return nil
        }
        guard components.host == "secure.gravatar.com" else {
            components.query = nil
            return components.url
        }

        let pathComponents = components.path.split(separator: "/", omittingEmptySubsequences: true)
        guard pathComponents.count == 2, pathComponents[0].lowercased() == "avatar" else {
            return nil
        }
        var safeQueryItems: [URLQueryItem] = []
        var seenQueryNames = Set<String>()
        for item in components.queryItems ?? [] {
            let name = item.name.lowercased()
            guard seenQueryNames.insert(name).inserted, let value = item.value else { continue }
            if name == "s" || name == "size",
               value.count <= 4,
               let size = Int(value),
               1...2_048 ~= size {
                safeQueryItems.append(URLQueryItem(name: name, value: String(size)))
            } else if name == "r" || name == "rating",
                      ["g", "pg", "r", "x"].contains(value.lowercased()) {
                safeQueryItems.append(URLQueryItem(name: name, value: value.lowercased()))
            }
        }
        components.queryItems = safeQueryItems.isEmpty ? nil : safeQueryItems
        return components.url
    }

    private static func normalizedHTTPSURL(
        _ url: URL?,
        allowedHosts: Set<String>
    ) -> URL? {
        guard let url,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              let host = components.host?.lowercased(),
              allowedHosts.contains(host) else {
            return nil
        }
        components.scheme = "https"
        components.host = host
        components.port = nil
        components.fragment = nil
        return components.url
    }
}
