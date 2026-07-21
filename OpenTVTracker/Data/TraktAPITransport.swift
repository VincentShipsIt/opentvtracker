import Foundation

extension TraktAPIClient {
    func get<Response: Decodable>(path: String, token: String) async throws -> Response {
        try await send(path: path, method: "GET", body: Optional<String>.none, token: token)
    }

    func getAll<Item: Decodable>(path: String, token: String) async throws -> [Item] {
        var page = 1
        var pageCount = 1
        var items: [Item] = []
        repeat {
            let separator = path.contains("?") ? "&" : "?"
            let request = try makeRequest(
                path: "\(path)\(separator)page=\(page)&limit=100",
                method: "GET",
                body: Optional<String>.none,
                token: token
            )
            let (data, response) = try await data(for: request)
            try validate(response)
            items.append(contentsOf: try Self.decoder.decode([Item].self, from: data))
            pageCount = max(
                Int(response.value(forHTTPHeaderField: "X-Pagination-Page-Count") ?? "") ?? 1,
                1
            )
            page += 1
        } while page <= pageCount
        return items
    }

    func send<Response: Decodable, Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        token: String?
    ) async throws -> Response {
        let request = try makeRequest(path: path, method: method, body: body, token: token)
        let (data, response) = try await data(for: request)
        try validate(response)
        return try Self.decoder.decode(Response.self, from: data)
    }

    func sendWithoutResponse<Body: Encodable>(
        path: String,
        method: String,
        body: Body,
        token: String?
    ) async throws {
        let request = try makeRequest(path: path, method: method, body: body, token: token)
        let (_, response) = try await data(for: request)
        try validate(response)
    }

    func makeRequest<Body: Encodable>(
        path: String,
        method: String,
        body: Body?,
        token: String?
    ) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: configuration.apiBaseURL) else {
            throw TraktSyncError.notConfigured
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.setValue(configuration.clientID, forHTTPHeaderField: "trakt-api-key")
        request.setValue("2", forHTTPHeaderField: "trakt-api-version")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("OpenTVTracker/1", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.httpBody = try Self.encoder.encode(body)
        }
        return request
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else {
                throw TraktSyncError.invalidResponse
            }
            return (data, response)
        } catch let error as TraktSyncError {
            throw error
        } catch {
            throw TraktSyncError.providerUnavailable
        }
    }

    func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200..<300:
            return
        case 401:
            throw TraktSyncError.notAuthorized
        case 429:
            throw TraktSyncError.rateLimited
        case 500...599:
            throw TraktSyncError.providerUnavailable
        default:
            throw TraktSyncError.invalidResponse
        }
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = try? Date(
                value,
                strategy: .iso8601.time(includingFractionalSeconds: true)
            ) {
                return date
            }
            if let date = try? Date(value, strategy: .iso8601) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO 8601 date."
            )
        }
        return decoder
    }()
}
