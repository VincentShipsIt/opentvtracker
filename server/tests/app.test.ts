import { describe, expect, test } from "bun:test";
import { createApp, ResponseCache, type SafeLogEvent } from "../src/app";
import type { ServerConfig } from "../src/config";
import { AppAttestSecurity, MemoryDeviceStore } from "../src/security";
import type { CatalogTitle, TMDBClient } from "../src/tmdb";

type TestTMDB = Pick<
  TMDBClient,
  "search" | "title" | "reviews" | "resolveExternalID"
>;

describe("server application", () => {
  test("response cache evicts the oldest entry including an empty-string key", () => {
    const cache = new ResponseCache(2, () => 1_000);
    cache.set("", "empty", 60_000);
    cache.set("keep", "kept", 60_000);
    cache.set("newest", "fresh", 60_000);

    expect(cache.get("")).toBeUndefined();
    expect(cache.get("keep")?.body).toBe("kept");
    expect(cache.get("newest")?.body).toBe("fresh");
  });

  test("health is generic and the anonymous paid reranking route is absent", async () => {
    const app = testApp().app;

    const health = await app.fetch(new Request("https://example.test/health"));
    const rerank = await app.fetch(
      new Request("https://example.test/v1/recommendations/rerank", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ candidates: [] }),
      }),
    );

    const healthBody = await health.json();
    expect(healthBody).toEqual({ status: "ok" });
    expect(JSON.stringify(healthBody)).not.toContain("tmdb");
    expect(rerank.status).toBe(404);
  });

  test("kill switches fail closed before provider access", async () => {
    let providerCalls = 0;
    const config = testConfig();
    config.controls.catalogEnabled = false;
    const app = testApp(config, {
      search: async () => {
        providerCalls += 1;
        return [];
      },
      title: async () => {
        providerCalls += 1;
        throw new Error("not expected");
      },
      reviews: async () => {
        providerCalls += 1;
        return { page: 1, totalPages: 1, results: [] };
      },
      resolveExternalID: async () => {
        providerCalls += 1;
        return null;
      },
    }).app;

    const result = await app.fetch(
      developmentRequest("https://example.test/v1/catalog/search?q=Drama"),
    );

    expect(result.status).toBe(503);
    expect(providerCalls).toBe(0);
    expect(await result.json()).toEqual({
      error: "Service temporarily unavailable",
    });
  });

  test("the global kill switch also disables anonymous challenge issuance", async () => {
    const config = testConfig();
    config.controls.proxyEnabled = false;
    const app = testApp(config).app;

    const result = await app.fetch(
      new Request("https://example.test/v1/app-attest/challenge", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ purpose: "attestation" }),
      }),
    );

    expect(result.status).toBe(503);
    expect(await result.json()).toEqual({
      error: "Service temporarily unavailable",
    });
  });

  test("requires strict validation before provider access", async () => {
    let providerCalls = 0;
    const { app } = testApp(undefined, {
      search: async () => {
        providerCalls += 1;
        return [];
      },
      title: async () => {
        throw new Error("not expected");
      },
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => null,
    });

    const invalid = await app.fetch(
      developmentRequest(
        "https://example.test/v1/catalog/search?q=Drama&page=0",
      ),
    );

    expect(invalid.status).toBe(400);
    expect(providerCalls).toBe(0);
  });

  test("caches catalog responses only after authentication", async () => {
    let providerCalls = 0;
    const { app } = testApp(undefined, {
      search: async () => {
        providerCalls += 1;
        return [];
      },
      title: async () => {
        throw new Error("not expected");
      },
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => null,
    });

    const url =
      "https://example.test/v1/catalog/search?q=Drama&page=1&region=MT";
    const first = await app.fetch(developmentRequest(url));
    const second = await app.fetch(developmentRequest(url));
    const unauthenticated = await app.fetch(new Request(url));
    const limited = await app.fetch(developmentRequest(url));

    expect(unauthenticated.status).toBe(401);
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(limited.status).toBe(429);
    expect(first.headers.get("Cache-Control")).toContain("max-age=300");
    expect(first.headers.get("CDN-Cache-Control")).toBe("no-store");
    expect(providerCalls).toBe(1);
  });

  test("coalesces concurrent authenticated cache misses into one completed entry", async () => {
    let providerCalls = 0;
    const loadStarted = deferred<void>();
    const pendingTitle = deferred<CatalogTitle>();
    const { app } = testApp(undefined, {
      search: async () => [],
      title: async () => {
        providerCalls += 1;
        loadStarted.resolve();
        return pendingTitle.promise;
      },
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => null,
    });
    const url =
      "https://example.test/v1/catalog/series/95396?region=MT&language=en";

    const firstPending = app.fetch(developmentRequest(url));
    const secondPending = app.fetch(developmentRequest(url));
    await loadStarted.promise;

    pendingTitle.resolve(catalogTitle());
    const [first, second] = await Promise.all([firstPending, secondPending]);
    const [firstBody, secondBody] = await Promise.all([
      first.text(),
      second.text(),
    ]);

    expect([first.status, second.status]).toEqual([200, 200]);
    expect(providerCalls).toBe(1);
    expect(secondBody).toBe(firstBody);
    expect(first.headers.get("ETag")).not.toBeNull();
    expect(second.headers.get("ETag")).toBe(first.headers.get("ETag"));
    expect(first.headers.get("Cache-Control")).toContain("private");
    expect(first.headers.get("CDN-Cache-Control")).toBe("no-store");
    expect(first.headers.get("Vary")).toBe(
      "Authorization, X-App-Attest-Key-ID",
    );

    const conditional = developmentRequest(url);
    conditional.headers.set("If-None-Match", first.headers.get("ETag")!);
    const notModified = await app.fetch(conditional);

    expect(notModified.status).toBe(304);
    expect(notModified.headers.get("ETag")).toBe(first.headers.get("ETag"));
    expect(notModified.headers.get("Cache-Control")).toBe(
      first.headers.get("Cache-Control"),
    );
    expect(notModified.headers.get("CDN-Cache-Control")).toBe("no-store");
    expect(notModified.headers.get("Vary")).toBe(
      "Authorization, X-App-Attest-Key-ID",
    );
    expect(providerCalls).toBe(1);
  });

  test("clears a rejected shared load so a later request retries", async () => {
    let providerCalls = 0;
    const loadStarted = deferred<void>();
    const firstLoad = deferred<CatalogTitle>();
    const { app } = testApp(undefined, {
      search: async () => [],
      title: async () => {
        providerCalls += 1;
        if (providerCalls === 1) {
          loadStarted.resolve();
          return firstLoad.promise;
        }
        return catalogTitle();
      },
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => null,
    });
    const url = "https://example.test/v1/catalog/series/95396?region=MT";

    const firstPending = app.fetch(developmentRequest(url));
    const secondPending = app.fetch(developmentRequest(url));
    await loadStarted.promise;

    firstLoad.reject(new Error("upstream failed"));
    const failures = await Promise.all([firstPending, secondPending]);

    expect(failures.map((result) => result.status)).toEqual([502, 502]);
    expect(providerCalls).toBe(1);
    expect(await failures[0].text()).toBe(await failures[1].text());

    const retry = await app.fetch(developmentRequest(url));
    const cached = await app.fetch(developmentRequest(url));

    expect([retry.status, cached.status]).toEqual([200, 200]);
    expect(providerCalls).toBe(2);
  });

  test("coalesces concurrent unresolved external IDs without caching null", async () => {
    let providerCalls = 0;
    const loadStarted = deferred<void>();
    const firstLoad = deferred<CatalogTitle | null>();
    const { app } = testApp(undefined, {
      search: async () => [],
      title: async () => {
        throw new Error("not expected");
      },
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => {
        providerCalls += 1;
        if (providerCalls === 1) {
          loadStarted.resolve();
          return firstLoad.promise;
        }
        return null;
      },
    });
    const url =
      "https://example.test/v1/catalog/resolve/tvdb/999999?kind=series&region=MT";

    const firstPending = app.fetch(developmentRequest(url));
    const secondPending = app.fetch(developmentRequest(url));
    await loadStarted.promise;

    firstLoad.resolve(null);
    const unresolved = await Promise.all([firstPending, secondPending]);

    expect(unresolved.map((result) => result.status)).toEqual([404, 404]);
    expect(providerCalls).toBe(1);
    expect(await unresolved[0].text()).toBe(await unresolved[1].text());
    expect(unresolved[0].headers.get("Cache-Control")).toBe("no-store");
    expect(unresolved[0].headers.get("ETag")).toBeNull();

    const later = await app.fetch(developmentRequest(url));

    expect(later.status).toBe(404);
    expect(providerCalls).toBe(2);
  });

  test("loads distinct cache keys independently", async () => {
    let providerCalls = 0;
    let activeLoads = 0;
    let maximumActiveLoads = 0;
    const { app } = testApp(undefined, {
      search: async () => [],
      title: async (_kind, id) => {
        providerCalls += 1;
        activeLoads += 1;
        maximumActiveLoads = Math.max(maximumActiveLoads, activeLoads);
        await Promise.resolve();
        activeLoads -= 1;
        return { ...catalogTitle(), catalogID: id, title: `Title ${id}` };
      },
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => null,
    });
    const [first, second] = await Promise.all([
      app.fetch(
        developmentRequest(
          "https://example.test/v1/catalog/series/95396?region=MT",
        ),
      ),
      app.fetch(
        developmentRequest(
          "https://example.test/v1/catalog/series/1396?region=MT",
        ),
      ),
    ]);
    const [firstBody, secondBody] = await Promise.all([
      first.json(),
      second.json(),
    ]);

    expect([first.status, second.status]).toEqual([200, 200]);
    expect(providerCalls).toBe(2);
    expect(maximumActiveLoads).toBe(2);
    expect(firstBody.title).toBe("Title 95396");
    expect(secondBody.title).toBe("Title 1396");
  });

  test("forwards content language to catalog search and title requests", async () => {
    const requestedLanguages: string[] = [];
    const { app } = testApp(undefined, {
      search: async (_query, _kind, _page, _region, language) => {
        requestedLanguages.push(language);
        return [];
      },
      title: async (_kind, _id, _region, language) => {
        requestedLanguages.push(language);
        return catalogTitle();
      },
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => null,
    });

    const search = await app.fetch(
      developmentRequest(
        "https://example.test/v1/catalog/search?page=1&region=MT&language=fr",
      ),
    );
    const title = await app.fetch(
      developmentRequest(
        "https://example.test/v1/catalog/series/95396?region=MT&language=es",
      ),
    );

    expect(search.status).toBe(200);
    expect(title.status).toBe(200);
    expect(requestedLanguages).toEqual(["fr", "es"]);
  });

  test("returns protected, cached review pages from the bounded route", async () => {
    let providerCalls = 0;
    const { app } = testApp(undefined, {
      search: async () => [],
      title: async () => {
        throw new Error("not expected");
      },
      reviews: async (_kind, _id, page) => {
        providerCalls += 1;
        return { page, totalPages: 3, results: [] };
      },
      resolveExternalID: async () => null,
    });
    const url = "https://example.test/v1/catalog/series/95396/reviews?page=2";

    const first = await app.fetch(developmentRequest(url));
    const second = await app.fetch(developmentRequest(url));

    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(await first.json()).toMatchObject({ page: 2, totalPages: 3 });
    expect(providerCalls).toBe(1);
  });

  test("caches only confirmed external ID mappings after authentication", async () => {
    let providerCalls = 0;
    const resolved = catalogTitle();
    const { app } = testApp(undefined, {
      search: async () => [],
      title: async () => resolved,
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => {
        providerCalls += 1;
        return resolved;
      },
    });
    const url =
      "https://example.test/v1/catalog/resolve/tvdb/371980?kind=series&region=MT";

    const unauthenticated = await app.fetch(new Request(url));
    const first = await app.fetch(developmentRequest(url));
    const second = await app.fetch(developmentRequest(url));

    expect(unauthenticated.status).toBe(401);
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(first.headers.get("Cache-Control")).toContain("max-age=604800");
    expect(providerCalls).toBe(1);
  });

  test("does not cache unresolved external IDs", async () => {
    let providerCalls = 0;
    const { app } = testApp(undefined, {
      search: async () => [],
      title: async () => {
        throw new Error("not expected");
      },
      reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
      resolveExternalID: async () => {
        providerCalls += 1;
        return null;
      },
    });
    const url =
      "https://example.test/v1/catalog/resolve/tvdb/999999?kind=series&region=MT";

    const first = await app.fetch(developmentRequest(url));
    const second = await app.fetch(developmentRequest(url));

    expect(first.status).toBe(404);
    expect(second.status).toBe(404);
    expect(providerCalls).toBe(2);
  });

  test("authenticated invalid requests count toward the development quota", async () => {
    const { app } = testApp();
    const invalidURL = "https://example.test/v1/catalog/search?q=Drama&page=0";

    const first = await app.fetch(developmentRequest(invalidURL));
    const second = await app.fetch(developmentRequest(invalidURL));
    const limited = await app.fetch(
      developmentRequest(
        "https://example.test/v1/catalog/search?q=Drama&page=1&region=MT",
      ),
    );

    expect(first.status).toBe(400);
    expect(second.status).toBe(400);
    expect(limited.status).toBe(429);
  });

  test("applies a deliberately lower device quota to the development bypass", async () => {
    const { app } = testApp();
    let last = new Response();
    for (let index = 0; index < 16; index += 1) {
      last = await app.fetch(
        developmentRequest(
          `https://example.test/v1/catalog/search?q=Title${index}&page=1&region=MT`,
        ),
        "192.0.2.1",
      );
    }

    expect(last.status).toBe(429);
    expect(last.headers.get("Retry-After")).not.toBeNull();
  });

  test("structured logs omit query values, IPs, credentials, assertions, and bodies", async () => {
    const logs: SafeLogEvent[] = [];
    const { app } = testApp(undefined, undefined, (event) => logs.push(event));
    const request = developmentRequest(
      "https://example.test/v1/catalog/search?q=PRIVATE-NAME&page=1&region=MT",
    );
    request.headers.set("Authorization", "Bearer TOP-SECRET");
    request.headers.set("X-App-Attest-Assertion", "PRIVATE-ASSERTION");

    await app.fetch(request, "203.0.113.77");

    const serialized = JSON.stringify(logs);
    expect(serialized).not.toContain("PRIVATE-NAME");
    expect(serialized).not.toContain("TOP-SECRET");
    expect(serialized).not.toContain("PRIVATE-ASSERTION");
    expect(serialized).not.toContain("203.0.113.77");
    expect(logs[0]).toMatchObject({
      path: "/v1/catalog/search",
      method: "GET",
      status: 200,
    });
  });
});

