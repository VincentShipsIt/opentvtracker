import Foundation

extension LibraryTransferService {
    static func backupPreview(
        snapshot: LibrarySnapshot,
        imported: LibrarySnapshot,
        current: LibrarySnapshot,
        titleCounts: LibraryTitleImportCounts,
        listCounts: LibraryListImportCounts
    ) -> LibraryImportPreview {
        LibraryImportPreview(
            snapshot: snapshot,
            matchedCount: titleCounts.matched,
            addedCount: titleCounts.added,
            duplicateCount: titleCounts.duplicates,
            skippedCount: 0,
            sourceName: "OpenTV backup",
            watchedEpisodeCount: imported.titles.reduce(0) {
                $0 + ($1.watchedEpisodeIDs?.count ?? 0)
            },
            watchEventCount: imported.sharedSpace.watchEvents?.count ?? 0,
            listCount: listCounts.lists,
            listMembershipCount: listCounts.memberships,
            importNotice: LibraryBackupMerge.importNotice(
                for: imported,
                current: current
            )
        )
    }
}

enum LibraryJSONImportValidator {
    static func validateEncodedFields(in data: Data) throws {
        var scanner = LibraryJSONEncodedFieldScanner()
        try scanner.validate(data)
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

private struct LibraryJSONEncodedFieldScanner {
    private var isInsideString = false
    private var isEscaped = false
    private var fieldSize = 0
    private var depth = 0
    private var separatorCount = 0
    private var containerSeparatorCounts: [Int] = []

    mutating func validate(_ data: Data) throws {
        for byte in data {
            try consume(byte)
        }
    }

    private mutating func consume(_ byte: UInt8) throws {
        if isInsideString {
            try consumeStringByte(byte)
            return
        }
        switch byte {
        case 0x22:
            isInsideString = true
            fieldSize = 0
        case 0x5B, 0x7B:
            try openContainer()
        case 0x5D, 0x7D:
            closeContainer()
        case 0x2C:
            try consumeSeparator()
        default:
            break
        }
    }

    private mutating func consumeStringByte(_ byte: UInt8) throws {
        if !isEscaped, byte == 0x22 {
            isInsideString = false
            fieldSize = 0
            return
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
    }

    private mutating func openContainer() throws {
        depth += 1
        guard depth <= LibraryImportLimits.maximumJSONDepth else {
            throw LibraryImportSafetyError.structureTooDeep
        }
        containerSeparatorCounts.append(0)
    }

    private mutating func closeContainer() {
        depth = max(depth - 1, 0)
        if !containerSeparatorCounts.isEmpty {
            containerSeparatorCounts.removeLast()
        }
    }

    private mutating func consumeSeparator() throws {
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
        sanitizeNumericMetadata(from: source, into: &title)
        sanitizeRemoteMetadata(from: source, into: &title)
        return title
    }

    private static func sanitizeNumericMetadata(
        from source: MediaTitle,
        into title: inout MediaTitle
    ) {
        title.runtimeMinutes = LibraryImportLimits.boundedRuntimeMinutes(source.runtimeMinutes)
        title.rewatchCount = source.rewatchCount.map(LibraryImportLimits.boundedRewatchCount)
        title.upNextManualOrder = source.upNextManualOrder.map(
            LibraryImportLimits.boundedOrderingValue
        )
        title.progress = source.progress.map(sanitized)
    }

    private static func sanitizeRemoteMetadata(
        from source: MediaTitle,
        into title: inout MediaTitle
    ) {
        title.posterURL = normalizedArtworkURL(source.posterURL)
        title.backdropURL = normalizedArtworkURL(source.backdropURL)
        title.trailerURL = normalizedHTTPSURL(source.trailerURL, allowedHosts: trailerHosts)
        title.sourceURL = normalizedHTTPSURL(source.sourceURL, allowedHosts: catalogLinkHosts)
        title.reviews = source.reviews.map(sanitized)
        title.seasons = source.seasons?.map(sanitized)
    }

    private static func sanitized(_ progress: EpisodeProgress) -> EpisodeProgress {
        let totalEpisodes = max(
            LibraryImportLimits.boundedProgressValue(progress.totalEpisodes),
            1
        )
        return EpisodeProgress(
            season: max(LibraryImportLimits.boundedProgressValue(progress.season), 1),
            episode: min(
                LibraryImportLimits.boundedProgressValue(progress.episode),
                totalEpisodes
            ),
            totalEpisodes: totalEpisodes
        )
    }

    private static func sanitized(_ source: CommunityReview) -> CommunityReview {
        var review = source
        review.avatarURL = normalizedAvatarURL(source.avatarURL)
        review.sourceURL = normalizedHTTPSURL(source.sourceURL, allowedHosts: reviewLinkHosts)
        return review
    }

    private static func sanitized(_ season: SeasonSummary) -> SeasonSummary {
        SeasonSummary(
            id: season.id,
            number: LibraryImportLimits.boundedProgressValue(season.number),
            title: season.title,
            episodes: season.episodes.map(sanitized),
            artworkURL: normalizedArtworkURL(season.artworkURL)
        )
    }

    private static func sanitized(_ episode: EpisodeSummary) -> EpisodeSummary {
        EpisodeSummary(
            id: episode.id,
            number: LibraryImportLimits.boundedProgressValue(episode.number),
            title: episode.title,
            airDate: episode.airDate,
            runtimeMinutes: episode.runtimeMinutes.map(LibraryImportLimits.boundedRuntimeMinutes),
            overview: episode.overview,
            stillURL: normalizedArtworkURL(episode.stillURL),
            rating: episode.rating,
            releaseType: episode.releaseType,
            airDateIsAllDay: episode.airDateIsAllDay
        )
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
