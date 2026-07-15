import { describe, expect, test } from "bun:test";
import { createApp, type SafeLogEvent } from "../src/app";
import type { ServerConfig } from "../src/config";
import { AppAttestSecurity, MemoryDeviceStore } from "../src/security";
import type { TMDBClient } from "../src/tmdb";

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

  test("requires strict validation and caches only after authentication", async () => {
    let providerCalls = 0;
    const { app } = testApp(undefined, {
      search: async () => {
        providerCalls += 1;
        return [];
      },
      title: async () => {
        throw new Error("not expected");
      },
    });

    const invalid = await app.fetch(
      developmentRequest(
        "https://example.test/v1/catalog/search?q=Drama&page=0",
      ),
    );
    const first = await app.fetch(
      developmentRequest(
        "https://example.test/v1/catalog/search?q=Drama&page=1&region=MT",
      ),
    );
    const second = await app.fetch(
      developmentRequest(
        "https://example.test/v1/catalog/search?q=Drama&page=1&region=MT",
      ),
    );

    expect(invalid.status).toBe(400);
    expect(first.status).toBe(200);
    expect(second.status).toBe(200);
    expect(first.headers.get("CDN-Cache-Control")).toBe("no-store");
    expect(providerCalls).toBe(1);
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
  tmdb?: Pick<TMDBClient, "search" | "title">,
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
      },
      logger,
      now: () => Date.parse("2026-07-15T12:00:00Z"),
    }),
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
      bundleID: "dev.shipshit.opentvtracker",
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
