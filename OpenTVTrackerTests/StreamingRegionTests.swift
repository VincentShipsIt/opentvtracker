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

        XCTAssertEqual(queryValue("region", in: searchURL), "US")
        XCTAssertEqual(queryValue("region", in: detailURL), "US")
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

    private func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
