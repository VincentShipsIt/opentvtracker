import XCTest
@testable import OpenTVTracker

@MainActor
final class CustomListModelTests: XCTestCase {
    func testCustomListsPersistMixedTitlesAndManualOrdering() async throws {
        let store = MemoryLibraryStore()
        let model = AppModel(store: store, seed: .sample)
        let listID = try XCTUnwrap(model.createList(named: "Comfort picks"))

        model.addTitle("severance", toList: listID)
        model.addTitle("past-lives", toList: listID)
        model.moveTitles(inList: listID, fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertTrue(model.renameList(listID, to: "Weekend comfort"))
        await model.flushPendingPersistence()

        let loaded = try await store.load()
        let saved = try XCTUnwrap(loaded)
        let list = try XCTUnwrap(saved.lists?.first(where: { $0.id == listID }))
        XCTAssertEqual(list.name, "Weekend comfort")
        XCTAssertEqual(list.titleIDs, ["past-lives", "severance"])
        XCTAssertEqual(
            saved.titles.filter { list.titleIDs.contains($0.id) }.map(\.kind.rawValue).sorted(),
            ["movie", "series"]
        )
    }

    func testListNamesAreUniqueIgnoringCase() {
        let model = AppModel(store: MemoryLibraryStore(), seed: .sample)

        XCTAssertNotNil(model.createList(named: "Cinema"))
        XCTAssertNil(model.createList(named: "cinema"))
    }

    func testVisibleRowOffsetsIgnoreDanglingTitleIDs() {
        var seed = LibrarySnapshot.sample
        seed.lists = [
            MediaList(
                id: "comfort",
                name: "Comfort",
                titleIDs: ["missing-title", "severance", "past-lives"],
                updatedAt: .now
            )
        ]
        let model = AppModel(store: MemoryLibraryStore(), seed: seed)

        model.moveTitles(inList: "comfort", fromOffsets: IndexSet(integer: 1), toOffset: 0)
        XCTAssertEqual(model.lists.first?.titleIDs, ["missing-title", "past-lives", "severance"])

        model.removeTitles(at: IndexSet(integer: 0), fromList: "comfort")
        XCTAssertEqual(model.lists.first?.titleIDs, ["missing-title", "severance"])
    }
}
