import Foundation

enum TVTimeImportService {
    static func isZIPArchive(_ data: Data) -> Bool {
        data.count >= 4 && data.prefix(2) == Data([0x50, 0x4B])
    }

    static func previewImport(
        _ data: Data,
        into current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async throws -> LibraryImportPreview {
        let session = try await prepareImport(
            data,
            into: current,
            catalog: catalog,
            region: region
        )
        return await session.preview()
    }

    static func prepareImport(
        _ data: Data,
        into current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) async throws -> TVTimeImportSession {
        let tvTimeArchive = try await Task.detached(priority: .userInitiated) {
            try TVTimeArchiveParser.parse(data)
        }.value

        return TVTimeImportSession(
            archive: tvTimeArchive,
            current: current,
            catalog: catalog,
            region: region
        )
    }
}

actor TVTimeImportSession {
    private let archive: TVTimeArchive
    private let current: LibrarySnapshot
    private let catalog: any CatalogProviding
    private let region: StreamingRegion
    private var automaticResolution: TVTimeTitleResolution?
    private var automaticResolutionTask: Task<TVTimeTitleResolution, Never>?

    init(
        archive: TVTimeArchive,
        current: LibrarySnapshot,
        catalog: any CatalogProviding,
        region: StreamingRegion
    ) {
        self.archive = archive
        self.current = current
        self.catalog = catalog
        self.region = region
    }

    func preview(
        manualResolutions: [ImportResolutionIssue.ID: MediaTitle] = [:]
    ) async -> LibraryImportPreview {
        let resolution: TVTimeTitleResolution
        if let automaticResolution {
            resolution = automaticResolution
        } else if let automaticResolutionTask {
            resolution = await automaticResolutionTask.value
        } else {
            let entities = archive.entities
            let current = self.current
            let catalog = self.catalog
            let region = self.region
            let task = Task {
                await TVTimeImportMerger.resolveTitles(
                    entities,
                    current: current,
                    catalog: catalog,
                    region: region
                )
            }
            automaticResolutionTask = task
            let resolved = await task.value
            automaticResolution = resolved
            automaticResolutionTask = nil
            resolution = resolved
        }

        return TVTimeImportMerger.mergedPreview(
            archive,
            into: current,
            automaticResolution: resolution,
            manualResolutions: manualResolutions
        )
    }

    func search(
        _ text: String,
        kind: MediaKind
    ) async throws -> [MediaTitle] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let results = try await catalog.search(
            MediaSearchQuery(text: trimmed, kind: kind, page: 1, region: region)
        )
        var seen = Set<MediaTitle.ID>()
        return results.filter { $0.kind == kind && seen.insert($0.id).inserted }
    }

    func detailedTitle(_ candidate: MediaTitle) async throws -> MediaTitle {
        try await catalog.title(
            kind: candidate.kind,
            catalogID: candidate.catalogID,
            region: region
        )
    }
}

struct TVTimeArchive: Sendable {
    var entities: [TVTimeEntity]
    var lists: [TVTimeList] = []
    var duplicateCount: Int
    var diagnostics: TVTimeImportDiagnostics

    func containsListOnly(_ entity: TVTimeEntity) -> Bool {
        !entity.hasTrackingData
            && lists.contains { list in
                list.memberships.contains { $0.entityIdentity == entity.identity }
            }
    }
}

struct TVTimeImportDiagnostics: Sendable {
    var missingIdentityCount = 0
    var unsupportedRecordCount = 0
    var unsupportedEpisodeRatingCount = 0
    var unreadableFileCount = 0
}

struct TVTimeEntity: Sendable {
    let identity: String
    var sourceID: String?
    // swiftlint:disable:next implicit_optional_initialization
    var source: ExternalCatalogSource? = nil
    var title: String
    var year: Int?
    var kind: MediaKind
    var isFollowed = false
    var isForLater = false
    var isArchived = false
    var rating: Double?
    var rewatchCount = 0
    var watches: [TVTimeWatch] = []

    var importedRewatchCount: Int {
        if kind == .movie {
            return [
                rewatchCount,
                max(watches.count - 1, 0),
                watches.filter(\.isRewatch).count
            ].max() ?? 0
        }
        return watches.reduce(0) {
            $0 + $1.importedRewatchCount
        }
    }
}

extension TVTimeEntity {
    var hasTrackingData: Bool {
        isFollowed
            || isForLater
            || isArchived
            || rating != nil
            || rewatchCount > 0
            || !watches.isEmpty
    }
}

struct TVTimeWatch: Hashable, Sendable {
    var season: Int?
    var episode: Int?
    var occurredAt: Date?
    var rating: Double?
    var isRewatch: Bool
    var rewatchCount = 0

    func hasSameIdentity(as other: TVTimeWatch) -> Bool {
        season == other.season
            && episode == other.episode
            && occurredAt == other.occurredAt
            && isRewatch == other.isRewatch
    }

    var importedRewatchCount: Int {
        max(rewatchCount, isRewatch ? 1 : 0)
    }
}

struct TVTimeList: Sendable {
    let id: MediaList.ID
    var name: String
    var memberships: [TVTimeListMembership]
}

struct TVTimeListMembership: Hashable, Sendable {
    let entityIdentity: String
    let order: Int
}

enum TVTimeImportError: LocalizedError {
    case emptyArchive
    case invalidArchive
    case archiveTooLarge
    case noSupportedData

    var errorDescription: String? {
        switch self {
        case .emptyArchive: "The TV Time export ZIP is empty."
        case .invalidArchive: "OpenTV could not read this TV Time export ZIP."
        case .archiveTooLarge: "This archive is too large to import safely."
        case .noSupportedData: "This ZIP does not contain recognizable TV Time tracking data."
        }
    }
}
