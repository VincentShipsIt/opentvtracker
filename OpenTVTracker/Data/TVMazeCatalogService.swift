import Foundation

struct TVMazeCatalogService: CatalogProviding {
    private let baseURL: URL
    private let session: URLSession

    init(
        baseURL: URL = URL(string: "https://api.tvmaze.com/")!,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    func search(_ query: MediaSearchQuery) async throws -> [MediaTitle] {
        guard query.kind != .movie else { return [] }

        let trimmedQuery = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedQuery.isEmpty {
            if query.page <= 1 {
                let url = try endpoint(path: "schedule/web", queryItems: [
                    URLQueryItem(name: "date", value: Self.dayString(.now))
                ])
                let schedule: [TVMazeScheduleEntryDTO] = try await request(url)
                var seenIDs: Set<Int> = []
                return schedule
                    .map(\.embedded.show)
                    .filter { seenIDs.insert($0.id).inserted }
                    .map(\.mediaTitle)
            }

            let url = try endpoint(path: "shows", queryItems: [
                URLQueryItem(name: "page", value: String(max(query.page - 2, 0)))
            ])
            let shows: [TVMazeShowDTO] = try await request(url)
            return shows.map(\.mediaTitle)
        }

        guard query.page <= 1 else { return [] }
        let url = try endpoint(path: "search/shows", queryItems: [
            URLQueryItem(name: "q", value: trimmedQuery)
        ])
        let results: [TVMazeSearchResultDTO] = try await request(url)
        return results.map(\.show.mediaTitle)
    }

    func title(kind: MediaKind, catalogID: Int, region _: StreamingRegion) async throws -> MediaTitle {
        guard kind == .series else { throw CatalogServiceError.notFound }
        let url = try endpoint(path: "shows/\(catalogID)", queryItems: [
            URLQueryItem(name: "embed", value: "episodes")
        ])
        let show: TVMazeShowDTO = try await request(url)
        return show.mediaTitle
    }

    private func endpoint(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw CatalogServiceError.invalidEndpoint
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw CatalogServiceError.invalidEndpoint }
        return url
    }

