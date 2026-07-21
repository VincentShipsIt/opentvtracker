import Foundation

enum ImportResolutionReason: String, Hashable, Sendable {
    case noCatalogMatch
    case ambiguousCatalogMatch
    case unsafeAnimeRelation
    case catalogUnavailable

    var label: String {
        switch self {
        case .noCatalogMatch: "No catalog match"
        case .ambiguousCatalogMatch: "Several possible matches"
        case .unsafeAnimeRelation: "Anime relation needs confirmation"
        case .catalogUnavailable: "Catalog unavailable"
        }
    }
}

struct ImportResolutionIssue: Hashable, Identifiable, Sendable {
    let id: String
    let sourceID: String?
    let title: String
    let year: Int?
    let kind: MediaKind
    let reason: ImportResolutionReason
    let detail: String

    var displayTitle: String {
        if !title.isEmpty { return title }
        if let sourceID { return "\(kind.label) source ID \(sourceID)" }
        return "Unnamed \(kind.label.lowercased())"
    }
}

struct CatalogResolvedTitle: Sendable {
    let title: MediaTitle
    let seasonNumberOverride: Int?
}

enum CatalogCandidateSelection {
    case resolved(CatalogResolvedTitle)
    case issue(ImportResolutionReason, String)
}

enum CatalogImportMatcher {
    static func searchQueries(for entity: TVTimeEntity) -> [String] {
        var values = [entity.title]
        if let yearSuffix = controlledYearSuffix(in: entity.title, declaredYear: entity.year) {
            values.append(yearSuffix.title)
        }
        if let animeRelation = animeRelation(in: entity.title) {
            values.append(animeRelation.title)
        }

        var seen = Set<String>()
        return values.compactMap { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let normalized = TVTimeCSV.normalizedTitle(trimmed)
            return seen.insert(normalized).inserted ? trimmed : nil
        }
    }

    static func select(
        entity: TVTimeEntity,
        candidates: [MediaTitle]
    ) -> CatalogCandidateSelection {
        let matchingKind = candidates.filter { $0.kind == entity.kind }
        let exact = matchingKind.filter { aliases(for: $0).contains(normalized(entity.title)) }
        if !exact.isEmpty {
            return uniqueCandidate(
                exact,
                expectedYear: entity.year,
                mismatchDetail: "The catalog found this title with a different release year. Choose the correct release."
            )
        }

        if let yearSuffix = controlledYearSuffix(in: entity.title, declaredYear: entity.year) {
            let baseMatches = matchingKind.filter {
                aliases(for: $0).contains(normalized(yearSuffix.title))
            }
            if !baseMatches.isEmpty {
                return uniqueCandidate(
                    baseMatches,
                    expectedYear: yearSuffix.year,
                    mismatchDetail: "The year suffix did not identify one catalog release. Choose the correct release."
                )
            }
        }

        if let animeSelection = selectAnime(entity: entity, candidates: matchingKind) {
            return animeSelection
        }

        return .issue(
            .noCatalogMatch,
            matchingKind.isEmpty
                ? "The active catalog returned no \(entity.kind.label.lowercased()) results."
                : "Catalog results did not match the exported display, original, or localized title and year."
        )
    }

    static func matches(_ title: MediaTitle, entity: TVTimeEntity) -> Bool {
        guard title.kind == entity.kind else { return false }
        let source = normalized(entity.title)
        return aliases(for: title).contains(source)
            && (entity.year == nil || title.year == entity.year)
    }

    static func safeAnimeSeasonNumber(in title: String) -> Int? {
        guard let relation = animeRelation(in: title), relation.isSafeSeason else { return nil }
        return relation.seasonNumber
    }

    private static func uniqueCandidate(
        _ candidates: [MediaTitle],
        expectedYear: Int?,
        mismatchDetail: String
    ) -> CatalogCandidateSelection {
        let matchingYear = expectedYear.map { year in
            candidates.filter { $0.year == year }
        } ?? candidates

        if matchingYear.count == 1, let candidate = matchingYear.first {
            return .resolved(CatalogResolvedTitle(title: candidate, seasonNumberOverride: nil))
        }
        if matchingYear.count > 1 || (expectedYear == nil && candidates.count > 1) {
            return .issue(
                .ambiguousCatalogMatch,
                "The catalog returned several matching releases. Choose the correct one."
            )
        }
        if expectedYear != nil, !candidates.isEmpty {
            return .issue(.ambiguousCatalogMatch, mismatchDetail)
        }
        return .issue(.noCatalogMatch, "The catalog did not return a unique matching title.")
    }

