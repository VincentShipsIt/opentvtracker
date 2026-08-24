import { describe, expect, test } from "bun:test";
import {
  mapAlternativeTitles,
  mapEpisodeSummary,
  mapReviewPage,
  mapReviews,
  mapSeriesLifecycle,
  mapStreamingProvider,
  StreamingProviderID,
  TMDBCapacityError,
  TMDBClient,
  TMDBProviderID,
  TMDBTimeoutError,
  type TMDBFetch,
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

describe("TMDBClient upstream scheduling", () => {
  test("shares one active ceiling across simultaneous searches and a series title", async () => {
    let activeRequests = 0;
    let maximumActiveRequests = 0;
    const fetch: TMDBFetch = async (input) => {
      activeRequests += 1;
      maximumActiveRequests = Math.max(maximumActiveRequests, activeRequests);
      await delay(1);
      const url = new URL(String(input));
      const payload = tmdbPayload(url);
      return jsonResponse(payload, 200, async () => {
        await delay(1);
        activeRequests -= 1;
        return payload;
      });
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 3,
      maximumPendingRequests: 64,
      requestDeadlineMilliseconds: 2_000,
    });

    const [first, second, title] = await Promise.all([
      client.search("drama", null, 1, "MT", "en"),
      client.search("comedy", null, 1, "MT", "en"),
      client.title("series", 900, "MT", "en"),
    ]);

    expect(first).toHaveLength(12);
    expect(second).toHaveLength(12);
    expect(title.seasons).toHaveLength(10);
    expect(maximumActiveRequests).toBe(3);
    expect(activeRequests).toBe(0);
  });

  test("starts search enrichment in bounded waves instead of one promise per item", async () => {
    const pendingDetails: Array<Deferred<Response>> = [];
    const fetch: TMDBFetch = async (input) => {
      const url = new URL(String(input));
      if (url.pathname === "/3/search/multi") {
        return jsonResponse({
          results: Array.from({ length: 20 }, (_, index) => ({
            id: index + 1,
            media_type: "movie",
          })),
        });
      }
      const pending = deferred<Response>();
      pendingDetails.push(pending);
      return pending.promise;
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 20,
      maximumPendingRequests: 20,
      requestDeadlineMilliseconds: 2_000,
    });

    const search = client.search("bounded", null, 1, "MT", "en");
    await waitFor(() => pendingDetails.length === 8);
    expect(pendingDetails).toHaveLength(8);
    pendingDetails
      .slice(0, 8)
      .forEach((pending, index) =>
        pending.resolve(jsonResponse(titleDetails(index + 1))),
      );
    await waitFor(() => pendingDetails.length === 16);
    expect(pendingDetails).toHaveLength(16);
    pendingDetails
      .slice(8, 16)
      .forEach((pending, index) =>
        pending.resolve(jsonResponse(titleDetails(index + 9))),
      );
    await waitFor(() => pendingDetails.length === 20);
    pendingDetails
      .slice(16)
      .forEach((pending, index) =>
        pending.resolve(jsonResponse(titleDetails(index + 17))),
      );

    expect((await search).map((title) => title.catalogID)).toEqual(
      Array.from({ length: 20 }, (_, index) => index + 1),
    );
  });

  test("starts season enrichment in bounded waves", async () => {
    const pendingSeasons: Array<{
      number: number;
      response: Deferred<Response>;
    }> = [];
    const fetch: TMDBFetch = async (input) => {
      const url = new URL(String(input));
      if (url.pathname === "/3/tv/900") {
        return jsonResponse({
          ...titleDetails(900, "series"),
          seasons: Array.from({ length: 20 }, (_, season_number) => ({
            season_number,
          })),
        });
      }
      const response = deferred<Response>();
      pendingSeasons.push({
        number: Number(url.pathname.split("/").at(-1)),
        response,
      });
      return response.promise;
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 20,
      maximumPendingRequests: 20,
      requestDeadlineMilliseconds: 2_000,
    });

    const title = client.title("series", 900, "MT", "en");
    await waitFor(() => pendingSeasons.length === 8);
    expect(pendingSeasons).toHaveLength(8);
    pendingSeasons.slice(0, 8).forEach(({ number, response }) =>
      response.resolve(jsonResponse({ season_number: number, episodes: [] })),
    );
    await waitFor(() => pendingSeasons.length === 16);
    pendingSeasons.slice(8, 16).forEach(({ number, response }) =>
      response.resolve(jsonResponse({ season_number: number, episodes: [] })),
    );
    await waitFor(() => pendingSeasons.length === 20);
    pendingSeasons.slice(16).forEach(({ number, response }) =>
      response.resolve(jsonResponse({ season_number: number, episodes: [] })),
    );

    expect((await title).seasons?.map((season) => season.number)).toEqual(
      Array.from({ length: 20 }, (_, index) => index),
    );
  });

  test("admits exactly active plus pending requests and starts them FIFO", async () => {
    const started: string[] = [];
    const pending: Array<Deferred<Response>> = [];
    const fetch: TMDBFetch = async (input) => {
      started.push(new URL(String(input)).searchParams.get("page") ?? "");
      const request = deferred<Response>();
      pending.push(request);
      return request.promise;
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 1,
      maximumPendingRequests: 2,
      requestDeadlineMilliseconds: 2_000,
    });

    const first = client.reviews("movie", 1, 1);
    const second = client.reviews("movie", 1, 2);
    const third = client.reviews("movie", 1, 3);
    const overloaded = client.reviews("movie", 1, 4).catch((error) => error);
    await waitFor(() => started.length === 1);

    expect(await overloaded).toBeInstanceOf(TMDBCapacityError);
    expect(started).toEqual(["1"]);
    pending[0]!.resolve(jsonResponse({ results: [] }));
    await waitFor(() => started.length === 2);
    pending[1]!.resolve(jsonResponse({ results: [] }));
    await waitFor(() => started.length === 3);
    pending[2]!.resolve(jsonResponse({ results: [] }));

    await Promise.all([first, second, third]);
    expect(started).toEqual(["1", "2", "3"]);
  });

  test("removes timed-out queued work so later requests regain pending capacity", async () => {
    let call = 0;
    const fetch: TMDBFetch = async (_input, init) => {
      call += 1;
      if (call === 3) return jsonResponse({ results: [] });
      return new Promise<Response>((_resolve, reject) => {
        init?.signal?.addEventListener("abort", () =>
          reject(new DOMException("timed out", "AbortError")),
        );
      });
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 1,
      maximumPendingRequests: 1,
      requestDeadlineMilliseconds: 15,
    });

    const active = client.reviews("movie", 1, 1).catch((error) => error);
    const queued = client.reviews("movie", 1, 2).catch((error) => error);
    expect(await active).toBeInstanceOf(TMDBTimeoutError);
    expect(await queued).toBeInstanceOf(TMDBTimeoutError);
    await expect(client.reviews("movie", 1, 3)).resolves.toMatchObject({
      page: 3,
      results: [],
    });
    expect(call).toBe(3);
  });

  test("retains input order when detail requests finish out of order and omits failures", async () => {
    const details = new Map<number, Deferred<Response>>();
    const fetch: TMDBFetch = async (input) => {
      const url = new URL(String(input));
      if (url.pathname === "/3/search/multi") {
        return jsonResponse({
          results: [1, 2, 3].map((id) => ({ id, media_type: "movie" })),
        });
      }
      const id = Number(url.pathname.split("/").at(-1));
      const pending = deferred<Response>();
      details.set(id, pending);
      return pending.promise;
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 3,
      requestDeadlineMilliseconds: 2_000,
    });

    const search = client.search("ordered", null, 1, "MT", "en");
    await waitFor(() => details.size === 3);
    details.get(3)!.resolve(jsonResponse(titleDetails(3)));
    details.get(2)!.reject(new Error("detail unavailable"));
    details.get(1)!.resolve(jsonResponse(titleDetails(1)));

    expect((await search).map((title) => title.catalogID)).toEqual([1, 3]);
  });

  test("deduplicates valid season numbers and returns partial results in numeric order", async () => {
    const seasonPaths: string[] = [];
    const fetch: TMDBFetch = async (input) => {
      const url = new URL(String(input));
      if (url.pathname === "/3/tv/900") {
        return jsonResponse({
          ...titleDetails(900, "series"),
          seasons: [
            3,
            1,
            3,
            0,
            -1,
            1.5,
            Number.MAX_SAFE_INTEGER + 1,
            Number.NaN,
            "2",
          ].map((season_number) => ({ season_number })),
        });
      }
      seasonPaths.push(url.pathname);
      const number = Number(url.pathname.split("/").at(-1));
      await delay(4 - number);
      if (number === 1) throw new Error("season unavailable");
      return jsonResponse({ season_number: number, episodes: [] });
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 8,
      requestDeadlineMilliseconds: 2_000,
    });

    const title = await client.title("series", 900, "MT", "en");

    expect(new Set(seasonPaths)).toEqual(
      new Set(["/3/tv/900/season/3", "/3/tv/900/season/1", "/3/tv/900/season/0"]),
    );
    expect(seasonPaths).toHaveLength(3);
    expect(title.seasons?.map((season) => season.number)).toEqual([0, 3]);
  });

  test("holds a permit through JSON decoding", async () => {
    const decoding = deferred<unknown>();
    const started: string[] = [];
    const fetch: TMDBFetch = async (input) => {
      const page = new URL(String(input)).searchParams.get("page") ?? "";
      started.push(page);
      return page === "1"
        ? jsonResponse({}, 200, () => decoding.promise)
        : jsonResponse({ results: [] });
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 1,
      requestDeadlineMilliseconds: 2_000,
    });

    const first = client.reviews("movie", 1, 1);
    const second = client.reviews("movie", 1, 2);
    await waitFor(() => started.length === 1);
    await delay(5);
    expect(started).toEqual(["1"]);
    decoding.resolve({ results: [] });
    await Promise.all([first, second]);
    expect(started).toEqual(["1", "2"]);
  });

  test("releases the sole permit after every upstream failure mode", async () => {
    let call = 0;
    const fetch: TMDBFetch = async (_input, init) => {
      call += 1;
      switch (call) {
        case 1:
          return jsonResponse({}, 503);
        case 2:
          return jsonResponse({}, 200, async () => {
            throw new Error("invalid JSON");
          });
        case 3:
          throw new Error("fetch failed");
        case 4:
          throw new DOMException("aborted", "AbortError");
        case 5:
          return new Promise<Response>((_resolve, reject) => {
            init?.signal?.addEventListener("abort", () =>
              reject(new DOMException("timed out", "AbortError")),
            );
          });
        default:
          return jsonResponse({ results: [] });
      }
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 1,
      maximumPendingRequests: 1,
      requestDeadlineMilliseconds: 15,
    });

    await expect(client.reviews("movie", 1, 1)).rejects.toThrow(
      "TMDB returned 503",
    );
    await expect(client.reviews("movie", 1, 2)).rejects.toThrow(
      "invalid JSON",
    );
    await expect(client.reviews("movie", 1, 3)).rejects.toThrow(
      "fetch failed",
    );
    await expect(client.reviews("movie", 1, 4)).rejects.toThrow("aborted");
    await expect(client.reviews("movie", 1, 5)).rejects.toBeInstanceOf(
      TMDBTimeoutError,
    );
    await expect(client.reviews("movie", 1, 6)).resolves.toMatchObject({
      page: 6,
      results: [],
    });
    expect(call).toBe(6);
  });

  test("does not deadlock when external-ID resolution continues into title loading", async () => {
    const started: string[] = [];
    const fetch: TMDBFetch = async (input) => {
      const url = new URL(String(input));
      started.push(url.pathname);
      return url.pathname.startsWith("/3/find/")
        ? jsonResponse({ movie_results: [{ id: 42 }] })
        : jsonResponse(titleDetails(42));
    };
    const client = new TMDBClient("test-token", {
      fetch,
      maximumActiveRequests: 1,
      maximumPendingRequests: 0,
      requestDeadlineMilliseconds: 100,
    });

    const title = await client.resolveExternalID("tvdb", 7, "movie", "MT");

    expect(title?.catalogID).toBe(42);
    expect(started).toEqual(["/3/find/7", "/3/movie/42"]);
  });

  test("rejects unsafe injected scheduler limits", () => {
    const invalidOptions = [
      { maximumActiveRequests: 0 },
      { maximumActiveRequests: 1.5 },
      { maximumPendingRequests: -1 },
      { maximumPendingRequests: Number.POSITIVE_INFINITY },
      { requestDeadlineMilliseconds: 0 },
      { requestDeadlineMilliseconds: Number.MAX_SAFE_INTEGER + 1 },
    ];

    for (const options of invalidOptions) {
      expect(() => new TMDBClient("test-token", options)).toThrow(RangeError);
    }
  });
});

