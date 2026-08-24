import XCTest
@testable import OpenTVTracker

struct CancellingCatalog: CatalogProviding {
    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        throw CancellationError()
    }

    func title(kind _: MediaKind, catalogID _: Int, region _: StreamingRegion) async throws -> MediaTitle {
        throw CancellationError()
    }
}

actor ControlledResolutionCatalog: CatalogProviding {
    let titles: [MediaTitle]
    private(set) var requestedCatalogIDs: [Int] = []
    private var releasedCatalogIDs: Set<Int> = []

    init(titles: [MediaTitle]) {
        self.titles = titles
    }

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        []
    }

    func title(
        kind: MediaKind,
        catalogID: Int,
        region _: StreamingRegion
    ) async throws -> MediaTitle {
        requestedCatalogIDs.append(catalogID)
        while !releasedCatalogIDs.contains(catalogID) {
            try Task.checkCancellation()
            await Task.yield()
        }
        guard let title = titles.first(where: {
            $0.kind == kind && $0.catalogID == catalogID
        }) else {
            throw CatalogServiceError.notFound
        }
        return title
    }

    func waitUntilRequested(catalogID: Int) async {
        while !requestedCatalogIDs.contains(catalogID) {
            await Task.yield()
        }
    }

    func hasRequested(catalogID: Int) -> Bool {
        requestedCatalogIDs.contains(catalogID)
    }

    func release(catalogID: Int) {
        releasedCatalogIDs.insert(catalogID)
    }
}

actor StubCatalog: CatalogProviding {
    private let searchResults: [MediaTitle]
    private let resolvedTitle: MediaTitle?
    private let failsAllRequests: Bool
    private var searchCallCount = 0
    private var resolveCallCount = 0

    init(
        searchResults: [MediaTitle] = [],
        resolvedTitle: MediaTitle? = nil,
        failsAllRequests: Bool = false
    ) {
        self.searchResults = searchResults
        self.resolvedTitle = resolvedTitle
        self.failsAllRequests = failsAllRequests
    }

    func search(_: MediaSearchQuery) async throws -> [MediaTitle] {
        searchCallCount += 1
        if failsAllRequests { throw StubCatalogError.unavailable }
        return searchResults
    }

    func title(
        kind: MediaKind,
        catalogID: Int,
        region _: StreamingRegion
    ) async throws -> MediaTitle {
        if failsAllRequests { throw StubCatalogError.unavailable }
        if let resolvedTitle,
           resolvedTitle.kind == kind,
           resolvedTitle.catalogID == catalogID {
            return resolvedTitle
        }
        guard let title = searchResults.first(where: {
            $0.kind == kind && $0.catalogID == catalogID
        }) else {
            throw CatalogServiceError.notFound
        }
        return title
    }

    func resolve(
        _: ExternalCatalogReference,
        region _: StreamingRegion
    ) async throws -> MediaTitle? {
        resolveCallCount += 1
        if failsAllRequests { throw StubCatalogError.unavailable }
        return resolvedTitle
    }

    func callCounts() -> (search: Int, resolve: Int) {
        (searchCallCount, resolveCallCount)
    }
}

enum StubCatalogError: Error {
    case unavailable
}

extension TVTimeImportTests {
    func testZIPWithoutTVTimeTrackingDataIsRejected() async throws {
        let archive = try makeArchive(["profile.csv": "name\nVincent\n"])

        do {
            _ = try await TVTimeImportService.previewImport(
                archive,
                into: .sample,
                catalog: LocalCatalogService(titles: LibrarySnapshot.sample.titles),
                region: .malta
            )
            XCTFail("Expected unsupported TV Time data to be rejected")
        } catch let error as TVTimeImportError {
            XCTAssertEqual(error.errorDescription, "This ZIP does not contain recognizable TV Time tracking data.")
        }
    }

