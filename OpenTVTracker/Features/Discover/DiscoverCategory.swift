import Foundation

enum DiscoverCategory: String, CaseIterable, Hashable, Identifiable {
    case newAndHot
    case topRated
    case scienceFiction
    case comedy
    case mysteryAndThrillers
    case dateNight
    case movies
    case series

    var id: String { rawValue }

    var title: String {
        switch self {
        case .newAndHot: "New & hot"
        case .topRated: "Top rated"
        case .scienceFiction: "Sci-Fi"
        case .comedy: "Comedy"
        case .mysteryAndThrillers: "Mystery"
        case .dateNight: "Date night"
        case .movies: "Movies"
        case .series: "TV shows"
        }
    }

    var subtitle: String {
        switch self {
        case .newAndHot: "The newest arrivals on your services"
        case .topRated: "The strongest scores on services you have"
        case .scienceFiction: "Big worlds and stranger futures"
        case .comedy: "Sharp, warm, and easy to start"
        case .mysteryAndThrillers: "Secrets, spies, and tense nights"
        case .dateNight: "One great story to share"
        case .movies: "A complete story tonight"
        case .series: "Your next world to live in"
        }
    }

    var symbol: String {
        switch self {
        case .newAndHot: "flame.fill"
        case .topRated: "star.fill"
        case .scienceFiction: "sparkles"
        case .comedy: "face.smiling.fill"
        case .mysteryAndThrillers: "eye.fill"
        case .dateNight: "heart.fill"
        case .movies: "film.fill"
        case .series: "tv.fill"
        }
    }

    var palette: PosterPalette {
        switch self {
        case .newAndHot: PosterPalette(primaryHex: "FF6B35", secondaryHex: "B42318")
        case .topRated: PosterPalette(primaryHex: "F4B400", secondaryHex: "754C00")
        case .scienceFiction: PosterPalette(primaryHex: "4F7CFF", secondaryHex: "19224D")
        case .comedy: PosterPalette(primaryHex: "FFB547", secondaryHex: "A64B2A")
        case .mysteryAndThrillers: PosterPalette(primaryHex: "6650A4", secondaryHex: "19152A")
        case .dateNight: PosterPalette(primaryHex: "E85D8E", secondaryHex: "5A1F45")
        case .movies: PosterPalette(primaryHex: "00A6A6", secondaryHex: "123C47")
        case .series: PosterPalette(primaryHex: "4C9A66", secondaryHex: "173726")
        }
    }

    func titles(from catalog: [MediaTitle]) -> [MediaTitle] {
        let matchingTitles = catalog.filter {
            !$0.state.isCurrentViewingComplete && $0.state != .dropped && matches($0)
        }
        if self == .topRated {
            return matchingTitles.sorted {
                if $0.rating != $1.rating { return $0.rating > $1.rating }
                if $0.year != $1.year { return $0.year > $1.year }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        }
        return matchingTitles.sorted {
                if $0.year != $1.year { return $0.year > $1.year }
                if $0.rating != $1.rating { return $0.rating > $1.rating }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
    }

    func latestTitle(in catalog: [MediaTitle]) -> MediaTitle? {
        titles(from: catalog).first
    }

    private func matches(_ title: MediaTitle) -> Bool {
        switch self {
        case .newAndHot:
            true
        case .topRated:
            title.rating >= 7.5
        case .scienceFiction:
            title.genres.contains("Sci-Fi")
        case .comedy:
            title.genres.contains("Comedy") || title.mood == .funny
        case .mysteryAndThrillers:
            title.genres.contains("Mystery") || title.genres.contains("Thriller")
        case .dateNight:
            title.genres.contains("Romance") || title.mood == .thoughtful
        case .movies:
            title.kind == .movie
        case .series:
            title.kind == .series
        }
    }
}

struct DiscoverCategorySection: Identifiable {
    let category: DiscoverCategory
    let titles: [MediaTitle]

    var id: DiscoverCategory.ID { category.id }
    var latestTitle: MediaTitle? { titles.first }

    static func available(in catalog: [MediaTitle]) -> [DiscoverCategorySection] {
        DiscoverCategory.allCases.compactMap { category in
            let titles = category.titles(from: catalog)
            guard !titles.isEmpty else { return nil }
            return DiscoverCategorySection(category: category, titles: titles)
        }
    }
}
