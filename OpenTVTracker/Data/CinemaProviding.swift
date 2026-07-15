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
        if let endpoint {
            do {
                return try await serverShowings(baseURL: endpoint, date: date, region: region)
            } catch {
                return try await officialMaltaShowings(on: date)
            }
        }
        return try await officialMaltaShowings(on: date)
    }

    private func serverShowings(baseURL: URL, date: Date, region: String) async throws -> [CinemaShowing] {
        let url = try showingsURL(baseURL: baseURL, date: date, region: region)
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw CinemaServiceError.unavailable
        }
        return try JSONDecoder.openTV.decode(CinemaShowingsResponse.self, from: data).showings
    }

    private func officialMaltaShowings(on date: Date) async throws -> [CinemaShowing] {
        let url = URL(string: "https://www.embassycinemas.com/film-showtimes-tickets/")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("text/html", forHTTPHeaderField: "Accept")
        request.setValue("OpenTVTracker/0.1", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode,
              let html = String(data: data, encoding: .utf8) else {
            throw CinemaServiceError.unavailable
        }
        return EmbassyShowtimeParser.showings(in: html, on: date)
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

enum EmbassyShowtimeParser {
    static func showings(in html: String, on date: Date) -> [CinemaShowing] {
        articleFragments(in: html).flatMap { article -> [CinemaShowing] in
            guard let title = firstCapture(
                pattern: #"<h3[^>]*elementor-size-default[^>]*>\s*<a[^>]*>(.*?)</a>\s*</h3>"#,
                text: article
            ).map(plainText), !title.isEmpty else {
                return []
            }

            let format = firstCapture(
                pattern: #"<li[^>]*>\s*(Cinema[^<]+)\s*</li>"#,
                text: article
            ).map(plainText)

            return scheduleRows(in: article).flatMap { row -> [CinemaShowing] in
                guard let timestamp = TimeInterval(row.timestamp),
                      isSameDay(timestamp: timestamp, date: date) else {
                    return []
                }
                return timeslots(in: row.html).compactMap { slot in
                    guard let startsAt = startDate(dayTimestamp: timestamp, time: slot.time),
                          let bookingURL = URL(string: decodeEntities(slot.url)) else {
                        return nil
                    }
                    return CinemaShowing(
                        id: "embassy-\(normalizedID(title))-\(Int(startsAt.timeIntervalSince1970))",
                        catalogID: nil,
                        title: title,
                        venueID: "embassy",
                        startsAt: startsAt,
                        format: format,
                        language: nil,
                        bookingURL: bookingURL
                    )
                }
            }
        }
        .sorted { $0.startsAt < $1.startsAt }
    }

    private static func articleFragments(in html: String) -> [String] {
        captures(
            pattern: #"<article\b[^>]*\btype-film\b[^>]*>(.*?)</article>"#,
            text: html
        )
    }

    private static func scheduleRows(in article: String) -> [(timestamp: String, html: String)] {
        let pattern = #"<div class=\"schedule-row\"[^>]*data-schedule-ts=\"([0-9]+)\"[^>]*>(.*?)(?=<div class=\"schedule-row\"|$)"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(article.startIndex..<article.endIndex, in: article)
        return regex.matches(in: article, range: range).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let timestampRange = Range(match.range(at: 1), in: article),
                  let htmlRange = Range(match.range(at: 2), in: article) else {
                return nil
            }
            return (String(article[timestampRange]), String(article[htmlRange]))
        }
    }

    private static func timeslots(in row: String) -> [(url: String, time: String)] {
        let pattern = #"<a[^>]*href=\"([^\"]+)\"[^>]*schedule-row-timeslot[^>]*>\s*([0-9]{1,2}:[0-9]{2})\s*</a>"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(row.startIndex..<row.endIndex, in: row)
        return regex.matches(in: row, range: range).compactMap { match in
            guard match.numberOfRanges >= 3,
                  let urlRange = Range(match.range(at: 1), in: row),
                  let timeRange = Range(match.range(at: 2), in: row) else {
                return nil
            }
            return (String(row[urlRange]), String(row[timeRange]))
        }
    }

    private static func firstCapture(pattern: String, text: String) -> String? {
        captures(pattern: pattern, text: text).first
    }

    private static func captures(pattern: String, text: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges >= 2,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                return nil
            }
            return String(text[captureRange])
        }
    }

    private static func isSameDay(timestamp: TimeInterval, date: Date) -> Bool {
        dayString(Date(timeIntervalSince1970: timestamp), timeZone: TimeZone(secondsFromGMT: 0)!)
            == dayString(date, timeZone: TimeZone(identifier: "Europe/Malta")!)
    }

    private static func startDate(dayTimestamp: TimeInterval, time: String) -> Date? {
        let parts = time.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        let day = Date(timeIntervalSince1970: dayTimestamp)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Malta")!
        let dayComponents = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(secondsFromGMT: 0)!,
            from: day
        )
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: dayComponents.year,
            month: dayComponents.month,
            day: dayComponents.day,
            hour: parts[0],
            minute: parts[1]
        ))
    }

    private static func plainText(_ html: String) -> String {
        decodeEntities(
            html.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        )
        .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    private static func normalizedID(_ value: String) -> String {
        value.lowercased().replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "-",
            options: .regularExpression
        )
    }

    private static func dayString(_ date: Date, timeZone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
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
