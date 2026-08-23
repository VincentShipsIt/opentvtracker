import Foundation
import XCTest
@testable import OpenTVTracker

@MainActor
final class ContentLanguageTests: XCTestCase {
    func testLanguageCodesAreValidatedAndNormalized() throws {
        XCTAssertEqual(try XCTUnwrap(ContentLanguage(code: " FR-fr ")).code, "fr")
        XCTAssertNil(ContentLanguage(code: "not-a-language"))
    }

    func testDeviceDefaultUsesPreferredLocaleLanguage() {
        let locale = Locale(identifier: "fr_MT")

        XCTAssertEqual(ContentLanguage.deviceDefault(locale: locale).code, "fr")
    }

    func testLanguageOverridePersistsWithoutReplacingAutomaticDefault() async throws {
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: .sample)
        let language = try XCTUnwrap(ContentLanguage(code: "fr"))

        model.setContentLanguageOverride(language)
        await model.flushPendingPersistence()
        let saved = try await store.load()

        XCTAssertEqual(model.contentLanguageOverride, language)
        XCTAssertEqual(saved?.contentLanguageCode, "fr")
    }

    func testLanguageChangePersistsUntrackedCatalogCleanupAcrossReload() async throws {
        let disposableTitle = try disposableCatalogTitle()
        let seed = LibrarySnapshot(
            titles: [disposableTitle],
            sharedSpace: LibrarySnapshot.empty.sharedSpace,
            streamingRegionCode: "MT",
            contentLanguageCode: "en"
        )
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: seed)
        let language = try XCTUnwrap(ContentLanguage(code: "fr"))

        model.setContentLanguageOverride(language)
        await model.flushPendingPersistence()

        let reloaded = makeReloadedModel(store: store)
        await reloaded.load()

        XCTAssertFalse(reloaded.titles.contains(where: { $0.id == disposableTitle.id }))
        XCTAssertEqual(reloaded.contentLanguageOverride, language)
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
