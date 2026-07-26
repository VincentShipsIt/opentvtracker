import Foundation
import XCTest
@testable import OpenTVTracker

final class DiscoverCategoryTests: XCTestCase {
    func testScienceFictionIsSortedNewestFirst() {
        let titles = DiscoverCategory.scienceFiction.titles(from: LibrarySnapshot.sample.titles)

        XCTAssertEqual(titles.first?.id, "fallout")
        XCTAssertEqual(titles.map(\.year), titles.map(\.year).sorted(by: >))
    }

    func testCategoriesExcludeCompletedTitles() {
        let movies = DiscoverCategory.movies.titles(from: LibrarySnapshot.sample.titles)

        XCTAssertFalse(movies.contains(where: { $0.state == .completed }))
    }

    func testCategoriesKeepDismissedAndDislikedTitlesBrowsable() throws {
        var catalog = LibrarySnapshot.sample.titles
        let index = try XCTUnwrap(catalog.firstIndex(where: { $0.kind == .movie && $0.state != .completed }))
        catalog[index].isDismissed = true
        catalog[index].isDisliked = true

        let movies = DiscoverCategory.movies.titles(from: catalog)

        XCTAssertTrue(movies.contains(where: { $0.id == catalog[index].id }))
    }

    func testTopRatedIsSortedByRating() {
        let titles = DiscoverCategory.topRated.titles(from: LibrarySnapshot.sample.titles)

        XCTAssertFalse(titles.isEmpty)
        XCTAssertEqual(titles.map(\.rating), titles.map(\.rating).sorted(by: >))
        XCTAssertTrue(titles.allSatisfy { $0.rating >= 7.5 })
    }

    func testAvailableCategoriesUseDistinctLeadTitles() {
        let sections = DiscoverCategorySection.available(in: LibrarySnapshot.sample.titles)
        let leadTitleIDs = sections.compactMap(\.leadTitle?.id)

        XCTAssertFalse(sections.isEmpty)
        XCTAssertEqual(Set(leadTitleIDs).count, leadTitleIDs.count)
    }

    func testAvailableCategoriesExcludeFeaturedTitleFromLeads() throws {
        let originalSections = DiscoverCategorySection.available(in: LibrarySnapshot.sample.titles)
        let featuredTitleID = try XCTUnwrap(originalSections.compactMap(\.leadTitle?.id).first)

        let sections = DiscoverCategorySection.available(
            in: LibrarySnapshot.sample.titles,
            excludingLeadTitleIDs: [featuredTitleID]
        )

        XCTAssertFalse(sections.compactMap(\.leadTitle?.id).contains(featuredTitleID))
    }

    func testLeadDeduplicationPreservesCategoryOrdering() throws {
        let sections = DiscoverCategorySection.available(in: LibrarySnapshot.sample.titles)
        let scienceFiction = try XCTUnwrap(
            sections.first(where: { $0.category == .scienceFiction })
        )

        XCTAssertEqual(
            scienceFiction.titles,
            DiscoverCategory.scienceFiction.titles(from: LibrarySnapshot.sample.titles)
        )
    }
}

/// Guards the rule the space switch depends on, at the level it can actually be broken.
///
/// `HorizontalShelf` exists so a shelf cannot forget to register itself with the space
/// swipe — but nothing stops the next one being written as a bare `ScrollView(.horizontal)`
/// again, and that mistake is invisible to every other test here. The symptom is a sideways
/// flick across a shelf swapping the whole room out, and the UI tests never see it: they
/// drag low on the screen specifically to miss the shelves. So the invariant is checked
/// against the source text itself, which is where it lives.
///
/// A second class in this file rather than its own, because this target's Xcode group is not
/// filesystem-synchronised — and the shelf that prompted it is the Discover carousel above.
final class HorizontalShelfRegistrationTests: XCTestCase {
    func testEveryHorizontalScrollViewRegistersWithTheSpaceSwipe() throws {
        let sourceRoot = try Self.appSourceRoot()
        let files = try Self.swiftFiles(under: sourceRoot)
        XCTAssertFalse(files.isEmpty, "Found no app sources to scan under \(sourceRoot.path)")

        var offenders: [String] = []
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            let shelves = source.components(separatedBy: "ScrollView(.horizontal").count - 1
            guard shelves > 0 else { continue }
            // `HorizontalShelf` is what every other shelf routes through, so its own file is
            // the one place allowed to build a horizontal scroll view unregistered.
            guard file.lastPathComponent != "Theme.swift" else { continue }

            // Counted per file rather than matched per declaration. Deciding which modifier
            // belongs to which scroll view means parsing Swift; counting catches the mistake
            // that actually happens — a shelf added with no registration anywhere.
            let registrations = source.components(separatedBy: "claimsHorizontalDrag()").count - 1
            if registrations < shelves {
                offenders.append(
                    "\(file.lastPathComponent): \(shelves) horizontal scroll views, \(registrations) registered"
                )
            }
        }

        XCTAssertTrue(
            offenders.isEmpty,
            """
            Horizontal scroll views that do not register with the space swipe:
            \(offenders.joined(separator: "\n"))
            Build them with `HorizontalShelf` (DesignSystem/Theme.swift), or apply \
            `claimsHorizontalDrag()` directly where routing through it is impossible.
            """
        )
    }

    /// `#filePath` is baked in by the compiler, so it still points at the checkout while the
    /// bundle runs in a simulator. This throws rather than skipping on purpose: a test that
    /// quietly passed when it could not find the sources would report success forever.
    private static func appSourceRoot() throws -> URL {
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // OpenTVTrackerTests
            .deletingLastPathComponent() // repository root
            .appendingPathComponent("OpenTVTracker", isDirectory: true)

        guard FileManager.default.fileExists(atPath: sourceRoot.path) else {
            throw UnscannableSources(path: sourceRoot.path)
        }
        return sourceRoot
    }

    private static func swiftFiles(under root: URL) throws -> [URL] {
        guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            throw UnscannableSources(path: root.path)
        }
        return files
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "swift" }
    }

    private struct UnscannableSources: Error, CustomStringConvertible {
        let path: String

        var description: String {
            "Could not read the app sources at \(path). This test exists to scan them, so an unreadable tree is a failure rather than a pass."
        }
    }
}