    func testZIPRejectsCaseInsensitiveDuplicateRecognizedFullPaths() throws {
        let archive = try makeArchive([
            (
                path: "Exports/TRACKING-PROD-RECORDS-V2.CSV",
                contents: "key,s_id,series_name,s_no,ep_no\nfirst,42,Severance,1,1\n"
            ),
            (
                path: "exports/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nsecond,42,Severance,1,2\n"
            )
        ])

        XCTAssertThrowsError(try TVTimeZIPReader.recognizedFiles(in: archive)) { error in
            guard let importError = error as? TVTimeImportError,
                  case .duplicateRecognizedPath = importError else {
                return XCTFail("Expected duplicateRecognizedPath, got \(error)")
            }
        }
    }

    func testZIPRejectsUnicodeCaseFoldDuplicateRecognizedFullPaths() throws {
        let archive = try makeArchive([
            (
                path: "Σ/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nfirst,42,Severance,1,1\n"
            ),
            (
                path: "ς/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nsecond,42,Severance,1,2\n"
            )
        ])

        XCTAssertThrowsError(try TVTimeZIPReader.recognizedFiles(in: archive)) { error in
            guard let importError = error as? TVTimeImportError,
                  case .duplicateRecognizedPath = importError else {
                return XCTFail("Expected duplicateRecognizedPath, got \(error)")
            }
        }
    }

    func testZIPRejectsMultiScalarCaseFoldDuplicateRecognizedFullPaths() throws {
        let archive = try makeArchive([
            (
                path: "Straße/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nfirst,42,Severance,1,1\n"
            ),
            (
                path: "STRASSE/tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nsecond,42,Severance,1,2\n"
            )
        ])

        XCTAssertThrowsError(try TVTimeZIPReader.recognizedFiles(in: archive)) { error in
            guard let importError = error as? TVTimeImportError,
                  case .duplicateRecognizedPath = importError else {
                return XCTFail("Expected duplicateRecognizedPath, got \(error)")
            }
        }
    }

    func testBoundedExtractionRejectsUnderreportedOutputBeforeAppendingPastLimit() throws {
        let exact = try TVTimeZIPReader.boundedExtraction(
            declaredSize: 1,
            maximumSize: 4
        ) { consumer in
            try consumer(Data([0, 1]))
            try consumer(Data([2, 3]))
        }
        XCTAssertEqual(exact, Data([0, 1, 2, 3]))

        var completedConsumerCalls = 0
        XCTAssertThrowsError(
            try TVTimeZIPReader.boundedExtraction(
                declaredSize: 1,
                maximumSize: 4
            ) { consumer in
                try consumer(Data([0, 1, 2]))
                completedConsumerCalls += 1
                try consumer(Data([3, 4]))
                completedConsumerCalls += 1
            }
        ) { error in
            guard let importError = error as? TVTimeImportError,
                  case .archiveTooLarge = importError else {
                return XCTFail("Expected archiveTooLarge, got \(error)")
            }
        }
        XCTAssertEqual(completedConsumerCalls, 1)
    }

    func testZIPRejectsExcessiveTotalEntryCount() throws {
        var files = [
            (
                path: "tracking-prod-records-v2.csv",
                contents: "key,s_id,series_name,s_no,ep_no\nfirst,42,Severance,1,1\n"
            )
        ]
        files.append(contentsOf: (0..<LibraryImportLimits.maximumZIPEntryCount).map { index in
            (path: "unrecognized/entry-\(index).txt", contents: "")
        })
        let archive = try makeArchive(files)

        XCTAssertThrowsError(try TVTimeZIPReader.recognizedFiles(in: archive)) { error in
            guard let importError = error as? TVTimeImportError,
                  case .tooManyArchiveEntries = importError else {
                return XCTFail("Expected tooManyArchiveEntries, got \(error)")
            }
        }
    }

    func testGDPRListAggregateFieldMayExceedNormalFieldLimit() throws {
        let objects = String(
            repeating: "x",
            count: LibraryImportLimits.maximumFieldSize + 1
        )
        let archive = try makeArchive([
            "lists-prod-lists.csv": "name,objects\nLarge list,\(objects)\n"
        ])

        let parsed = try TVTimeArchiveParser.parse(archive)

        XCTAssertEqual(parsed.lists.map(\.name), ["Large list"])
    }
}
