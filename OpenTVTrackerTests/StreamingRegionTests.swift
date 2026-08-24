import Foundation
import XCTest
@testable import OpenTVTracker

@MainActor
final class StreamingRegionTests: XCTestCase {
    func testRegionCodesAreValidatedAndNormalized() throws {
        XCTAssertEqual(try XCTUnwrap(StreamingRegion(code: " mt ")).code, "MT")
        XCTAssertNil(StreamingRegion(code: "not-a-region"))
    }

    func testDeviceDefaultUsesLocaleRegionWithoutLocationAccess() {
        let locale = Locale(identifier: "en_MT")

        XCTAssertEqual(StreamingRegion.deviceDefault(locale: locale), .malta)
    }

    func testServerSearchAndDetailsIncludeSelectedRegion() throws {
        let service = ServerCatalogService(baseURL: try XCTUnwrap(URL(string: "https://example.com")))
        let region = try XCTUnwrap(StreamingRegion(code: "US"))

        let searchURL = try service.searchURL(
            for: MediaSearchQuery(text: "Severance", kind: .series, page: 2, region: region)
        )
        let detailURL = try service.titleURL(kind: .series, catalogID: 95_396, region: region)
        let reviewsURL = try service.reviewsURL(kind: .series, catalogID: 95_396, page: 3)

        XCTAssertEqual(queryValue("region", in: searchURL), "US")
        XCTAssertEqual(queryValue("region", in: detailURL), "US")
        XCTAssertEqual(queryValue("language", in: searchURL), "en")
        XCTAssertEqual(queryValue("language", in: detailURL), "en")
        XCTAssertEqual(queryValue("page", in: reviewsURL), "3")
        XCTAssertEqual(reviewsURL.path, "/v1/catalog/series/95396/reviews")
    }

    func testServerSearchAndDetailsIncludeSelectedContentLanguage() throws {
        let service = ServerCatalogService(baseURL: try XCTUnwrap(URL(string: "https://example.com")))
        let language = try XCTUnwrap(ContentLanguage(code: "fr"))

        let searchURL = try service.searchURL(
            for: MediaSearchQuery(
                text: "",
                kind: nil,
                page: 1,
                region: .malta,
                contentLanguage: language
            )
        )
        let detailURL = try service.titleURL(
            kind: .series,
            catalogID: 95_396,
            region: .malta,
            contentLanguage: language
        )

        XCTAssertEqual(queryValue("language", in: searchURL), "fr")
        XCTAssertEqual(queryValue("language", in: detailURL), "fr")
    }

    func testRegionOverridePersistsWithoutReplacingAutomaticDefault() async throws {
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: .sample)
        let region = try XCTUnwrap(StreamingRegion(code: "GB"))

        model.setStreamingRegionOverride(region)
        await model.flushPendingPersistence()
        let saved = try await store.load()

        XCTAssertEqual(model.streamingRegionOverride, region)
        XCTAssertEqual(saved?.streamingRegionCode, "GB")
    }

    func testRegionChangePersistsUntrackedCatalogCleanupAcrossReload() async throws {
        let disposableTitle = try disposableCatalogTitle()
        let seed = LibrarySnapshot(
            titles: [disposableTitle],
            sharedSpace: LibrarySnapshot.empty.sharedSpace,
            streamingRegionCode: "MT",
            contentLanguageCode: "en"
        )
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: seed)
        let region = try XCTUnwrap(StreamingRegion(code: "GB"))

        model.setStreamingRegionOverride(region)
        await model.flushPendingPersistence()

        let reloaded = makeReloadedModel(store: store)
        await reloaded.load()

        XCTAssertFalse(reloaded.titles.contains(where: { $0.id == disposableTitle.id }))
        XCTAssertEqual(reloaded.streamingRegionOverride, region)
    }

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }

    private func disposableCatalogTitle() throws -> MediaTitle {
        var title = try XCTUnwrap(LibrarySnapshot.sample.titles.first(where: { $0.id == "fallout" }))
        title.state = .planned
        title.progress = nil
        title.personalWatchlist = false
        title.userRating = nil
        title.notes = nil
        title.rewatchCount = nil
        title.lastWatchedAt = nil
        title.isUpNextPinned = nil
        title.upNextSnoozedUntil = nil
        title.upNextManualOrder = nil
        title.watchedEpisodeIDs = []
        return title
    }

    private func makeReloadedModel(store: any LibraryPersisting) -> AppModel {
        AppModel(
            store: store,
            recommendationService: DeterministicRecommendationService(),
            sharedConversationNotifier: NoopSharedConversationNotifier(),
            reminderScheduler: NoopReminderScheduler(),
            partnerActivityNotifier: NoopPartnerActivityNotifier(),
            catalogService: LocalCatalogService(titles: []),
            traktService: UnconfiguredTraktSyncService(),
            seed: .empty
        )
    }
}
