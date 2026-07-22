import Foundation

struct DiscoveryAssistantIntent: Equatable, Sendable {
    let kind: MediaKind?
    let mood: Mood?
    let maximumRuntimeMinutes: Int?
    let minimumRating: Double?
    let genres: Set<String>
    let isForBothMembers: Bool
    let prefersRecentTitles: Bool
}

struct DiscoveryAssistantMatch: Hashable, Identifiable, Sendable {
    let title: MediaTitle
    let reason: String
    let score: Double

    var id: MediaTitle.ID { title.id }
}

struct DiscoveryAssistantResponse: Hashable, Sendable {
    let prompt: String
    let summary: String
    let matches: [DiscoveryAssistantMatch]
}

enum DiscoveryAssistantEngine {
    static func respond(
        to prompt: String,
        titles: [MediaTitle],
        selectedProviderIDs: Set<StreamingProvider.ID>,
        tasteProfiles: [MemberTasteProfile],
        limit: Int = 6
    ) -> DiscoveryAssistantResponse {
        let intent = parse(prompt)
        let eligibleTitles = titles.filter {
            isEligible($0, intent: intent, selectedProviderIDs: selectedProviderIDs)
        }
        let moodAdjustedTitles = titlesMatchingMoodWhenPossible(eligibleTitles, mood: intent.mood)
        let matches = moodAdjustedTitles
            .map { title in
                DiscoveryAssistantMatch(
                    title: title,
                    reason: reason(for: title, intent: intent),
                    score: score(title, intent: intent, tasteProfiles: tasteProfiles)
                )
            }
            .sorted(by: isBetterMatch)
            .prefix(max(limit, 0))
            .map { $0 }

        return DiscoveryAssistantResponse(
            prompt: prompt,
            summary: summary(for: matches, selectedProviderIDs: selectedProviderIDs),
            matches: matches
        )
    }

    static func parse(_ prompt: String) -> DiscoveryAssistantIntent {
        let normalized = prompt.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        )
        let kind: MediaKind? = if containsAny(normalized, ["movie", "film"]) {
            .movie
        } else if containsAny(normalized, ["show", "series", "tv"]) {
            .series
        } else {
            nil
        }

        let mood: Mood? = if containsAny(normalized, ["funny", "comedy", "laugh", "lighthearted"]) {
            .funny
        } else if containsAny(normalized, ["cozy", "comfort", "relax", "easy watch"]) {
            .cozy
        } else if containsAny(normalized, ["intense", "tense", "thrilling", "scary", "dark"]) {
            .intense
        } else if containsAny(normalized, ["thoughtful", "smart", "cerebral", "emotional", "drama"]) {
            .thoughtful
        } else {
            nil
        }

