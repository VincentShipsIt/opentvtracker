import Foundation
@testable import OpenTVTracker

enum LibraryTransferRemoteMetadataFixtures {
    static func unsafeSnapshot(
        snapshot: LibrarySnapshot,
        title: MediaTitle,
        review: CommunityReview
    ) -> (snapshot: LibrarySnapshot, title: MediaTitle) {
        var snapshot = snapshot
        var title = title
        title.state = .paused
        title.progress = EpisodeProgress(season: 1, episode: 1, totalEpisodes: 9)
        title.userRating = 9.25
        title.notes = "Private import note"
        title.rewatchCount = 3
        title.lastWatchedAt = Date(timeIntervalSince1970: 1_700_000_000)
        title.isDismissed = true
        title.isDisliked = false
        title.personalWatchlist = true
        title.watchedEpisodeIDs = ["severance-s1e1"]
        title.seriesLifecycle = .continuing
        title.isUpNextPinned = true
        title.upNextSnoozedUntil = Date(timeIntervalSince1970: 1_800_000_000)
        title.upNextManualOrder = 4
        title.posterURL = URL(string: "https://secure.gravatar.com/avatar/poster-tracker")
        title.backdropURL = URL(string: "https://image.tmdb.org.attacker.invalid/backdrop.jpg")
        title.trailerURL = URL(string: "https://www.youtube.com.attacker.invalid/watch?v=unsafe")
        title.sourceURL = URL(string: "https://www.themoviedb.org@attacker.invalid/tv/95396")
        title.reviews = [unsafeReview(from: review)]
        title.seasons = [unsafeSeason()]

        snapshot.titles = [title]
        snapshot.sharedSpace.titleIDs = [title.id]
        snapshot.sharedSpace.titleMetadata = [title]
        snapshot.diaryEntries = [LibraryDiaryTransferTests.diaryEntry]
        snapshot.lists = [
            MediaList(
                id: "private-list",
                name: "Private list",
                titleIDs: [title.id],
                updatedAt: Date(timeIntervalSince1970: 1_700_000_100)
            )
        ]
        return (snapshot, title)
    }

    static func trustedSnapshot(
        snapshot: LibrarySnapshot,
        title: MediaTitle,
        review: CommunityReview
    ) -> LibrarySnapshot {
        var snapshot = snapshot
        var title = title
        title.posterURL = URL(
            string: "HTTPS://IMAGE.TMDB.ORG:443/t/p/w500/poster.jpg?language=en#fragment"
        )
        title.backdropURL = URL(
            string: "https://MEDIA.THEMOVIEDB.ORG:443/t/p/w780/backdrop.jpg#fragment"
        )
        title.trailerURL = URL(string: "https://YOUTU.BE:443/abcdefghijk#fragment")
        title.sourceURL = URL(
            string: "https://WWW.THEMOVIEDB.ORG:443/tv/95396?language=en#fragment"
        )
        title.reviews = [trustedReview(from: review)]
        title.seasons = [trustedSeason()]

        snapshot.titles = [title]
        snapshot.sharedSpace.titleIDs = [title.id]
        snapshot.sharedSpace.titleMetadata = [title]
        return snapshot
    }

    private static func unsafeReview(from review: CommunityReview) -> CommunityReview {
        var review = review
        review.avatarURL = URL(string: "https://secure.gravatar.com@attacker.invalid/avatar")
        review.sourceURL = URL(string: "https://trakt.tv/reviews/unsafe")
        return review
    }

    private static func trustedReview(from review: CommunityReview) -> CommunityReview {
        var review = review
        review.avatarURL = URL(
            string: "https://SECURE.GRAVATAR.COM:443/avatar/hash?s=64&d=https%3A%2F%2Ftracker.invalid%2Fpixel.png#fragment"
        )
        review.sourceURL = URL(
            string: "https://WWW.THEMOVIEDB.ORG:443/review/1#fragment"
        )
        return review
    }

    private static func unsafeSeason() -> SeasonSummary {
        var episode = EpisodeSummary(
            id: "severance-s1e1",
            number: 1,
            title: "Good News About Hell",
            airDate: Date(timeIntervalSince1970: 1_645_142_400),
            runtimeMinutes: 57
        )
        episode.stillURL = URL(string: "http://static.tvmaze.com/uploads/still.jpg")
        var season = SeasonSummary(
            id: "severance-s1",
            number: 1,
            title: "Season 1",
            episodes: [episode]
        )
        season.artworkURL = URL(fileURLWithPath: "/private/season.jpg")
        return season
    }

    private static func trustedSeason() -> SeasonSummary {
        var episode = EpisodeSummary(
            id: "severance-s1e1",
            number: 1,
            title: "Good News About Hell",
            airDate: nil,
            runtimeMinutes: 57
        )
        episode.stillURL = URL(
            string: "https://IMAGE.TMDB.ORG:443/t/p/w300/still.jpg#fragment"
        )
        var season = SeasonSummary(
            id: "severance-s1",
            number: 1,
            title: "Season 1",
            episodes: [episode]
        )
        season.artworkURL = URL(
            string: "https://STATIC.TVMAZE.COM:443/uploads/images/original_untouched/season.jpg#fragment"
        )
        return season
    }
}
