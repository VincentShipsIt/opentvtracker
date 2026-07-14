import Foundation

extension LibrarySnapshot {
    static let sample = LibrarySnapshot(
        titles: [
            MediaTitle(
                id: "severance",
                catalogID: 95396,
                title: "Severance",
                year: 2022,
                kind: .series,
                synopsis: "Mark leads a team whose work and personal memories have been surgically divided. The boundary starts to crack when a former colleague appears outside work.",
                genres: ["Drama", "Mystery", "Sci-Fi"],
                runtimeMinutes: 52,
                state: .watching,
                progress: EpisodeProgress(season: 2, episode: 3, totalEpisodes: 10),
                rating: 8.7,
                nextReleaseDescription: "Next: S2 E4 · ready now",
                recommendationReason: "Both of you finish cerebral mysteries quickly.",
                mood: .thoughtful,
                palette: PosterPalette(primaryHex: "245C7A", secondaryHex: "101A2B"),
                providers: [.appleTV],
                reviews: [.sampleThoughtful]
            ),
            MediaTitle(
                id: "the-bear",
                catalogID: 136315,
                title: "The Bear",
                year: 2022,
                kind: .series,
                synopsis: "A young chef returns home to run his family's sandwich shop and discovers that rebuilding a kitchen is easier than rebuilding a family.",
                genres: ["Drama", "Comedy"],
                runtimeMinutes: 31,
                state: .watching,
                progress: EpisodeProgress(season: 3, episode: 5, totalEpisodes: 10),
                rating: 8.5,
                nextReleaseDescription: "Continue: S3 E6",
                recommendationReason: "A short episode that fits tonight and lands for both of you.",
                mood: .intense,
                palette: PosterPalette(primaryHex: "2F5F46", secondaryHex: "12261E"),
                providers: [.disneyPlus],
                reviews: [.sampleWarm]
            ),
            MediaTitle(
                id: "slow-horses",
                catalogID: 95480,
                title: "Slow Horses",
                year: 2022,
                kind: .series,
                synopsis: "A dysfunctional team of British intelligence agents navigates the espionage world's smoke, mirrors, and spectacular mistakes.",
                genres: ["Drama", "Thriller"],
                runtimeMinutes: 48,
                state: .planned,
                progress: EpisodeProgress(season: 1, episode: 0, totalEpisodes: 6),
                rating: 8.2,
                nextReleaseDescription: "6 episodes available",
                recommendationReason: "Dry humor for you, spy tension for your partner.",
                mood: .funny,
                palette: PosterPalette(primaryHex: "9B7748", secondaryHex: "30251C"),
                providers: [.appleTV],
                reviews: [.sampleSharp]
            ),
            MediaTitle(
                id: "past-lives",
                catalogID: 666277,
                title: "Past Lives",
                year: 2023,
                kind: .movie,
                synopsis: "Two childhood friends reunite in New York for one fateful week and confront destiny, love, and the choices that make a life.",
                genres: ["Drama", "Romance"],
                runtimeMinutes: 106,
                state: .planned,
                progress: nil,
                rating: 7.8,
                nextReleaseDescription: "1h 46m",
                recommendationReason: "A thoughtful one-evening watch with no series commitment.",
                mood: .thoughtful,
                palette: PosterPalette(primaryHex: "A36555", secondaryHex: "3B2831"),
                providers: [.mubi],
                reviews: [.sampleTender]
            ),
            MediaTitle(
                id: "hacks",
                catalogID: 124101,
                title: "Hacks",
                year: 2021,
                kind: .series,
                synopsis: "A legendary Las Vegas comedian and an ambitious young writer discover that their sharpest material is each other.",
                genres: ["Comedy", "Drama"],
                runtimeMinutes: 29,
                state: .planned,
                progress: EpisodeProgress(season: 1, episode: 0, totalEpisodes: 10),
                rating: 8.0,
                nextReleaseDescription: "Easy 29-minute start",
                recommendationReason: "High match when you both want something funny and light.",
                mood: .funny,
                palette: PosterPalette(primaryHex: "B45D99", secondaryHex: "352047"),
                providers: [.max],
                reviews: [.sampleSharp]
            ),
            MediaTitle(
                id: "arrival",
                catalogID: 329865,
                title: "Arrival",
                year: 2016,
                kind: .movie,
                synopsis: "A linguist works with the military to communicate with alien visitors, while language reshapes her understanding of time.",
                genres: ["Drama", "Sci-Fi"],
                runtimeMinutes: 116,
                state: .completed,
                progress: nil,
                rating: 7.9,
                nextReleaseDescription: nil,
                recommendationReason: nil,
                mood: .thoughtful,
                palette: PosterPalette(primaryHex: "70808A", secondaryHex: "1A242A"),
                providers: [.paramount],
                reviews: [.sampleThoughtful]
            )
        ],
        sharedSpace: SharedSpace(
            id: "vincent-and-partner",
            name: "Our couch",
            members: [
                SpaceMember(id: "vincent", name: "Vincent", initials: "VS", isCurrentUser: true),
                SpaceMember(id: "partner", name: "Partner", initials: "GF", isCurrentUser: false)
            ],
            titleIDs: ["severance", "the-bear", "slow-horses", "past-lives"],
            activity: [
                SharedActivity(id: "activity-1", memberID: "partner", description: "added Past Lives", relativeDate: "12m", symbol: "plus"),
                SharedActivity(id: "activity-2", memberID: "vincent", description: "watched The Bear S3 E5", relativeDate: "Yesterday", symbol: "checkmark"),
                SharedActivity(id: "activity-3", memberID: "partner", description: "reacted to Slow Horses", relativeDate: "Mon", symbol: "heart.fill")
            ],
            isCloudSharingEnabled: false
        )
    )
}

extension StreamingProvider {
    static let appleTV = StreamingProvider(id: "apple-tv", name: "Apple TV+", symbol: "apple.logo")
    static let disneyPlus = StreamingProvider(id: "disney-plus", name: "Disney+", symbol: "sparkles.tv")
    static let max = StreamingProvider(id: "max", name: "Max", symbol: "play.tv")
    static let mubi = StreamingProvider(id: "mubi", name: "MUBI", symbol: "m.circle")
    static let paramount = StreamingProvider(id: "paramount", name: "Paramount+", symbol: "mountain.2")
}

extension CommunityReview {
    static let sampleThoughtful = CommunityReview(id: "review-thoughtful", author: "Maya R.", excerpt: "Patient, precise, and far stranger than its premise first suggests.", rating: 9, source: "TMDB", containsSpoilers: false)
    static let sampleWarm = CommunityReview(id: "review-warm", author: "Jonas", excerpt: "Chaotic on the surface, deeply generous underneath.", rating: 8.5, source: "TMDB", containsSpoilers: false)
    static let sampleSharp = CommunityReview(id: "review-sharp", author: "Nadia", excerpt: "The dialogue moves like a knife fight and somehow stays funny.", rating: 8, source: "TMDB", containsSpoilers: false)
    static let sampleTender = CommunityReview(id: "review-tender", author: "Eli", excerpt: "A quiet film about the lives we choose and the ones that remain possible.", rating: 9, source: "TMDB", containsSpoilers: false)
}