        return DiscoveryAssistantIntent(
            kind: kind,
            mood: mood,
            maximumRuntimeMinutes: maximumRuntime(in: normalized),
            minimumRating: minimumRating(in: normalized),
            genres: genres(in: normalized),
            isForBothMembers: containsAny(
                normalized,
                ["together", "both", "for us", "girlfriend", "date night", "couple"]
            ),
            prefersRecentTitles: containsAny(normalized, ["new", "newest", "latest", "recent"])
        )
    }

    private static func isEligible(
        _ title: MediaTitle,
        intent: DiscoveryAssistantIntent,
        selectedProviderIDs: Set<StreamingProvider.ID>
    ) -> Bool {
        guard title.isRecommendationEligible,
              !selectedProviderIDs.isEmpty,
              !selectedProviderIDs.isDisjoint(with: Set(title.providers.map(\.id))) else {
            return false
        }
        if let kind = intent.kind, title.kind != kind { return false }
        if let maximum = intent.maximumRuntimeMinutes, title.runtimeMinutes > maximum { return false }
        if let minimum = intent.minimumRating, title.rating < minimum { return false }
        if !intent.genres.isEmpty {
            let titleGenres = Set(title.genres.map(normalizedGenre))
            guard !titleGenres.isDisjoint(with: intent.genres.map(normalizedGenre)) else { return false }
        }
        return true
    }

    private static func titlesMatchingMoodWhenPossible(_ titles: [MediaTitle], mood: Mood?) -> [MediaTitle] {
        guard let mood else { return titles }
        let exactMatches = titles.filter { $0.mood == mood }
        return exactMatches.isEmpty ? titles : exactMatches
    }

    private static func score(
        _ title: MediaTitle,
        intent: DiscoveryAssistantIntent,
        tasteProfiles: [MemberTasteProfile]
    ) -> Double {
        let currentYear = Calendar.current.component(.year, from: .now)
        let recency = max(0, 3 - Double(max(currentYear - title.year, 0)) * 0.25)
        let mood = intent.mood == title.mood ? 5.0 : 0
        let titleGenres = Set(title.genres.map(normalizedGenre))
        let genre = Double(titleGenres.intersection(intent.genres.map(normalizedGenre)).count) * 5
        let kind = intent.kind == title.kind ? 2.0 : 0
        let watchlist = title.isOnPersonalWatchlist ? 1.0 : 0
        let recent = intent.prefersRecentTitles ? recency : recency * 0.35
        let shared = intent.isForBothMembers
            ? tasteProfiles.reduce(0.0) { $0 + sharedProfileScore($1, title: title) }
            : 0
        return title.rating * 1.5 + mood + genre + kind + watchlist + recent + shared
    }

    private static func sharedProfileScore(_ profile: MemberTasteProfile, title: MediaTitle) -> Double {
        let preferredGenres = Set(profile.preferredGenres.map(normalizedGenre))
        let genreMatches = Set(title.genres.map(normalizedGenre)).intersection(preferredGenres).count
        let moodMatch = profile.preferredMoods.contains(title.mood) ? 1.5 : 0
        let runtimeMatch = profile.maximumRuntimeMinutes.map { title.runtimeMinutes <= $0 ? 1.0 : -1.0 } ?? 0
        return Double(genreMatches) * 2 + moodMatch + runtimeMatch
    }

    private static func reason(for title: MediaTitle, intent: DiscoveryAssistantIntent) -> String {
        let titleGenres = Set(title.genres.map(normalizedGenre))
        let matchingGenre = title.genres.first { intent.genres.map(normalizedGenre).contains(normalizedGenre($0)) }
        let lead: String
        if let matchingGenre {
            lead = "A strong \(matchingGenre.lowercased()) match"
        } else if intent.mood == title.mood, let mood = intent.mood {
            lead = "Fits the \(mood.label.lowercased()) mood"
        } else if intent.isForBothMembers, !titleGenres.isEmpty {
            lead = "A strong shared pick"
        } else {
            lead = "One of the strongest unwatched picks"
        }
        let provider = title.providers.first?.name ?? "your services"
        let rating = title.rating.formatted(.number.precision(.fractionLength(1)))
        return "\(lead). Rated \(rating) · \(title.runtimeMinutes) min · \(provider)."
    }

    private static func summary(
        for matches: [DiscoveryAssistantMatch],
        selectedProviderIDs: Set<StreamingProvider.ID>
    ) -> String {
        guard !matches.isEmpty else {
            return "No exact match is available on your selected services. Try relaxing the runtime or rating."
        }
        let providerNames = StreamingProvider.supportedSubscriptions
            .filter { selectedProviderIDs.contains($0.id) }
            .map(\.name)
        let services = ListFormatter.localizedString(byJoining: providerNames)
        return "\(matches.count) picks available on \(services)."
    }

    private static func genres(in prompt: String) -> Set<String> {
        var matches: Set<String> = []
        let mappings: [(String, [String])] = [
            ("Sci-Fi", ["sci-fi", "science fiction", "space", "future"]),
            ("Comedy", ["comedy", "sitcom"]),
            ("Mystery", ["mystery", "detective", "whodunit"]),
            ("Thriller", ["thriller", "suspense", "tense"]),
            ("Romance", ["romance", "romantic", "date night"]),
            ("Drama", ["drama", "emotional"]),
            ("Action", ["action", "adventure"]),
            ("Animation", ["animation", "animated", "anime"])
        ]
        for (genre, keywords) in mappings where containsAny(prompt, keywords) {
            matches.insert(genre)
        }
        return matches
    }

    private static func maximumRuntime(in prompt: String) -> Int? {
        if let minutes = firstNumber(
            matching: #"(\d{1,3})\s*(?:min|mins|minute|minutes)\b"#,
            in: prompt
        ) {
            return Int(minutes)
        }
        if let hours = firstNumber(
            matching: #"(\d(?:\.\d+)?)\s*(?:hour|hours|hr|hrs)\b"#,
            in: prompt
        ) {
            return Int(hours * 60)
        }
        if containsAny(prompt, ["short", "quick", "not too long"]) { return 45 }
        return nil
    }

    private static func minimumRating(in prompt: String) -> Double? {
        let asksForRating = containsAny(
            prompt,
            ["rating", "rated", "score", "highly rated", "good reviews", "best reviewed"]
        )
        guard asksForRating else { return nil }
        let parsed = firstNumber(
            matching: #"(?:rating|rated|score|above|over|at least)\D{0,8}(\d(?:\.\d)?)"#,
            in: prompt
        )
        return min(max(parsed ?? 7.5, 0), 10)
    }

    private static func firstNumber(matching pattern: String, in value: String) -> Double? {
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
              ),
              let range = Range(match.range(at: 1), in: value) else {
            return nil
        }
        return Double(value[range])
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains { value.localizedStandardContains($0) }
    }

    private static func normalizedGenre(_ genre: String) -> String {
        genre.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func isBetterMatch(_ lhs: DiscoveryAssistantMatch, _ rhs: DiscoveryAssistantMatch) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.title.rating != rhs.title.rating { return lhs.title.rating > rhs.title.rating }
        if lhs.title.year != rhs.title.year { return lhs.title.year > rhs.title.year }
        return lhs.title.title.localizedStandardCompare(rhs.title.title) == .orderedAscending
    }
}
