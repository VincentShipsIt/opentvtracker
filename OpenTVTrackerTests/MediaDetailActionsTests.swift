import XCTest
@testable import OpenTVTracker

final class MediaDetailActionsTests: XCTestCase {
    func testIncompleteStatesAdvanceProgress() {
        for state in [WatchState.planned, .watching, .paused, .dropped] {
            XCTAssertEqual(MediaDetailPrimaryAction(state: state), .advanceProgress)
        }
    }

    func testCurrentViewingCompleteStatesEditActivity() {
        for state in [WatchState.caughtUp, .completed] {
            XCTAssertEqual(MediaDetailPrimaryAction(state: state), .editActivity)
        }
    }

    func testQueueProgressActionMarksSeriesWithUnwatchedEpisodesFirst() throws {
        let title = try XCTUnwrap(LibrarySnapshot.sample.titles.first { $0.id == "severance" })

        let action = try XCTUnwrap(
            QueueProgressAction(title: title, hasUnwatchedReleasedEpisodes: true)
        )

        XCTAssertEqual(action, .markNextEpisode)
        XCTAssertEqual(action.label, "Mark next episode watched")
        XCTAssertNil(QueueProgressAction(title: title, hasUnwatchedReleasedEpisodes: false))
    }

    func testQueueProgressActionMarksUnwatchedMoviesAndOmitsCompleted() throws {
        let movie = try XCTUnwrap(LibrarySnapshot.sample.titles.first { $0.id == "past-lives" })
        let completed = try XCTUnwrap(LibrarySnapshot.sample.titles.first { $0.id == "arrival" })

        XCTAssertEqual(
            QueueProgressAction(title: movie, hasUnwatchedReleasedEpisodes: false),
            .markMovieWatched
        )
        XCTAssertEqual(
            QueueProgressAction(title: movie, hasUnwatchedReleasedEpisodes: false)?.label,
            "Mark watched"
        )
        XCTAssertNil(QueueProgressAction(title: completed, hasUnwatchedReleasedEpisodes: false))

        var caughtUpMovie = movie
        caughtUpMovie.state = .caughtUp
        XCTAssertNil(QueueProgressAction(title: caughtUpMovie, hasUnwatchedReleasedEpisodes: false))
    }
}
