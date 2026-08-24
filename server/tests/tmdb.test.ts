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
  tmdbDiscoverRequests,
  tmdbLocale,
} from "../src/tmdb";

describe("tmdbLocale", () => {
  test("expands ISO language codes to TMDB locales", () => {
    expect(tmdbLocale("en")).toBe("en-US");
    expect(tmdbLocale("fr")).toBe("fr-FR");
    expect(tmdbLocale("mt")).toBe("mt-MT");
  });
});

describe("tmdbDiscoverRequests", () => {
  test("filters default browsing by the selected original language", () => {
    const requests = tmdbDiscoverRequests("fr", 2, null);

    expect(requests.map((request) => request.mediaType)).toEqual([
      "movie",
      "tv",
    ]);
    for (const request of requests) {
      const url = new URL(request.path, "https://api.themoviedb.org");
      expect(url.searchParams.get("language")).toBe("fr-FR");
      expect(url.searchParams.get("with_original_language")).toBe("fr");
      expect(url.searchParams.get("page")).toBe("1");
      expect(request.resultOffset).toBe(10);
      expect(request.resultLimit).toBe(10);
    }
  });

  test("keeps every mixed-media discover result reachable across pages", () => {
    const first = tmdbDiscoverRequests("en", 1, null);
    const second = tmdbDiscoverRequests("en", 2, null);
    const third = tmdbDiscoverRequests("en", 3, null);

    expect(first.map((request) => request.resultOffset)).toEqual([0, 0]);
    expect(second.map((request) => request.resultOffset)).toEqual([10, 10]);
    expect(
      third.map((request) => {
        const url = new URL(request.path, "https://api.themoviedb.org");
        return [url.searchParams.get("page"), request.resultOffset];
      }),
    ).toEqual([
      ["2", 0],
      ["2", 0],
    ]);
  });

  test("keeps single-kind browsing aligned with provider pages", () => {
    const [request] = tmdbDiscoverRequests("fr", 2, "movie");

    const url = new URL(request!.path, "https://api.themoviedb.org");
    expect(url.searchParams.get("page")).toBe("2");
    expect(request!.resultOffset).toBe(0);
    expect(request!.resultLimit).toBe(20);
  });
});

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
      id: "tmdb-review-provider-review-id",
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
      "tmdb-review-provider-stable",
      "tmdb-review-fallback-2-1",
    ]);
  });

  test("keeps the requested review page when TMDB reports a mismatched page", () => {
    const page = mapReviewPage(
      { page: 1, total_pages: 4, results: [{ content: "Review" }] },
      3,
    );

    expect(page.page).toBe(3);
    expect(page.results[0]?.id).toBe("tmdb-review-fallback-3-0");
  });

  test("keeps provider and fallback identities distinct during pagination deduplication", () => {
    const fallback = mapReviewPage(
      { results: [{ content: "Fallback review" }] },
      1,
    ).results[0]!;
    const provider = mapReviewPage(
      { results: [{ id: "fallback-1-0", content: "Provider review" }] },
      2,
    ).results[0]!;
    const seenIDs = new Set<string>();
    const paginated = [fallback, fallback, provider, provider].filter((review) =>
      seenIDs.has(review.id) ? false : Boolean(seenIDs.add(review.id)),
    );

    expect(paginated.map((review) => review.id)).toEqual([
      "tmdb-review-fallback-1-0",
      "tmdb-review-provider-fallback-1-0",
    ]);
    expect(paginated.map((review) => review.excerpt)).toEqual([
      "Fallback review",
      "Provider review",
    ]);
  });

  test("accepts only provider-relative avatar artwork on the TMDB image CDN", () => {
    const avatarPaths = [
      ["/avatar.jpg", "https://image.tmdb.org/t/p/w185/avatar.jpg"],
      [undefined, null],
      ["", null],
      ["/https://secure.gravatar.com/avatar/hash?s=200", null],
      ["/http://secure.gravatar.com/avatar/hash", null],
      ["https://attacker.example/avatar.jpg", null],
      ["http://attacker.example/avatar.jpg", null],
      ["//attacker.example/avatar.jpg", null],
      ["/image.tmdb.org.attacker.example/avatar.jpg", null],
      ["https://user:password@image.tmdb.org/avatar.jpg", null],
      ["data:image/png;base64,AAAA", null],
      ["javascript:alert(1)", null],
      ["/\\attacker.example/avatar.jpg", null],
      ["/avatar.jpg?redirect=https://attacker.example", null],
      ["/avatar.jpg#attacker", null],
    ] as const;

    const mapped = mapReviews({
      results: avatarPaths.map(([avatarPath], index) => ({
        id: `avatar-${index}`,
        content: "Review",
        author_details: { avatar_path: avatarPath },
      })),
    }, 1, avatarPaths.length);

    expect(mapped.map((review) => review.avatarURL)).toEqual(
      avatarPaths.map(([, expected]) => expected),
    );
  });

  test("derives original-review links from bounded provider identifiers", () => {
    const mapped = mapReviews({
      results: [
        { id: "safe_review-123", content: "No upstream URL" },
        {
          id: "safe-review-456",
          content: "Hostile upstream URL",
          url: "https://attacker.example/review/stolen",
        },
        {
          id: "safe-review-789",
          content: "Mismatched upstream URL",
          url: "https://www.themoviedb.org/review/different-id",
        },
      ],
    });

    expect(mapped.map((review) => review.sourceURL)).toEqual([
      "https://www.themoviedb.org/review/safe_review-123",
      "https://www.themoviedb.org/review/safe-review-456",
      "https://www.themoviedb.org/review/safe-review-789",
    ]);
  });

  test("canonicalizes only strict TMDB review URLs when the provider ID is unavailable", () => {
    const sourceURLs = [
      [
        "https://www.themoviedb.org/review/fallback-id",
        "https://www.themoviedb.org/review/fallback-id",
      ],
      ["http://www.themoviedb.org/review/review-id", null],
      ["//www.themoviedb.org/review/review-id", null],
      ["https://user:password@www.themoviedb.org/review/review-id", null],
      ["https://www.themoviedb.org:443/review/review-id", null],
      ["https://themoviedb.org/review/review-id", null],
      ["https://reviews.themoviedb.org/review/review-id", null],
      ["https://www.themoviedb.org.attacker.example/review/review-id", null],
      ["https://www.themoviedb.org/movie/review-id", null],
      ["https://www.themoviedb.org/review/review-id/extra", null],
      ["https://www.themoviedb.org/review/invalid.id", null],
      ["https://www.themoviedb.org/review/review-id?redirect=attacker", null],
      ["https://www.themoviedb.org/review/review-id#attacker", null],
      ["not a URL", null],
    ] as const;

    const mapped = mapReviews({
      results: sourceURLs.map(([url]) => ({ content: "Review", url })),
    }, 4, sourceURLs.length);

    expect(mapped.map((review) => review.sourceURL)).toEqual(
      sourceURLs.map(([, expected]) => expected),
    );
    expect(mapped.map((review) => review.id)).toEqual(
      sourceURLs.map((_, index) => `tmdb-review-fallback-4-${index}`),
    );
  });

  test("uses page identities for invalid or oversized provider IDs", () => {
    const invalidIDs = [
      "slash/id",
      "dot.id",
      "percent%2Fid",
      "unicode-é",
      " spaced ",
      "query?id",
      "fragment#id",
      "x".repeat(129),
    ];

    const page = mapReviewPage(
      {
        results: invalidIDs.map((id) => ({
          id,
          content: "Review",
          url: `https://attacker.example/review/${id}`,
        })),
      },
      3,
    );

    expect(page.results.map((review) => review.id)).toEqual(
      invalidIDs.map((_, index) => `tmdb-review-fallback-3-${index}`),
    );
    expect(page.results.every((review) => review.sourceURL === null)).toBe(true);
  });

  test("uses the same URL trust boundary for embedded and paginated reviews", () => {
    const payload = {
      results: [
        {
          id: "shared-review",
          content: "Review",
          author_details: { avatar_path: "//attacker.example/avatar.jpg" },
          url: "https://attacker.example/review/shared-review",
        },
      ],
    };

    expect(mapReviewPage(payload, 2).results).toEqual(
      mapReviews(payload, 2, 20),
    );
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
