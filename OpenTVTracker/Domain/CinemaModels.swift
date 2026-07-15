import Foundation

struct CinemaVenue: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let locality: String
    let symbol: String
    let listingsURL: URL
}

struct CinemaShowing: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let catalogID: Int?
    let title: String
    let venueID: CinemaVenue.ID
    let startsAt: Date
    let format: String?
    let language: String?
    let bookingURL: URL
}

struct CinemaDay: Hashable, Identifiable, Sendable {
    let date: Date

    var id: Date { date }
}

extension CinemaVenue {
    static let malta: [CinemaVenue] = [
        CinemaVenue(
            id: "eden",
            name: "Eden Cinemas",
            locality: "St Julian's",
            symbol: "popcorn.fill",
            listingsURL: URL(string: "https://www.edencinemas.com.mt/")!
        ),
        CinemaVenue(
            id: "embassy",
            name: "Embassy Cinemas",
            locality: "Valletta",
            symbol: "building.columns.fill",
            listingsURL: URL(string: "https://www.embassycinemas.com/now-showing/")!
        ),
        CinemaVenue(
            id: "citadel",
            name: "Citadel Cinema",
            locality: "Victoria, Gozo",
            symbol: "film.stack.fill",
            listingsURL: URL(string: "https://citadelcinema.com/")!
        )
    ]
}
