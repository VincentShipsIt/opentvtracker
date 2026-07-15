import Foundation

protocol CinemaProviding: Sendable {
    var venues: [CinemaVenue] { get }
    func showings(on date: Date, region: String) async throws -> [CinemaShowing]
}

struct MaltaCinemaService: CinemaProviding {
    let venues = CinemaVenue.malta
    private let endpoint: URL?
    private let session: URLSession

    init(endpoint: URL? = AppServiceConfiguration.apiBaseURL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func showings(on date: Date, region: String = "MT") async throws -> [CinemaShowing] {
        guard let endpoint else { return [] }
        let url = try showingsURL(baseURL: endpoint, date: date, region: region)
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw CinemaServiceError.unavailable
        }
        return try JSONDecoder.openTV.decode(CinemaShowingsResponse.self, from: data).showings
    }

    private func showingsURL(baseURL: URL, date: Date, region: String) throws -> URL {
        let path = baseURL.appending(path: "v1/cinemas/showings")
        guard var components = URLComponents(url: path, resolvingAgainstBaseURL: false) else {
            throw CinemaServiceError.invalidEndpoint
        }
        components.queryItems = [
            URLQueryItem(name: "country", value: region),
            URLQueryItem(name: "date", value: DateFormatter.openTVDay.string(from: date))
        ]
        guard let url = components.url else { throw CinemaServiceError.invalidEndpoint }
        return url
    }
}

private struct CinemaShowingsResponse: Decodable {
    let showings: [CinemaShowing]
}

enum CinemaServiceError: LocalizedError {
    case invalidEndpoint
    case unavailable

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint: "The cinema service endpoint is invalid."
        case .unavailable: "Live Malta showtimes are temporarily unavailable."
        }
    }
}

enum AppServiceConfiguration {
    static var apiBaseURL: URL? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "OpenTVAPIBaseURL") as? String,
              !value.isEmpty else { return nil }
        return URL(string: value)
    }

    static var recommendationURL: URL? {
        apiBaseURL?.appending(path: "v1/recommendations/rerank")
    }
}

extension JSONDecoder {
    static var openTV: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private extension DateFormatter {
    static var openTVDay: DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }
}
