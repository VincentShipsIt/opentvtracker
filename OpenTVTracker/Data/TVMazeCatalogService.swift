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
                    .map { $0.mediaTitle() }
            }

            let url = try endpoint(path: "shows", queryItems: [
                URLQueryItem(name: "page", value: String(max(query.page - 2, 0)))
            ])
            let shows: [TVMazeShowDTO] = try await request(url)
            return shows.map { $0.mediaTitle() }
        }

        guard query.page <= 1 else { return [] }
        let url = try endpoint(path: "search/shows", queryItems: [
            URLQueryItem(name: "q", value: trimmedQuery)
        ])
        let results: [TVMazeSearchResultDTO] = try await request(url)
        return results.map { $0.show.mediaTitle() }
    }

    func title(kind: MediaKind, catalogID: Int, region _: StreamingRegion) async throws -> MediaTitle {
        guard kind == .series else { throw CatalogServiceError.notFound }
        let url = try endpoint(path: "shows/\(catalogID)", queryItems: [
            URLQueryItem(name: "embed", value: "episodes")
        ])

        // The show payload carries no landscape art and no per-season art — TVmaze keeps both
        // on separate endpoints. They run alongside the detail fetch rather than after it, so
        // the artwork costs no extra latency, and either one failing leaves the screen intact.
        async let detail: TVMazeShowDTO = request(url)
        async let artwork: [TVMazeImageDTO]? = optionalRequest(path: "shows/\(catalogID)/images")
        async let seasons: [TVMazeSeasonDTO]? = optionalRequest(path: "shows/\(catalogID)/seasons")

        let show = try await detail
        return show.mediaTitle(
            backdropURL: TVMazeImageDTO.backdropURL(from: await artwork ?? []),
            seasonArtwork: TVMazeSeasonDTO.artworkByNumber(await seasons ?? [])
        )
    }

    func reviews(kind _: MediaKind, catalogID _: Int, page: Int) async throws -> CommunityReviewPage {
        CommunityReviewPage(page: max(page, 1), totalPages: 1, results: [])
    }

    private func endpoint(path: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        ) else {
            throw CatalogServiceError.invalidEndpoint
        }
        // Nil rather than an empty array: assigning `[]` still appends a bare "?" to the path,
        // and the artwork endpoints take no parameters at all.
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw CatalogServiceError.invalidEndpoint }
        return url
    }

    /// Enrichment that must never take the detail screen down with it. A show with no
    /// background image answers 404 rather than an empty list, so every failure here degrades
    /// to "no extra artwork" instead of propagating.
    private func optionalRequest<Response: Decodable>(path: String) async -> Response? {
        guard let url = try? endpoint(path: path, queryItems: []) else { return nil }
        return try? await request(url)
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

/// One entry from `shows/:id/images`. TVmaze tags each image with a type, and only
/// `background` is genuinely landscape — posters and banners are the wrong shape for a hero.
private struct TVMazeImageDTO: Decodable {
    struct Resolutions: Decodable {
        struct Entry: Decodable {
            let url: URL?
        }

        let original: Entry?
        let medium: Entry?
    }

    let type: String?
    let main: Bool?
    let resolutions: Resolutions

    static func backdropURL(from images: [TVMazeImageDTO]) -> URL? {
        let backgrounds = images.filter { $0.type?.lowercased() == "background" }
        // A show can carry a dozen backgrounds; the one flagged `main` is the art the show's
        // own page leads with, so it is the closest thing to an editorial pick.
        let preferred = backgrounds.first { $0.main == true } ?? backgrounds.first
        return preferred?.resolutions.original?.url ?? preferred?.resolutions.medium?.url
    }
}

/// One entry from `shows/:id/seasons`. Seasons themselves are still synthesized by grouping
/// the embedded episodes — this endpoint is consulted only for the per-season artwork, which
/// the episode payload does not carry.
private struct TVMazeSeasonDTO: Decodable {
    struct Image: Decodable {
        let medium: URL?
        let original: URL?
    }

    let number: Int?
    let image: Image?

    static func artworkByNumber(_ seasons: [TVMazeSeasonDTO]) -> [Int: URL] {
        seasons.reduce(into: [:]) { result, season in
            guard let number = season.number,
                  let url = season.image?.original ?? season.image?.medium else { return }
            result[number] = url
        }
    }
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
    let status: String?
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
        case status
        case rating
        case weight
        case network
        case webChannel
        case image
        case summary
        case embedded = "_embedded"
    }

    /// Both artwork arguments default to empty so the search and schedule paths, which have
    /// only the show payload to work from, keep reading as a plain conversion.
    func mediaTitle(backdropURL: URL? = nil, seasonArtwork: [Int: URL] = [:]) -> MediaTitle {
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
            backdropURL: backdropURL,
            trailerURL: nil,
            nextEpisodeAirDate: nextEpisode?.0,
            nextEpisodeAirDateIsAllDay: nextEpisode.map { $0.1.airstamp == nil },
            releaseDate: releaseDate,
            personalWatchlist: false,
            seasons: Self.seasons(from: episodes, showID: id, artwork: seasonArtwork),
            metadataSource: .tvmaze,
            sourceURL: url,
            seriesLifecycle: Self.lifecycle(from: status)
        )
    }

    private func episodeDescription(_ episode: TVMazeEpisodeDTO) -> String {
        guard let season = episode.season, let number = episode.number else { return "New episode scheduled" }
        return "Next: S\(season) E\(number)"
    }

    private static func seasons(
        from episodes: [TVMazeEpisodeDTO],
        showID: Int,
        artwork: [Int: URL]
    ) -> [SeasonSummary]? {
        let numberedEpisodes = episodes.compactMap { episode -> (Int, EpisodeSummary)? in
            guard let season = episode.season, let number = episode.number else { return nil }
            return (
                season,
                EpisodeSummary(
                    id: "tvmaze-episode-\(episode.id)",
                    number: number,
                    title: episode.name,
                    airDate: episode.airDate,
                    runtimeMinutes: episode.runtime,
                    overview: Self.plainText(episode.summary),
                    stillURL: episode.image?.original ?? episode.image?.medium,
                    airDateIsAllDay: episode.airstamp == nil
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
                    episodes: values.map(\.1).sorted { $0.number < $1.number },
                    artworkURL: artwork[number]
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

    private static func lifecycle(from status: String?) -> SeriesLifecycle {
        switch status?.lowercased() {
        case "ended":
            .ended
        case "running", "to be determined", "in development":
            .continuing
        default:
            .unknown
        }
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
    struct Image: Decodable {
        let medium: URL?
        let original: URL?
    }

    let id: Int
    let name: String
    let season: Int?
    let number: Int?
    let airdate: String?
    let airstamp: Date?
    let runtime: Int?
    let image: Image?
    let summary: String?

    var airDate: Date? {
        airstamp ?? airdate.flatMap(Self.parseDay)
    }

    private static func parseDay(_ value: String) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