    private static func selectAnime(
        entity: TVTimeEntity,
        candidates: [MediaTitle]
    ) -> CatalogCandidateSelection? {
        guard let relation = animeRelation(in: entity.title) else { return nil }
        let animeMatches = candidates.filter { title in
            title.genres.contains { normalized($0) == "animation" }
                && aliases(for: title).contains(normalized(relation.title))
        }
        guard !animeMatches.isEmpty else { return nil }
        guard relation.isSafeSeason, let seasonNumber = relation.seasonNumber else {
            return .issue(
                .unsafeAnimeRelation,
                "OpenTV does not collapse parts, cours, specials, OVAs, or movies into a numbered season. Choose the intended catalog title."
            )
        }
        switch uniqueCandidate(
            animeMatches,
            expectedYear: entity.year,
            mismatchDetail: "The anime season label matched several releases. Choose the intended catalog title."
        ) {
        case .resolved(let resolved):
            return .resolved(
                CatalogResolvedTitle(
                    title: resolved.title,
                    seasonNumberOverride: seasonNumber
                )
            )
        case .issue(let reason, let detail):
            return .issue(reason, detail)
        }
    }

    private static func aliases(for title: MediaTitle) -> Set<String> {
        Set(([title.title] + (title.alternativeTitles ?? [])).map(normalized))
    }

    private static func normalized(_ value: String) -> String {
        let folded = value.folding(
            options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let separated = folded.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar) ? String(scalar) : " "
        }.joined()
        return separated.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func controlledYearSuffix(
        in title: String,
        declaredYear: Int?
    ) -> (title: String, year: Int)? {
        let pattern = #"(?i)^\s*(.+?)\s*(?:\((\d{4})\)|[-–—]\s*(\d{4}))\s*$"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
              let match = expression.firstMatch(
                  in: title,
                  range: NSRange(title.startIndex..., in: title)
              ),
              let titleRange = Range(match.range(at: 1), in: title) else {
            return nil
        }
        let year = [2, 3].compactMap { index -> Int? in
            guard match.range(at: index).location != NSNotFound,
                  let range = Range(match.range(at: index), in: title) else {
                return nil
            }
            return Int(title[range])
        }.first
        guard let year,
              (1888...(Calendar.current.component(.year, from: .now) + 5)).contains(year),
              declaredYear == nil || declaredYear == year else {
            return nil
        }
        let base = title[titleRange].trimmingCharacters(in: .whitespacesAndNewlines)
        return base.isEmpty ? nil : (base, year)
    }

    private static func animeRelation(in title: String) -> AnimeRelation? {
        let safePatterns = [
            #"(?i)^\s*(.+?)\s+season\s+(\d{1,2})\s*$"#,
            #"(?i)^\s*(.+?)\s+(\d{1,2})(?:st|nd|rd|th)\s+season\s*$"#
        ]
        for pattern in safePatterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(
                      in: title,
                      range: NSRange(title.startIndex..., in: title)
                  ),
                  let titleRange = Range(match.range(at: 1), in: title),
                  let seasonRange = Range(match.range(at: 2), in: title),
                  let season = Int(title[seasonRange]),
                  season > 0 else {
                continue
            }
            return AnimeRelation(
                title: String(title[titleRange]),
                seasonNumber: season,
                isSafeSeason: true
            )
        }

        let unsafePattern = #"(?i)^\s*(.+?)\s+(?:part|cour|specials?|ova|ona|movie)\s*(?:\d{1,2})?\s*$"#
        guard let expression = try? NSRegularExpression(pattern: unsafePattern),
              let match = expression.firstMatch(
                  in: title,
                  range: NSRange(title.startIndex..., in: title)
              ),
              let titleRange = Range(match.range(at: 1), in: title) else {
            return nil
        }
        return AnimeRelation(
            title: String(title[titleRange]),
            seasonNumber: nil,
            isSafeSeason: false
        )
    }
}

private struct AnimeRelation {
    let title: String
    let seasonNumber: Int?
    let isSafeSeason: Bool
}
