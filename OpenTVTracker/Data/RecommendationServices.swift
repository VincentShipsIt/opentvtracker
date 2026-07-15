import Foundation

struct DeterministicRecommendationService: RecommendationProviding {
    func recommendations(
        from snapshot: LibrarySnapshot,
        context: RecommendationContext
    ) async throws -> [Recommendation] {
        DeterministicRecommendationEngine.rank(snapshot: snapshot, context: context)
    }
}

enum DeterministicRecommendationEngine {
    static func rank(
        snapshot: LibrarySnapshot,
        context: RecommendationContext,
        limit: Int = 20
    ) -> [Recommendation] {
        let history = snapshot.titles.filter { $0.state == .completed || $0.state == .watching }
        let genreWeights = preferredGenreWeights(history: history)
        let profiles = snapshot.sharedSpace.tasteProfiles ?? []

        return snapshot.titles
            .filter { candidate in
                candidate.state == .planned
                    && candidate.isRecommendationEligible
                    && (context.mood == .any || candidate.mood == context.mood)
                    && isOnSelectedProvider(candidate, selectedIDs: snapshot.selectedProviderIDs)
                    && fitsRuntime(candidate, maximum: context.maximumRuntimeMinutes)
            }
            .map { candidate in
                recommendation(
                    candidate,
                    context: context,
                    genreWeights: genreWeights,
                    profiles: profiles
                )
            }
            .sorted(by: isBetterRecommendation)
            .prefix(limit)
            .map { $0 }
    }

    private static func recommendation(
        _ candidate: MediaTitle,
        context: RecommendationContext,
        genreWeights: [String: Double],
        profiles: [MemberTasteProfile]
    ) -> Recommendation {
        let historyScore = candidate.genres.reduce(0.0) { score, genre in
            score + (genreWeights[normalized(genre)] ?? 0)
        }
        let moodScore = context.mood == .any || candidate.mood == context.mood ? 3.0 : 0
        let qualityScore = max(0, candidate.rating - 6)
        let freshnessScore = min(max(Double(candidate.year - 2020) * 0.18, 0), 1.5)
        let coupleScore = profiles.reduce(0.0) { $0 + profileScore($1, candidate: candidate) }
        let score = historyScore + moodScore + qualityScore + freshnessScore + coupleScore

        return Recommendation(
            id: candidate.id,
            title: candidate,
            reason: reason(
                candidate,
                context: context,
                genreWeights: genreWeights,
                profiles: profiles
            ),
            score: score
        )
    }

    private static func preferredGenreWeights(history: [MediaTitle]) -> [String: Double] {
        history.reduce(into: [:]) { weights, title in
            let completionWeight = title.state == .completed ? 1.5 : 1.0
            let ratingWeight = title.userRating.map { max($0 - 5, 0) / 5 } ?? 0.5
            for genre in title.genres {
                weights[normalized(genre), default: 0] += completionWeight + ratingWeight
            }
        }
    }

    private static func profileScore(_ profile: MemberTasteProfile, candidate: MediaTitle) -> Double {
        let preferredGenres = Set(profile.preferredGenres.map(normalized))
        let genreMatches = candidate.genres.filter { preferredGenres.contains(normalized($0)) }.count
        let moodMatch = profile.preferredMoods.contains(candidate.mood) ? 1.5 : 0
        let runtimeFit = profile.maximumRuntimeMinutes.map { candidate.runtimeMinutes <= $0 ? 1.0 : -1.0 } ?? 0
        return Double(genreMatches) * 2 + moodMatch + runtimeFit
    }

