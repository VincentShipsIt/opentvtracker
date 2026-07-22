import { describe, expect, test } from "bun:test";
import {
  mapAlternativeTitles,
  mapEpisodeSummary,
  mapReviewPage,
  mapReviews,
  mapSeriesLifecycle,
  mapStreamingProvider,
  StreamingProviderID,
  TMDBProviderID,
} from "../src/tmdb";

describe("mapAlternativeTitles", () => {
  test("deduplicates original and localized titles without returning the display title", () => {
    expect(
      mapAlternativeTitles(
        {
          name: "Attack on Titan",
          original_name: "進撃の巨人",
          alternative_titles: {
            results: [
              { title: "L'Attaque des Titans" },
              { title: "Attack on Titan" },
            ],
          },
          translations: {
            translations: [
              { data: { name: "Ataque a los Titanes" } },
              { data: { name: "L'Attaque des Titans" } },
            ],
          },
        },
        "series",
      ),
    ).toEqual(["進撃の巨人", "Ataque a los Titanes", "L'Attaque des Titans"]);
  });

  test("keeps translations when alternative titles exceed the response cap", () => {
    const alternativeTitles = Array.from({ length: 60 }, (_, index) => ({
      title: `Alternative ${index}`,
    }));

    const titles = mapAlternativeTitles(
      {
        name: "Display title",
        original_name: "Original title",
        alternative_titles: { results: alternativeTitles },
        translations: {
          translations: [{ data: { name: "Localized title" } }],
        },
      },
      "series",
    );

    expect(titles).toHaveLength(50);
    expect(titles).toContain("Localized title");
  });
});

describe("mapSeriesLifecycle", () => {
  test("distinguishes ended series from continuing catalog entries", () => {
    expect(mapSeriesLifecycle("Ended")).toBe("ended");
    expect(mapSeriesLifecycle("Canceled")).toBe("ended");
    expect(mapSeriesLifecycle("Returning Series")).toBe("continuing");
    expect(mapSeriesLifecycle("In Production")).toBe("continuing");
    expect(mapSeriesLifecycle(undefined)).toBe("unknown");
  });
});

describe("mapReviews", () => {
  test("keeps complete TMDB review content and source metadata", () => {
    const content = "A".repeat(900);
    expect(
      mapReviews({
        results: [
          {
            id: "review-id",
            author: "Reviewer",
            author_details: {
              username: "reviewer-name",
              avatar_path: "/avatar.jpg",
              rating: 8,
            },
            content,
            url: "https://www.themoviedb.org/review/review-id",
            created_at: "2026-07-14T10:30:15.123Z",
            updated_at: "2026-07-15T11:45:00.000Z",
          },
        ],
      })[0],
    ).toEqual({
      id: "tmdb-review-review-id",
      author: "Reviewer",
      excerpt: content,
      rating: 8,
      source: "TMDB",
      containsSpoilers: true,
      username: "reviewer-name",
      avatarURL: "https://image.tmdb.org/t/p/w185/avatar.jpg",
      sourceURL: "https://www.themoviedb.org/review/review-id",
      createdAt: "2026-07-14T10:30:15Z",
      updatedAt: "2026-07-15T11:45:00Z",
    });
  });

  test("maps bounded review pages with stable cross-page identities", () => {
    const page = mapReviewPage(
      {
        page: 2,
        total_pages: 120,
        results: [
          { id: "stable", content: "First" },
          { content: "No provider identifier" },
        ],
      },
      2,
    );

    expect(page.page).toBe(2);
    expect(page.totalPages).toBe(100);
    expect(page.results.map((review) => review.id)).toEqual([
      "tmdb-review-stable",
      "tmdb-review-2-1",
    ]);
  });

  test("keeps the requested review page when TMDB reports a mismatched page", () => {
    const page = mapReviewPage(
      { page: 1, total_pages: 4, results: [{ content: "Review" }] },
      3,
    );

    expect(page.page).toBe(3);
    expect(page.results[0]?.id).toBe("tmdb-review-3-0");
  });
});

describe("mapEpisodeSummary", () => {
  test("keeps TMDB episode artwork and overview for the mobile season screen", () => {
    expect(
      mapEpisodeSummary(
        {
          id: 123,
          episode_number: 4,
          name: "The You You Are",
          air_date: "2022-03-04",
          runtime: 46,
          overview: "The team meets a mysterious visitor.",
          still_path: "/episode-still.jpg",
          vote_average: 8.4,
          episode_type: "finale",
        },
        95396,
        1,
      ),
    ).toEqual({
      id: "tmdb-episode-123",
      number: 4,
      title: "The You You Are",
      airDate: "2022-03-04T00:00:00Z",
      runtimeMinutes: 46,
      overview: "The team meets a mysterious visitor.",
      stillURL: "https://image.tmdb.org/t/p/w500/episode-still.jpg",
      rating: 8.4,
      releaseType: "finale",
      airDateIsAllDay: true,
    });
  });

  test("does not infer a finale from malformed upstream metadata", () => {
    expect(
      mapEpisodeSummary(
        {
          id: 456,
          episode_number: 8,
          name: "Unknown type",
          air_date: "2026-07-24",
          episode_type: "season_finale",
        },
        95396,
        2,
      ).releaseType,
    ).toBeNull();
  });
});

describe("mapStreamingProvider", () => {
  test("maps TMDB's stable Apple TV ID to the Apple TV+ subscription", () => {
    expect(mapStreamingProvider(TMDBProviderID.appleTV)).toEqual([
      {
        id: StreamingProviderID.appleTV,
        name: "Apple TV+",
        symbol: "apple.logo",
        brandHex: "1C1C1E",
      },
    ]);
  });

  test("maps direct subscription variants to one app provider", () => {
    expect(mapStreamingProvider(TMDBProviderID.netflixWithAds)[0]?.id).toBe(
      StreamingProviderID.netflix,
    );
    expect(mapStreamingProvider(TMDBProviderID.primeVideoLegacy)[0]?.id).toBe(
      StreamingProviderID.primeVideo,
    );
    expect(mapStreamingProvider(TMDBProviderID.paramountEssential)[0]?.id).toBe(
      StreamingProviderID.paramount,
    );
  });

  test("does not treat channel add-ons as direct subscriptions", () => {
    expect(mapStreamingProvider(2243)).toEqual([]); // Apple TV Amazon Channel
    expect(mapStreamingProvider(582)).toEqual([]); // Paramount+ Amazon Channel
    expect(mapStreamingProvider(1825)).toEqual([]); // HBO Max Amazon Channel
    expect(mapStreamingProvider(201)).toEqual([]); // MUBI Amazon Channel
  });

  test("rejects malformed and unknown upstream values", () => {
    expect(mapStreamingProvider("350")).toEqual([]);
    expect(mapStreamingProvider(Number.NaN)).toEqual([]);
    expect(mapStreamingProvider(undefined)).toEqual([]);
    expect(mapStreamingProvider(999_999)).toEqual([]);
  });
});
