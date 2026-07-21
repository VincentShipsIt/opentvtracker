import Foundation

struct TraktDeviceCodeRequest: Encodable {
    let clientID: String

    enum CodingKeys: String, CodingKey {
        case clientID = "client_id"
    }
}

struct TraktDeviceCodeResponse: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURL: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURL = "verification_url"
        case expiresIn = "expires_in"
        case interval
    }
}

struct TraktDeviceTokenRequest: Encodable {
    let code: String
    let clientID: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case code
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

struct TraktRefreshRequest: Encodable {
    let refreshToken: String
    let clientID: String
    let clientSecret: String
    let grantType: String

    enum CodingKeys: String, CodingKey {
        case refreshToken = "refresh_token"
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case grantType = "grant_type"
    }
}

struct TraktRevokeRequest: Encodable {
    let token: String
    let clientID: String
    let clientSecret: String

    enum CodingKeys: String, CodingKey {
        case token
        case clientID = "client_id"
        case clientSecret = "client_secret"
    }
}

struct TraktOAuthToken: Codable, Sendable {
    let accessToken: String
    let tokenType: String
    let expiresIn: Int
    let refreshToken: String
    let scope: String
    let createdAt: Int

    var expiresAt: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt + expiresIn))
    }

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case createdAt = "created_at"
    }
}

struct TraktLastActivityResponse: Decodable {
    let all: Date
}

struct TraktIDsDTO: Decodable {
    let trakt: Int?
    let tmdb: Int?
}

struct TraktMediaDTO: Decodable {
    let ids: TraktIDsDTO
    let title: String?
    let year: Int?
    let overview: String?
    let runtime: Int?
    let rating: Double?
    let genres: [String]?

    func remoteTitle(kind: MediaKind) -> TraktRemoteTitle? {
        guard let tmdbID = ids.tmdb,
              let title,
              let year else {
            return nil
        }
        return TraktRemoteTitle(
            media: TraktMediaKey(kind: kind, tmdbID: tmdbID),
            title: title,
            year: year,
            overview: overview,
            runtimeMinutes: runtime,
            rating: rating,
            genres: genres ?? []
        )
    }
}

struct TraktEpisodeDTO: Decodable {
    let season: Int
    let number: Int
    let ids: TraktIDsDTO
}

struct TraktHistoryDTO: Decodable {
    let id: Int64
    let watchedAt: Date
    let type: String
    let movie: TraktMediaDTO?
    let episode: TraktEpisodeDTO?
    let show: TraktMediaDTO?

    var remoteTitle: TraktRemoteTitle? {
        switch type {
        case "movie": movie?.remoteTitle(kind: .movie)
        case "episode": show?.remoteTitle(kind: .series)
        default: nil
        }
    }

    var historyItem: TraktHistoryItem? {
        if type == "movie", let tmdbID = movie?.ids.tmdb {
            return TraktHistoryItem(
                id: id,
                media: TraktMediaKey(kind: .movie, tmdbID: tmdbID),
                season: nil,
                episode: nil,
                watchedAt: watchedAt
            )
        }
        if type == "episode",
           let tmdbID = show?.ids.tmdb,
           let episode {
            return TraktHistoryItem(
                id: id,
                media: TraktMediaKey(kind: .series, tmdbID: tmdbID),
                season: episode.season,
                episode: episode.number,
                watchedAt: watchedAt
            )
        }
        return nil
    }

    enum CodingKeys: String, CodingKey {
        case id
        case watchedAt = "watched_at"
        case type
        case movie
        case episode
        case show
    }
}

struct TraktRatingDTO: Decodable {
    let ratedAt: Date
    let rating: Int
    let type: String
    let movie: TraktMediaDTO?
    let show: TraktMediaDTO?

    var remoteTitle: TraktRemoteTitle? {
        switch type {
        case "movie": movie?.remoteTitle(kind: .movie)
        case "show": show?.remoteTitle(kind: .series)
        default: nil
        }
    }

    var ratingItem: TraktRatingItem? {
        let media: TraktMediaKey?
        switch type {
        case "movie":
            media = movie?.ids.tmdb.map { TraktMediaKey(kind: .movie, tmdbID: $0) }
        case "show":
            media = show?.ids.tmdb.map { TraktMediaKey(kind: .series, tmdbID: $0) }
        default:
            media = nil
        }
        return media.map { TraktRatingItem(media: $0, rating: rating, ratedAt: ratedAt) }
    }

    enum CodingKeys: String, CodingKey {
        case ratedAt = "rated_at"
        case rating
        case type
        case movie
        case show
    }
}

