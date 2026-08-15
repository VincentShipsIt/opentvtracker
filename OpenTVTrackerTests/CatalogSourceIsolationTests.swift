import XCTest
@testable import OpenTVTracker

/// TMDB and TVmaze numeric IDs share `MediaTitle.catalogID`. Anything that
/// joins on the bare number must also respect the metadata source.
final class CatalogSourceIsolationTests: XCTestCase {
    func testTraktMediaKeyIgnoresTVmazeTitles() {
        XCTAssertEqual(
            TraktMediaKey(title: Self.tmdbTitle),
            TraktMediaKey(kind: .series, tmdbID: 95_396)
        )
        XCTAssertNil(TraktMediaKey(title: Self.tvmazeTitle))
        XCTAssertFalse(TraktMediaKey(kind: .series, tmdbID: 95_396).matches(Self.tvmazeTitle))
    }

    func testTraktSyncDoesNotAttachRemoteHistoryToTVmazeTitleWithSameNumber() {
        var snapshot = LibrarySnapshot.empty
        var tvmaze = Self.tvmazeTitle
        tvmaze.personalWatchlist = true
        tvmaze.userRating = 8
        snapshot.titles = [tvmaze]
        let media = TraktMediaKey(kind: .series, tmdbID: 95_396)

        let plan = TraktSyncEngine.plan(
            local: snapshot,
            remote: TraktRemoteSnapshot(
                activityAt: .now,
                history: [
                    TraktHistoryItem(id: 1, media: media, season: 1, episode: 1, watchedAt: .now)
                ],
                ratings: [],
                watchlist: [],
                lists: []
            )
        )

        let title = plan.snapshot.titles[0]
        XCTAssertEqual(title.id, tvmaze.id)
        XCTAssertNil(title.watchedEpisodeIDs)
        XCTAssertEqual(title.state, .planned)
        XCTAssertTrue(plan.outbound.watchlistToAdd.isEmpty)
        XCTAssertTrue(plan.outbound.ratingsToAdd.isEmpty)
        XCTAssertEqual(TraktSyncEngine.pendingChangeCount(in: snapshot), 0)
    }

    func testImportAliasMatchesOnlyItsOwnSource() {
        let alias = ImportResolutionAlias(title: Self.tvmazeTitle)

        XCTAssertEqual(alias.resolvedMetadataSource, .tvmaze)
        XCTAssertTrue(alias.matches(Self.tvmazeTitle))
        XCTAssertFalse(alias.matches(Self.tmdbTitle))
        XCTAssertFalse(ImportResolutionAlias(title: Self.tmdbTitle).matches(Self.tvmazeTitle))
    }

    func testLegacyAliasWithoutSourceDecodesAsTMDB() throws {
        let data = Data(#"{"kind":"series","catalogID":95396}"#.utf8)
        let alias = try JSONDecoder.openTV.decode(ImportResolutionAlias.self, from: data)

        XCTAssertNil(alias.metadataSource)
        XCTAssertEqual(alias.resolvedMetadataSource, .tmdb)
        XCTAssertTrue(alias.matches(Self.tmdbTitle))
        XCTAssertFalse(alias.matches(Self.tvmazeTitle))
    }

    func testCSVExportCarriesMetadataSourceAndImportHonoursIt() throws {
        var snapshot = LibrarySnapshot.empty
        snapshot.titles = [Self.tmdbTitle, Self.tvmazeTitle]

        let csv = try XCTUnwrap(
            String(data: LibraryTransferService.exportTitlesCSV(snapshot), encoding: .utf8)
        )
        let lines = csv.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines[0].hasSuffix(",metadata_source"))
        XCTAssertTrue(lines.contains { $0.hasSuffix(",TMDB") })
        XCTAssertTrue(lines.contains { $0.hasSuffix(",TVmaze") })

        let update = """
        catalog_id,title,year,state,metadata_source
        95396,Severance,2022,completed,tvmaze
        """
        let preview = try LibraryTransferService.previewImport(Data(update.utf8), into: snapshot)
        let tmdb = try XCTUnwrap(preview.snapshot.titles.first { $0.id == Self.tmdbTitle.id })
        let tvmaze = try XCTUnwrap(preview.snapshot.titles.first { $0.id == Self.tvmazeTitle.id })

        XCTAssertEqual(tvmaze.state, .completed)
        XCTAssertEqual(tmdb.state, Self.tmdbTitle.state)
    }

    private static let tmdbTitle = {
        var title = LibrarySnapshot.sample.titles.first { $0.id == "severance" }!
        title.metadataSource = .tmdb
        return title
    }()

    private static let tvmazeTitle = MediaTitle(
        id: "tvmaze-series-95396",
        catalogID: 95_396,
        title: "Severance",
        year: 2022,
        kind: .series,
        synopsis: "TVmaze copy that happens to share the TMDB number.",
        genres: ["Drama"],
        runtimeMinutes: 50,
        state: .planned,
        progress: nil,
        rating: 8.5,
        nextReleaseDescription: nil,
        recommendationReason: nil,
        mood: .any,
        palette: PosterPalette(primaryHex: "3D4E81", secondaryHex: "161A2C"),
        providers: [],
        reviews: [],
        metadataSource: .tvmaze
    )
}
