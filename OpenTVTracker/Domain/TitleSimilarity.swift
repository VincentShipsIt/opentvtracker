import Foundation

struct SimilarTitleMatch: Hashable, Identifiable, Sendable {
    let title: MediaTitle
    let reason: String
    let score: Double

    var id: MediaTitle.ID { title.id }
}

enum TitleSimilarity {
    static func matches(
        for source: MediaTitle,
        among candidates: [MediaTitle],
        limit: Int = 12
    ) -> [SimilarTitleMatch] {
        guard limit > 0 else { return [] }

        return candidates
            .lazy
            .filter {
                $0.id != source.id
                    && !$0.state.isCurrentViewingComplete
                    && $0.state != .dropped
            }
            .map { match(source: source, candidate: $0) }
            .filter { $0.score > 0 }
            .sorted(by: isBetterMatch)
            .prefix(limit)
            .map { $0 }
    }

    private static func match(source: MediaTitle, candidate: MediaTitle) -> SimilarTitleMatch {
        let sourceGenres = Set(source.genres.map(normalizedGenre))
        let sharedGenres = candidate.genres.filter { sourceGenres.contains(normalizedGenre($0)) }
        let genreScore = Double(sharedGenres.count) * 4
        let moodScore = source.mood == candidate.mood ? 3.0 : 0
        let kindScore = source.kind == candidate.kind ? 2.0 : 0
        let runtimeDifference = abs(source.runtimeMinutes - candidate.runtimeMinutes)
        let runtimeScore = max(0, 2 - Double(runtimeDifference) / 30)

        return SimilarTitleMatch(
            title: candidate,
            reason: reason(source: source, candidate: candidate, sharedGenres: sharedGenres),
            score: genreScore + moodScore + kindScore + runtimeScore
        )
    }

    private static func reason(
        source: MediaTitle,
        candidate: MediaTitle,
        sharedGenres: [String]
    ) -> String {
        if sharedGenres.count >= 2 {
            return "Shares \(sharedGenres.prefix(2).joined(separator: " + "))"
        }
        if let sharedGenre = sharedGenres.first {
            return "More \(sharedGenre) with a similar pace"
        }
        if source.mood == candidate.mood {
            return "Same \(source.mood.label.lowercased()) mood"
        }
        if source.kind == candidate.kind {
            return "Another \(candidate.kind.label.lowercased()) with a close runtime"
        }
        return "A close match for tonight"
    }

    private static func isBetterMatch(_ lhs: SimilarTitleMatch, _ rhs: SimilarTitleMatch) -> Bool {
        if lhs.score != rhs.score { return lhs.score > rhs.score }
        if lhs.title.rating != rhs.title.rating { return lhs.title.rating > rhs.title.rating }
        if lhs.title.year != rhs.title.year { return lhs.title.year > rhs.title.year }
        return lhs.title.title.localizedStandardCompare(rhs.title.title) == .orderedAscending
    }

    private static func normalizedGenre(_ genre: String) -> String {
        genre.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}