    private static func reason(
        _ candidate: MediaTitle,
        context: RecommendationContext,
        genreWeights: [String: Double],
        profiles: [MemberTasteProfile]
    ) -> String {
        let sharedProfileGenres = Set(profiles.flatMap(\.preferredGenres).map(normalized))
        let coupleGenres = candidate.genres.filter { sharedProfileGenres.contains(normalized($0)) }
        if profiles.count > 1, let genre = coupleGenres.first {
            return "A \(genre.lowercased()) compromise that fits both taste profiles."
        }
        let historyGenres = candidate.genres
            .filter { genreWeights[normalized($0), default: 0] > 0 }
            .sorted { genreWeights[normalized($0), default: 0] > genreWeights[normalized($1), default: 0] }
        if let genre = historyGenres.first {
            return "Ranks highly because you keep watching \(genre.lowercased()) titles."
        }
        if context.mood != .any, candidate.mood == context.mood {
            return "Matches your \(context.mood.label.lowercased()) mood and selected services."
        }
        return "Available on your services, unwatched, and highly rated."
    }

    private static func isOnSelectedProvider(
        _ title: MediaTitle,
        selectedIDs: Set<StreamingProvider.ID>?
    ) -> Bool {
        guard let selectedIDs else { return true }
        guard !selectedIDs.isEmpty else { return false }
        return !selectedIDs.isDisjoint(with: Set(title.providers.map(\.id)))
    }

    private static func fitsRuntime(_ title: MediaTitle, maximum: Int?) -> Bool {
        maximum.map { title.runtimeMinutes <= $0 } ?? true
    }

    private static func isBetterRecommendation(_ lhs: Recommendation, _ rhs: Recommendation) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.title.rating != rhs.title.rating { return lhs.title.rating > rhs.title.rating }
        return lhs.title.id < rhs.title.id
    }

    private static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

struct ProviderNeutralRecommendationService: RecommendationProviding {
    private let fallback = DeterministicRecommendationService()
    private let endpoint: URL?
    private let session: URLSession

    init(endpoint: URL? = AppServiceConfiguration.recommendationURL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    func recommendations(
        from snapshot: LibrarySnapshot,
        context: RecommendationContext
    ) async throws -> [Recommendation] {
        let deterministic = try await fallback.recommendations(from: snapshot, context: context)
        guard context.allowsRemoteReranking, let endpoint, !deterministic.isEmpty else {
            return deterministic
        }

        do {
            return try await rerank(deterministic, context: context, endpoint: endpoint)
        } catch {
            return deterministic
        }
    }

    private func rerank(
        _ recommendations: [Recommendation],
        context: RecommendationContext,
        endpoint: URL
    ) async throws -> [Recommendation] {
        let payload = RecommendationRerankRequest(
            mood: context.mood.rawValue,
            maximumRuntimeMinutes: context.maximumRuntimeMinutes,
            candidates: recommendations.map {
                .init(
                    catalogID: $0.title.catalogID,
                    title: $0.title.title,
                    genres: $0.title.genres,
                    runtimeMinutes: $0.title.runtimeMinutes,
                    rating: $0.title.rating,
                    providers: $0.title.providers.map(\.name),
                    deterministicScore: $0.score,
                    deterministicReason: $0.reason
                )
            }
        )
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw RecommendationServiceError.unavailable
        }
        let rankedIDs = try JSONDecoder().decode(RecommendationRerankResponse.self, from: data).catalogIDs
        let rank = Dictionary(uniqueKeysWithValues: rankedIDs.enumerated().map { ($0.element, $0.offset) })
        return recommendations.sorted {
            (rank[$0.title.catalogID] ?? .max) < (rank[$1.title.catalogID] ?? .max)
        }
    }
}

private struct RecommendationRerankRequest: Encodable {
    struct Candidate: Encodable {
        let catalogID: Int
        let title: String
        let genres: [String]
        let runtimeMinutes: Int
        let rating: Double
        let providers: [String]
        let deterministicScore: Double
        let deterministicReason: String
    }

    let mood: String
    let maximumRuntimeMinutes: Int?
    let candidates: [Candidate]
}

private struct RecommendationRerankResponse: Decodable {
    let catalogIDs: [Int]
}

private enum RecommendationServiceError: Error {
    case unavailable
}
