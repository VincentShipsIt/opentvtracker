import XCTest
@testable import OpenTVTracker

final class TVMazeCatalogServiceTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testBrowseIndexOnlyReturnsSelectedLanguageTitles() async throws {
        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/shows")
            XCTAssertEqual(
                URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
                    .queryItems?
                    .first(where: { $0.name == "page" })?
                    .value,
                "0"
            )
            return try Self.jsonResponse(
                for: request,
                body: [
                    Self.show(id: 1, name: "English title", language: "English"),
                    Self.show(id: 2, name: "Ира", language: "Russian"),
                    Self.show(id: 3, name: "Unknown language", language: nil)
                ]
            )
        }
        let service = TVMazeCatalogService(
            baseURL: URL(string: "https://api.tvmaze.test/")!,
            session: TestURLProtocol.session()
        )

        let titles = try await service.search(
            MediaSearchQuery(
                text: "",
                kind: nil,
                page: 2,
                region: .malta,
                contentLanguage: try XCTUnwrap(ContentLanguage(code: "ru"))
            )
        )

        XCTAssertEqual(titles.map(\.title), ["Ира"])
    }

    func testScheduleBrowseOnlyReturnsEnglishTitles() async throws {
        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/schedule/web")
            return try Self.jsonResponse(
                for: request,
                body: [
                    ["_embedded": ["show": Self.show(id: 1, name: "English title", language: "English")]],
                    ["_embedded": ["show": Self.show(id: 2, name: "Русское название", language: "Russian")]]
                ]
            )
        }
        let service = TVMazeCatalogService(
            baseURL: URL(string: "https://api.tvmaze.test/")!,
            session: TestURLProtocol.session()
        )

        let titles = try await service.search(
            MediaSearchQuery(
                text: "",
                kind: nil,
                page: 1,
                region: .malta,
                contentLanguage: .english
            )
        )

        XCTAssertEqual(titles.map(\.title), ["English title"])
    }

    func testExplicitSearchKeepsInternationalMatches() async throws {
        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/search/shows")
            return try Self.jsonResponse(
                for: request,
                body: [
                    ["show": Self.show(id: 2, name: "Ира", language: "Russian")]
                ]
            )
        }
        let service = TVMazeCatalogService(
            baseURL: URL(string: "https://api.tvmaze.test/")!,
            session: TestURLProtocol.session()
        )

        let titles = try await service.search(
            MediaSearchQuery(text: "Ира", kind: nil, page: 1, region: .malta)
        )

        XCTAssertEqual(titles.map(\.title), ["Ира"])
    }

    private static func show(
        id: Int,
        name: String,
        language: String?
    ) -> [String: Any] {
        [
            "id": id,
            "url": "https://tvmaze.test/shows/\(id)",
            "name": name,
            "language": language.map { $0 as Any } ?? NSNull(),
            "genres": ["Drama"],
            "runtime": 45,
            "averageRuntime": 45,
            "premiered": "2026-01-01",
            "status": "Running",
            "rating": ["average": 8.0],
            "weight": 90,
            "network": NSNull(),
            "webChannel": NSNull(),
            "image": NSNull(),
            "summary": "Summary",
            "_embedded": NSNull()
        ]
    }

    private static func jsonResponse(
        for request: URLRequest,
        body: Any
    ) throws -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            try JSONSerialization.data(withJSONObject: body)
        )
    }
}