    private func request<Response: Decodable>(_ url: URL) async throws -> Response {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenTVTracker/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CatalogServiceError.unavailable }
        if response.statusCode == 404 { throw CatalogServiceError.notFound }
        guard 200..<300 ~= response.statusCode else { throw CatalogServiceError.unavailable }
        return try JSONDecoder.openTV.decode(Response.self, from: data)
    }

    private static func dayString(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

private struct TVMazeSearchResultDTO: Decodable {
    let show: TVMazeShowDTO
}

private struct TVMazeScheduleEntryDTO: Decodable {
    struct Embedded: Decodable {
        let show: TVMazeShowDTO
    }

    let embedded: Embedded

    enum CodingKeys: String, CodingKey {
        case embedded = "_embedded"
    }
}

private struct TVMazeShowDTO: Decodable {
    struct Rating: Decodable {
        let average: Double?
    }

    struct Image: Decodable {
        let medium: URL?
        let original: URL?
    }

    struct Channel: Decodable {
        let name: String
    }

    struct Embedded: Decodable {
        let episodes: [TVMazeEpisodeDTO]?
    }

    let id: Int
    let url: URL?
    let name: String
    let genres: [String]
    let runtime: Int?
    let averageRuntime: Int?
    let premiered: String?
    let rating: Rating
    let weight: Int?
    let network: Channel?
    let webChannel: Channel?
    let image: Image?
    let summary: String?
    let embedded: Embedded?

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case name
        case genres
        case runtime
        case averageRuntime
        case premiered
        case rating
        case weight
        case network
        case webChannel
        case image
        case summary
        case embedded = "_embedded"
    }

    var mediaTitle: MediaTitle {
        let episodes = embedded?.episodes ?? []
        let releaseDate = premiered.flatMap(Self.parseDay)
        let nextEpisode = episodes
            .compactMap { episode -> (Date, TVMazeEpisodeDTO)? in
                guard let date = episode.airDate, date >= Calendar.current.startOfDay(for: .now) else { return nil }
                return (date, episode)
            }
            .min { $0.0 < $1.0 }

        return MediaTitle(
            id: "tvmaze-series-\(id)",
            catalogID: id,
            title: name,
            year: releaseDate.map { Calendar.current.component(.year, from: $0) } ?? 0,
            kind: .series,
            synopsis: Self.plainText(summary) ?? "No synopsis has been published yet.",
            genres: genres,
            runtimeMinutes: runtime ?? averageRuntime ?? 0,
            state: .planned,
            progress: nil,
            rating: rating.average ?? min(Double(weight ?? 0) / 10, 10),
            nextReleaseDescription: nextEpisode.map { episodeDescription($0.1) },
            recommendationReason: nil,
            mood: Self.mood(for: genres),
            palette: PosterPalette(primaryHex: "3155A4", secondaryHex: "111831"),
            providers: Self.providers(network: network?.name, webChannel: webChannel?.name),
            reviews: [],
            posterURL: image?.original ?? image?.medium,
            backdropURL: nil,
            trailerURL: nil,
            nextEpisodeAirDate: nextEpisode?.0,
            releaseDate: releaseDate,
            personalWatchlist: false,
            seasons: Self.seasons(from: episodes, showID: id),
            metadataSource: .tvmaze,
            sourceURL: url
        )
    }

    private func episodeDescription(_ episode: TVMazeEpisodeDTO) -> String {
        guard let season = episode.season, let number = episode.number else { return "New episode scheduled" }
        return "Next: S\(season) E\(number)"
    }

    private static func seasons(from episodes: [TVMazeEpisodeDTO], showID: Int) -> [SeasonSummary]? {
        let numberedEpisodes = episodes.compactMap { episode -> (Int, EpisodeSummary)? in
            guard let season = episode.season, let number = episode.number else { return nil }
            return (
                season,
                EpisodeSummary(
                    id: "tvmaze-episode-\(episode.id)",
                    number: number,
                    title: episode.name,
                    airDate: episode.airDate,
                    runtimeMinutes: episode.runtime
                )
            )
        }
        guard !numberedEpisodes.isEmpty else { return nil }

        return Dictionary(grouping: numberedEpisodes, by: \.0)
            .map { number, values in
                SeasonSummary(
                    id: "tvmaze-season-\(showID)-\(number)",
                    number: number,
                    title: number == 0 ? "Specials" : "Season \(number)",
                    episodes: values.map(\.1).sorted { $0.number < $1.number }
                )
            }
            .sorted { $0.number < $1.number }
    }

    private static func providers(network: String?, webChannel: String?) -> [StreamingProvider] {
        let value = [network, webChannel]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()

        var providers: [StreamingProvider] = []
        if value.contains("netflix") { providers.append(.netflix) }
        if value.contains("amazon") || value.contains("prime video") { providers.append(.primeVideo) }
        if value.contains("apple tv+") { providers.append(.appleTV) }
        if value.contains("disney+") { providers.append(.disneyPlus) }
        if value.contains("hbo max") || value == "max" { providers.append(.max) }
        if value.contains("mubi") { providers.append(.mubi) }
        if value.contains("paramount+") { providers.append(.paramount) }
        return providers
    }

    private static func mood(for genres: [String]) -> Mood {
        let normalized = Set(genres.map { $0.lowercased() })
        if !normalized.isDisjoint(with: ["comedy"]) { return .funny }
        if !normalized.isDisjoint(with: ["thriller", "horror", "action", "crime"]) { return .intense }
        if !normalized.isDisjoint(with: ["drama", "documentary", "history"]) { return .thoughtful }
        if !normalized.isDisjoint(with: ["family", "romance"]) { return .cozy }
        return .any
    }

    private static func plainText(_ html: String?) -> String? {
        guard let html else { return nil }
        let withoutTags = html.replacingOccurrences(
            of: "<[^>]+>",
            with: " ",
            options: .regularExpression
        )
        let decoded = withoutTags
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        let collapsed = decoded.replacingOccurrences(
            of: "\\s+",
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsed.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseDay(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}

private struct TVMazeEpisodeDTO: Decodable {
    let id: Int
    let name: String
    let season: Int?
    let number: Int?
    let airdate: String?
    let runtime: Int?

    var airDate: Date? {
        airdate.flatMap(Self.parseDay)
    }

    private static func parseDay(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
