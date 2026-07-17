import { describe, expect, test } from "bun:test";
import { createApp, type SafeLogEvent } from "../src/app";
import type { ServerConfig } from "../src/config";
import { AppAttestSecurity, MemoryDeviceStore } from "../src/security";
import type { CatalogTitle, TMDBClient } from "../src/tmdb";

type TestTMDB = Pick<TMDBClient, "search" | "title" | "resolveExternalID">;

describe("server application", () => {
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
      resolveExternalID: async () => null,
    });

    const url =
      "https://example.test/v1/catalog/search?q=Drama&page=1&region=MT";
    const unauthenticated = await app.fetch(new Request(url));
    const first = await app.fetch(developmentRequest(url));
    const second = await app.fetch(developmentRequest(url));

    expect(unauthenticated.status).toBe(401);
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(first.headers.get("Cache-Control")).toContain("max-age=300");
    expect(first.headers.get("CDN-Cache-Control")).toBe("no-store");
    expect(providerCalls).toBe(1);
  });

  test("caches only confirmed external ID mappings after authentication", async () => {
    let providerCalls = 0;
    const resolved = catalogTitle();
    const { app } = testApp(undefined, {
      search: async () => [],
      title: async () => resolved,
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
    seasons: null,
  };
}

function developmentRequest(url: string): Request {
  return new Request(url, {
    headers: { "X-OpenTV-Development-Token": "local-development-only" },
  });
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