function testApp(
  suppliedConfig?: ServerConfig,
  tmdb?: TestTMDB,
  logger: (event: SafeLogEvent) => void = () => {},
) {
  const config = suppliedConfig ?? testConfig();
  const security = new AppAttestSecurity(
    config.appAttest,
    new MemoryDeviceStore(),
    {
      verifyAttestation: () => {
        throw new Error("not used");
      },
      verifyAssertion: () => {
        throw new Error("not used");
      },
    },
  );
  return {
    app: createApp({
      config,
      security,
      tmdb: tmdb ?? {
        search: async () => [],
        title: async () => {
          throw new Error("not used");
        },
        reviews: async () => ({ page: 1, totalPages: 1, results: [] }),
        resolveExternalID: async () => null,
      },
      logger,
      now: () => Date.parse("2026-07-15T12:00:00Z"),
    }),
  };
}

function catalogTitle(): CatalogTitle {
  return {
    catalogID: 95_396,
    title: "Severance",
    alternativeTitles: [],
    year: 2022,
    kind: "series",
    synopsis: "",
    genres: ["Drama"],
    runtimeMinutes: 50,
    rating: 8.7,
    mood: "thoughtful",
    posterURL: null,
    backdropURL: null,
    trailerURL: null,
    providers: [],
    reviews: [],
    releaseDate: "2022-02-18T00:00:00Z",
    nextEpisodeAirDate: null,
    nextEpisodeAirDateIsAllDay: null,
    seasons: null,
    seriesLifecycle: "continuing",
  };
}

function developmentRequest(url: string): Request {
  return new Request(url, {
    headers: { "X-OpenTV-Development-Token": "local-development-only" },
  });
}

function deferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T | PromiseLike<T>) => void;
  reject: (reason?: unknown) => void;
} {
  let resolve!: (value: T | PromiseLike<T>) => void;
  let reject!: (reason?: unknown) => void;
  const promise = new Promise<T>((resolvePromise, rejectPromise) => {
    resolve = resolvePromise;
    reject = rejectPromise;
  });
  return { promise, resolve, reject };
}

function testConfig(): ServerConfig {
  return {
    port: 8787,
    tmdbToken: "not-a-real-provider-key",
    appAttest: {
      mode: "development",
      teamID: "C76R5DRH64",
      bundleID: "dev.opentvtracker.app",
      tokenSecret: "test-token-secret-that-is-at-least-thirty-two-characters",
      statePath: "unused",
      challengeTTLSeconds: 60,
      tokenTTLSeconds: 600,
      developmentBypassToken: "local-development-only",
    },
    controls: {
      proxyEnabled: true,
      catalogEnabled: true,
      cinemaEnabled: true,
      registrationEnabled: true,
    },
  };
}
