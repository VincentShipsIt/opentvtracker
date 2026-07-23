import XCTest
@testable import OpenTVTracker

@MainActor
final class FirstRunTests: XCTestCase {
    func testProviderBadgeForegroundMaximizesContrast() {
        XCTAssertEqual(AppAccessibility.readableForeground(forHex: "#FFFFFF"), .dark)
        XCTAssertEqual(AppAccessibility.readableForeground(forHex: "000000"), .light)
        XCTAssertEqual(AppAccessibility.readableForeground(forHex: "F5C518"), .dark)
        XCTAssertEqual(AppAccessibility.readableForeground(forHex: "invalid"), .light)
    }

    func testAvatarInitialsStayInsideCompactCircularBadges() {
        XCTAssertEqual(AppAccessibility.displayedInitials("YOU"), "YO")
        XCTAssertEqual(AppAccessibility.displayedInitials(" v s "), "VS")
        XCTAssertEqual(AppAccessibility.displayedInitials("Å"), "Å")
    }

    func testFirstRunCompletionPersistsForFreshLibrary() async throws {
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: .empty)

        XCTAssertFalse(model.hasCompletedFirstRun)

        model.completeFirstRun()
        await model.flushPendingPersistence()
        let saved = try await store.load()

        XCTAssertTrue(model.hasCompletedFirstRun)
        XCTAssertEqual(saved?.hasCompletedFirstRun, true)
    }

    func testSeededLibraryDoesNotReopenFirstRun() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        XCTAssertTrue(model.hasCompletedFirstRun)
    }

    func testSelectingFirstRunTitlePopulatesUpNextAndCanBeUndone() throws {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        model.toggleFirstRunTitle("slow-horses")

        let selected = try XCTUnwrap(model.mediaTitle(withID: "slow-horses"))
        XCTAssertEqual(selected.state, .watching)
        XCTAssertTrue(selected.isOnPersonalWatchlist)
        XCTAssertTrue(model.upNext.contains(where: { $0.id == selected.id }))

        model.toggleFirstRunTitle("slow-horses")

        let removed = try XCTUnwrap(model.mediaTitle(withID: "slow-horses"))
        XCTAssertEqual(removed.state, .planned)
        XCTAssertFalse(removed.isOnPersonalWatchlist)
        XCTAssertFalse(model.upNext.contains(where: { $0.id == removed.id }))
    }

    func testNewReleasesOnlyIncludeRecentTitlesOnSelectedServices() throws {
        let referenceDate = Date(timeIntervalSince1970: 2_000_000_000)
        var snapshot = LibrarySnapshot.sample
        snapshot.selectedProviderIDs = [StreamingProvider.appleTV.id]

        let severanceIndex = try XCTUnwrap(
            snapshot.titles.firstIndex(where: { $0.id == "severance" })
        )
        snapshot.titles[severanceIndex].nextEpisodeAirDate = referenceDate.addingTimeInterval(-86_400)

        let slowHorsesIndex = try XCTUnwrap(
            snapshot.titles.firstIndex(where: { $0.id == "slow-horses" })
        )
        snapshot.titles[slowHorsesIndex].nextEpisodeAirDate = referenceDate.addingTimeInterval(-20 * 86_400)

        let pastLivesIndex = try XCTUnwrap(
            snapshot.titles.firstIndex(where: { $0.id == "past-lives" })
        )
        snapshot.titles[pastLivesIndex].releaseDate = referenceDate.addingTimeInterval(-86_400)

        let model = AppModel(store: MemoryLibraryStore(), seed: snapshot)

        XCTAssertEqual(
            model.newReleasesOnSelectedProviders(referenceDate: referenceDate).map(\.id),
            ["severance"]
        )
    }
}
