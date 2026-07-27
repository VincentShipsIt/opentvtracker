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
}
