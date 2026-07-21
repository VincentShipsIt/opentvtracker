import Foundation
import XCTest
@testable import OpenTVTracker

final class TrailerPlaybackTests: XCTestCase {
    func testSupportedYouTubeURLsNormalizeToOnePrivateInlineEmbed() throws {
        let sources = [
            "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtu.be/dQw4w9WgXcQ?t=30",
            "https://m.youtube.com/shorts/dQw4w9WgXcQ",
            "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ"
        ]

        let normalized = try sources.map {
            try XCTUnwrap(TrailerURLNormalizer.urls(for: XCTUnwrap(URL(string: $0))))
        }

        XCTAssertTrue(normalized.allSatisfy {
            $0.embed.absoluteString
                == "https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?playsinline=1&rel=0"
        })
        XCTAssertTrue(normalized.allSatisfy {
            $0.external.absoluteString == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        })
    }

    func testNormalizerRejectsUnsupportedOrMalformedEmbedURLs() throws {
        let rejected = [
            "http://www.youtube.com/watch?v=dQw4w9WgXcQ",
            "https://youtube.example/watch?v=dQw4w9WgXcQ",
            "https://www.youtube.com/watch?v=too-short",
            "https://user:password@www.youtube.com/watch?v=dQw4w9WgXcQ"
        ]

        for source in rejected {
            XCTAssertNil(
                TrailerURLNormalizer.urls(for: try XCTUnwrap(URL(string: source))),
                source
            )
        }
    }

    func testUnsupportedHTTPSDestinationRemainsAnExplicitExternalFallback() throws {
        let source = try XCTUnwrap(URL(string: "https://trailers.example/title/official"))

        XCTAssertNil(TrailerURLNormalizer.urls(for: source))
        XCTAssertEqual(TrailerURLNormalizer.safeExternalURL(source), source)
        XCTAssertNil(
            TrailerURLNormalizer.safeExternalURL(
                try XCTUnwrap(URL(string: "http://trailers.example/title/official"))
            )
        )
        XCTAssertTrue(TrailerPlaybackState.failed.showsFallback)
        XCTAssertFalse(TrailerPlaybackState.loading.showsFallback)
        XCTAssertFalse(TrailerPlaybackState.ready.showsFallback)
    }
}