struct TraktListItemDTO: Decodable {
    let type: String
    let movie: TraktMediaDTO?
    let show: TraktMediaDTO?

    var remoteTitle: TraktRemoteTitle? {
        switch type {
        case "movie": movie?.remoteTitle(kind: .movie)
        case "show": show?.remoteTitle(kind: .series)
        default: nil
        }
    }

    var mediaKey: TraktMediaKey? {
        switch type {
        case "movie":
            movie?.ids.tmdb.map { TraktMediaKey(kind: .movie, tmdbID: $0) }
        case "show":
            show?.ids.tmdb.map { TraktMediaKey(kind: .series, tmdbID: $0) }
        default:
            nil
        }
    }
}

struct TraktListDTO: Decodable {
    struct IDs: Decodable {
        let trakt: Int
    }

    let name: String
    let privacy: String
    let ids: IDs
}

struct TraktMutationIDs: Encodable {
    let tmdb: Int
}

struct TraktMovieMutationDTO: Encodable {
    let ids: TraktMutationIDs
    var watchedAt: Date?
    var rating: Int?

    enum CodingKeys: String, CodingKey {
        case ids
        case watchedAt = "watched_at"
        case rating
    }
}

struct TraktShowMutationDTO: Encodable {
    let ids: TraktMutationIDs
    var rating: Int?
    var seasons: [TraktSeasonMutationDTO]?
}

struct TraktSeasonMutationDTO: Encodable {
    let number: Int
    let episodes: [TraktEpisodeMutationDTO]
}

struct TraktEpisodeMutationDTO: Encodable {
    let number: Int
    let watchedAt: Date

    enum CodingKeys: String, CodingKey {
        case number
        case watchedAt = "watched_at"
    }
}

struct TraktMutationPayload: Encodable {
    var movies: [TraktMovieMutationDTO]?
    var shows: [TraktShowMutationDTO]?

    static func media(_ media: Set<TraktMediaKey>) -> TraktMutationPayload {
        TraktMutationPayload(
            movies: media.filter { $0.kind == .movie }
                .sorted { $0.tmdbID < $1.tmdbID }
                .map { TraktMovieMutationDTO(ids: TraktMutationIDs(tmdb: $0.tmdbID)) },
            shows: media.filter { $0.kind == .series }
                .sorted { $0.tmdbID < $1.tmdbID }
                .map { TraktShowMutationDTO(ids: TraktMutationIDs(tmdb: $0.tmdbID)) }
        )
    }

    static func ratings(_ ratings: [TraktRatingBaseline]) -> TraktMutationPayload {
        TraktMutationPayload(
            movies: ratings.filter { $0.media.kind == .movie }.map {
                TraktMovieMutationDTO(
                    ids: TraktMutationIDs(tmdb: $0.media.tmdbID),
                    rating: $0.rating
                )
            },
            shows: ratings.filter { $0.media.kind == .series }.map {
                TraktShowMutationDTO(
                    ids: TraktMutationIDs(tmdb: $0.media.tmdbID),
                    rating: $0.rating
                )
            }
        )
    }

    static func history(_ history: [TraktHistoryMutation]) -> TraktMutationPayload {
        let movies = history.filter { $0.media.kind == .movie }.map {
            TraktMovieMutationDTO(
                ids: TraktMutationIDs(tmdb: $0.media.tmdbID),
                watchedAt: $0.watchedAt
            )
        }
        let groupedShows = Dictionary(grouping: history.filter { $0.media.kind == .series }, by: \.media)
        let shows = groupedShows.keys.sorted { $0.tmdbID < $1.tmdbID }.map { media in
            let seasons = Dictionary(grouping: groupedShows[media] ?? [], by: \.season)
                .compactMap { seasonNumber, mutations -> TraktSeasonMutationDTO? in
                    guard let seasonNumber else { return nil }
                    let episodes = mutations.compactMap { mutation -> TraktEpisodeMutationDTO? in
                        guard let episode = mutation.episode else { return nil }
                        return TraktEpisodeMutationDTO(
                            number: episode,
                            watchedAt: mutation.watchedAt
                        )
                    }
                    return TraktSeasonMutationDTO(number: seasonNumber, episodes: episodes)
                }
                .sorted { $0.number < $1.number }
            return TraktShowMutationDTO(
                ids: TraktMutationIDs(tmdb: media.tmdbID),
                seasons: seasons
            )
        }
        return TraktMutationPayload(movies: movies, shows: shows)
    }
}