type Deferred<Value> = {
  promise: Promise<Value>;
  resolve: (value: Value) => void;
  reject: (reason?: unknown) => void;
};

function deferred<Value>(): Deferred<Value> {
  let resolve!: (value: Value) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<Value>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

function jsonResponse(
  payload: unknown,
  status = 200,
  decode: () => Promise<unknown> = async () => payload,
): Response {
  return {
    ok: status >= 200 && status < 300,
    status,
    json: decode,
  } as Response;
}

function titleDetails(id: number, kind: "movie" | "series" = "movie") {
  return kind === "movie"
    ? { id, title: `Movie ${id}`, release_date: "2026-01-01" }
    : { id, name: `Series ${id}`, first_air_date: "2026-01-01" };
}

function tmdbPayload(url: URL): unknown {
  if (url.pathname === "/3/search/multi") {
    return {
      results: Array.from({ length: 12 }, (_, index) => ({
        id: index + 1,
        media_type: "movie",
      })),
    };
  }
  if (url.pathname === "/3/tv/900") {
    return {
      ...titleDetails(900, "series"),
      seasons: Array.from({ length: 10 }, (_, season_number) => ({
        season_number,
      })),
    };
  }
  const season = url.pathname.match(/\/season\/(\d+)$/)?.[1];
  if (season !== undefined) {
    return { season_number: Number(season), episodes: [] };
  }
  return titleDetails(Number(url.pathname.split("/").at(-1)));
}

async function waitFor(predicate: () => boolean): Promise<void> {
  for (let attempt = 0; attempt < 200; attempt += 1) {
    if (predicate()) return;
    await delay(1);
  }
  throw new Error("Timed out waiting for test condition");
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
