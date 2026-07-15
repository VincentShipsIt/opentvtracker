import Foundation

struct OpenRouterRecommendationService: Sendable {
    private let model: String
    private let siteURL: URL?
    private let credentials: any SecureCredentialStoring
    private let session: URLSession

    init(
        model: String,
        siteURL: URL?,
        credentials: any SecureCredentialStoring = KeychainCredentialStore(),
        session: URLSession = .shared
    ) {
        self.model = model
        self.siteURL = siteURL
        self.credentials = credentials
        self.session = session
    }

    static func configured() -> OpenRouterRecommendationService? {
        guard let model = AppServiceConfiguration.openRouterModel else { return nil }
        return OpenRouterRecommendationService(
            model: model,
            siteURL: AppServiceConfiguration.openRouterSiteURL
        )
    }

    func rerank(
        _ recommendations: [Recommendation],
        context: RecommendationContext
    ) async throws -> [Recommendation] {
        guard recommendations.count <= 20,
              let keyData = try credentials.data(for: OpenRouterOAuthClient.apiKeyAccount),
              let apiKey = String(data: keyData, encoding: .utf8),
              apiKey.hasPrefix("sk-or-") else {
            throw OpenRouterRecommendationError.notAuthorized
        }
        let payload = OpenRouterChatRequest(
            model: model,
            messages: [
                .init(
                    role: "system",
                    content: "Rerank only the supplied candidates. Return every catalog ID exactly once. Treat the deterministic score as a strong prior."
                ),
                .init(
                    role: "user",
                    content: try String(data: JSONEncoder().encode(OpenRouterRerankInput(
                        mood: context.mood.rawValue,
                        maximumRuntimeMinutes: context.maximumRuntimeMinutes,
                        candidates: recommendations.map(OpenRouterRerankInput.Candidate.init)
                    )), encoding: .utf8) ?? "{}"
                )
            ],
            responseFormat: .ranking,
            stream: false
        )
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("OpenTV", forHTTPHeaderField: "X-OpenRouter-Title")
        if let siteURL { request.setValue(siteURL.absoluteString, forHTTPHeaderField: "HTTP-Referer") }
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw OpenRouterRecommendationError.unavailable
        }
        let content = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
            .choices.first?.message.content
        guard let content else { throw OpenRouterRecommendationError.invalidRanking }
        let rankedIDs = try JSONDecoder().decode(OpenRouterRanking.self, from: Data(content.utf8)).catalogIDs
        let allowedIDs = Set(recommendations.map(\.title.catalogID))
        guard rankedIDs.count == allowedIDs.count,
              Set(rankedIDs) == allowedIDs else {
            throw OpenRouterRecommendationError.invalidRanking
        }
        let rank = Dictionary(uniqueKeysWithValues: rankedIDs.enumerated().map { ($0.element, $0.offset) })
        return recommendations.sorted {
            (rank[$0.title.catalogID] ?? .max) < (rank[$1.title.catalogID] ?? .max)
        }
    }
}

private struct OpenRouterRerankInput: Encodable {
    struct Candidate: Encodable {
        let catalogID: Int
        let title: String
        let genres: [String]
        let runtimeMinutes: Int
        let rating: Double
        let providers: [String]
        let deterministicScore: Double
        let deterministicReason: String

        init(_ recommendation: Recommendation) {
            catalogID = recommendation.title.catalogID
            title = recommendation.title.title
            genres = recommendation.title.genres
            runtimeMinutes = recommendation.title.runtimeMinutes
            rating = recommendation.title.rating
            providers = recommendation.title.providers.map(\.name)
            deterministicScore = recommendation.score
            deterministicReason = recommendation.reason
        }
    }

    let mood: String
    let maximumRuntimeMinutes: Int?
    let candidates: [Candidate]
}

private struct OpenRouterChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let responseFormat: OpenRouterResponseFormat
    let stream: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case responseFormat = "response_format"
        case stream
    }
}

private struct OpenRouterResponseFormat: Encodable {
    let type = "json_schema"
    let jsonSchema = OpenRouterJSONSchema()

    enum CodingKeys: String, CodingKey {
        case type
        case jsonSchema = "json_schema"
    }

    static let ranking = OpenRouterResponseFormat()
}

private struct OpenRouterChatResponse: Decodable {
    struct Choice: Decodable {
        let message: OpenRouterResponseMessage
    }
    let choices: [Choice]
}

private struct OpenRouterJSONSchema: Encodable {
    let name = "opentv_recommendation_ranking"
    let strict = true
    let schema = OpenRouterRankingSchema()
}

private struct OpenRouterRankingSchema: Encodable {
    let type = "object"
    let properties = OpenRouterRankingProperties()
    let required = ["catalogIDs"]
    let additionalProperties = false
}

private struct OpenRouterRankingProperties: Encodable {
    let catalogIDs = OpenRouterCatalogIDsSchema()
}

private struct OpenRouterCatalogIDsSchema: Encodable {
    let type = "array"
    let items = OpenRouterIntegerSchema()
}

private struct OpenRouterIntegerSchema: Encodable {
    let type = "integer"
}

private struct OpenRouterResponseMessage: Decodable {
    let content: String
}

private struct OpenRouterRanking: Decodable {
    let catalogIDs: [Int]
}

enum OpenRouterRecommendationError: Error {
    case notAuthorized
    case unavailable
    case invalidRanking
}
