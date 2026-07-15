import Foundation

struct LocalCatalogService: CatalogProviding {
    let titles: [MediaTitle]

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        titles.filter { title in
            (query.kind == nil || title.kind == query.kind)
                && (title.title.localizedStandardContains(query.text)
                    || title.genres.contains { $0.localizedStandardContains(query.text) })
        }
    }

    func title(kind: MediaKind, catalogID: Int) async throws -> MediaTitle {
        guard let title = titles.first(where: { $0.kind == kind && $0.catalogID == catalogID }) else {
            throw CatalogServiceError.notFound
        }
        return title
    }
}

struct ServerCatalogService: CatalogProviding {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        var components = URLComponents(
            url: baseURL.appending(path: "v1/catalog/search"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "q", value: query.text),
            URLQueryItem(name: "kind", value: query.kind?.rawValue),
            URLQueryItem(name: "page", value: String(max(query.page, 1))),
            URLQueryItem(name: "region", value: "MT")
        ].filter { $0.value != nil }
        guard let url = components?.url else { throw CatalogServiceError.invalidEndpoint }
        let response: CatalogSearchResponse = try await request(url)
        return response.results.map(\.mediaTitle)
    }

    func title(kind: MediaKind, catalogID: Int) async throws -> MediaTitle {
        let url = baseURL.appending(path: "v1/catalog/\(kind.rawValue)/\(catalogID)")
        let response: CatalogTitleDTO = try await request(url)
        return response.mediaTitle
    }

    private func request<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CatalogServiceError.unavailable }
        if response.statusCode == 404 { throw CatalogServiceError.notFound }
        guard 200..<300 ~= response.statusCode else { throw CatalogServiceError.unavailable }
        return try JSONDecoder.openTV.decode(Response.self, from: data)
    }
}

struct FallbackCatalogService: CatalogProviding {
    let primary: (any CatalogProviding)?
    let fallback: any CatalogProviding

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        if let primary, let results = try? await primary.search(query), !results.isEmpty { return results }
        return try await fallback.search(query)
    }

    func title(kind: MediaKind, catalogID: Int) async throws -> MediaTitle {
        if let primary, let title = try? await primary.title(kind: kind, catalogID: catalogID) { return title }
        return try await fallback.title(kind: kind, catalogID: catalogID)
    }
}

private struct CatalogSearchResponse: Decodable {
    let results: [CatalogTitleDTO]
}

private struct CatalogTitleDTO: Decodable {
    let catalogID: Int
    let title: String
    let year: Int
    let kind: MediaKind
    let synopsis: String
    let genres: [String]
    let runtimeMinutes: Int
    let rating: Double
    let mood: Mood?
    let posterURL: URL?
    let backdropURL: URL?
    let trailerURL: URL?
    let providers: [StreamingProvider]
    let reviews: [CommunityReview]?
    let releaseDate: Date?
    let nextEpisodeAirDate: Date?

    var mediaTitle: MediaTitle {
        MediaTitle(
            id: "\(kind.rawValue)-\(catalogID)",
            catalogID: catalogID,
            title: title,
            year: year,
            kind: kind,
            synopsis: synopsis,
            genres: genres,
            runtimeMinutes: runtimeMinutes,
            state: .planned,
            progress: nil,
            rating: rating,
            nextReleaseDescription: nil,
            recommendationReason: nil,
            mood: mood ?? .any,
            palette: PosterPalette(primaryHex: "3D4E81", secondaryHex: "161A2C"),
            providers: providers,
            reviews: reviews ?? [],
            posterURL: posterURL,
            backdropURL: backdropURL,
            trailerURL: trailerURL,
            nextEpisodeAirDate: nextEpisodeAirDate,
            releaseDate: releaseDate
        )
    }
}

enum CatalogServiceError: LocalizedError {
    case invalidEndpoint
    case unavailable
    case notFound

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The catalog service endpoint is invalid."
        case .unavailable: "The catalog is temporarily unavailable."
        case .notFound: "That title is no longer available in the catalog."
        }
    }
}
