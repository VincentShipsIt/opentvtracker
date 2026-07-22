import { createHash, randomUUID } from "node:crypto";
import { embassyShowings } from "./cinema";
import type { ServerConfig } from "./config";
import {
  AppAttestHeaders,
  AppAttestSecurity,
  BoundedRateLimiter,
  SecurityError,
} from "./security";
import { TMDBClient } from "./tmdb";
import {
  readJSONBody,
  validateCatalogExternalID,
  validateCatalogReviews,
  validateCatalogSearch,
  validateCatalogTitle,
  validateChallengeRequest,
  validateCinemaShowings,
  validateEmptyObject,
  validateRegistrationRequest,
  ValidationError,
} from "./validation";

export type SafeLogEvent = {
  event: "request";
  requestID: string;
  method: string;
  path: string;
  status: number;
  code: string;
  durationMilliseconds: number;
};

export type SafeLogger = (event: SafeLogEvent) => void;

type AppDependencies = {
  config: ServerConfig;
  security: AppAttestSecurity;
  tmdb?: Pick<TMDBClient, "search" | "title" | "reviews" | "resolveExternalID">;
  cinemaShowings?: typeof embassyShowings;
  logger?: SafeLogger;
  rateLimiter?: BoundedRateLimiter;
  now?: () => number;
};

type CachedValue = { body: string; etag: string; expiresAt: number };

class ResponseCache {
  private readonly values = new Map<string, CachedValue>();

  constructor(
    private readonly maximumEntries = 500,
    private readonly now: () => number = Date.now,
  ) {}

  get(key: string): CachedValue | undefined {
    const value = this.values.get(key);
    if (!value) return undefined;
    if (value.expiresAt <= this.now()) {
      this.values.delete(key);
      return undefined;
    }
    return value;
  }

  set(key: string, body: string, ttlMilliseconds: number): CachedValue {
    if (this.values.size >= this.maximumEntries) {
      const oldest = this.values.keys().next().value as string | undefined;
      if (oldest) this.values.delete(oldest);
    }
    const value = {
      body,
      etag: `"${createHash("sha256").update(body).digest("base64url")}"`,
      expiresAt: this.now() + ttlMilliseconds,
    };
    this.values.set(key, value);
    return value;
  }
}

const quotas = {
  challenge: { ip: 30, device: 30, window: 60_000 },
  register: { ip: 5, device: 5, window: 3_600_000 },
  token: { ip: 20, device: 20, window: 60_000 },
  catalogSearch: { ip: 30, device: 10, window: 60_000 },
  catalogTitle: { ip: 120, device: 60, window: 60_000 },
  catalogReviews: { ip: 120, device: 60, window: 60_000 },
  catalogResolve: { ip: 120, device: 90, window: 60_000 },
  cinema: { ip: 40, device: 20, window: 60_000 },
} as const;

export function createApp(dependencies: AppDependencies): {
  fetch(request: Request, ipAddress?: string): Promise<Response>;
} {
  const { config, security } = dependencies;
  const tmdb =
    dependencies.tmdb ??
    (config.tmdbToken ? new TMDBClient(config.tmdbToken) : undefined);
  const cinema = dependencies.cinemaShowings ?? embassyShowings;
  const logger =
    dependencies.logger ??
    ((event) => process.stdout.write(`${JSON.stringify(event)}\n`));
  const limiter = dependencies.rateLimiter ?? new BoundedRateLimiter();
  const now = dependencies.now ?? Date.now;
  const cache = new ResponseCache(500, now);

  return {
    async fetch(request, ipAddress = "unknown") {
      const startedAt = now();
      const requestID = randomUUID();
      const url = new URL(request.url);
      let status = 500;
      let code = "internal_error";

      try {
        if (request.method === "OPTIONS") {
          status = 204;
          code = "preflight";
          return response(null, status, config);
        }

        if (request.method === "GET" && url.pathname === "/health") {
          status = 200;
          code = "ok";
          return response({ status: "ok" }, status, config);
        }

        if (
          request.method === "POST" &&
          url.pathname === "/v1/app-attest/challenge"
        ) {
          if (!config.controls.proxyEnabled) {
            status = 503;
            code = "disabled";
            return disabled(config);
          }
          enforceIPQuota(limiter, "challenge", ipAddress, quotas.challenge);
          const { value } = await readJSONBody(request, 1_024);
          const challengeRequest = validateChallengeRequest(value);
          if (challengeRequest.keyID) {
            enforceDeviceQuota(
              limiter,
              "challenge",
              hash(challengeRequest.keyID),
              quotas.challenge,
            );
          }
          const challenge = security.issueChallenge(
            challengeRequest.purpose,
            challengeRequest.keyID,
            request.headers.get("authorization"),
          );
          status = 201;
          code = "challenge_issued";
          return response(challenge, status, config);
        }

        if (
          request.method === "POST" &&
          url.pathname === "/v1/app-attest/register"
        ) {
          if (
            !config.controls.proxyEnabled ||
            !config.controls.registrationEnabled
          ) {
            status = 503;
            code = "disabled";
            return disabled(config);
          }
          enforceIPQuota(limiter, "register", ipAddress, quotas.register);
          const { value } = await readJSONBody(request, 40_000);
          const registration = validateRegistrationRequest(value);
          const token = await security.register(
            registration.challengeID,
            registration.keyID,
            registration.attestation,
          );
          status = 201;
          code = "device_registered";
          return response(token, status, config);
        }

        if (
          request.method === "POST" &&
          url.pathname === "/v1/app-attest/token"
        ) {
          if (!config.controls.proxyEnabled) {
            status = 503;
            code = "disabled";
            return disabled(config);
          }
          enforceIPQuota(limiter, "token", ipAddress, quotas.token);
          const keyID = request.headers.get(AppAttestHeaders.keyID)?.trim();
          if (keyID) {
            enforceDeviceQuota(limiter, "token", hash(keyID), quotas.token);
          }
          const { value, bytes } = await readJSONBody(request, 128);
          validateEmptyObject(value);
          const token = await security.refreshToken(request, bytes);
          status = 200;
          code = "token_issued";
          return response(token, status, config);
        }

        if (!config.controls.proxyEnabled) {
          status = 503;
          code = "disabled";
          return disabled(config);
        }

        if (request.method === "GET" && url.pathname === "/v1/catalog/search") {
          if (!config.controls.catalogEnabled || !tmdb) {
            status = 503;
            code = "disabled";
            return disabled(config);
          }
          const identity = await security.authorizeRequest(
            request,
            new Uint8Array(),
          );
          enforceProtectedQuota(
            limiter,
            "catalog-search",
            ipAddress,
            identity.deviceID,
            quotas.catalogSearch,
            identity.trust,
          );
          const input = validateCatalogSearch(url);
          const cacheKey = `search:${input.query}:${input.kind ?? "all"}:${input.page}:${input.region}`;
          const result = await cachedJSON(
            cache,
            cacheKey,
            300_000,
            request,
            async () => ({
              results: await tmdb.search(
                input.query,
                input.kind,
                input.page,
                input.region,
              ),
            }),
            config,
            "catalog-search",
          );
          status = result.status;
          code = result.status === 304 ? "not_modified" : "ok";
          return result;
        }

        const catalogReviewsMatch = url.pathname.match(
          /^\/v1\/catalog\/(movie|series)\/(\d+)\/reviews$/,
        );
        if (request.method === "GET" && catalogReviewsMatch) {
          if (!config.controls.catalogEnabled || !tmdb) {
            status = 503;
            code = "disabled";
            return disabled(config);
          }
          const identity = await security.authorizeRequest(
            request,
            new Uint8Array(),
          );
          enforceProtectedQuota(
            limiter,
            "catalog-reviews",
            ipAddress,
            identity.deviceID,
            quotas.catalogReviews,
            identity.trust,
          );
          const input = validateCatalogReviews(catalogReviewsMatch, url);
          const cacheKey = `reviews:${input.kind}:${input.id}:${input.page}`;
          const result = await cachedJSON(
            cache,
            cacheKey,
            300_000,
            request,
            () => tmdb.reviews(input.kind, input.id, input.page),
            config,
            "catalog-reviews",
          );
          status = result.status;
          code = result.status === 304 ? "not_modified" : "ok";
          return result;
        }

        const catalogMatch = url.pathname.match(
          /^\/v1\/catalog\/(movie|series)\/(\d+)$/,
        );
        if (request.method === "GET" && catalogMatch) {
          if (!config.controls.catalogEnabled || !tmdb) {
            status = 503;
            code = "disabled";
            return disabled(config);
          }
          const identity = await security.authorizeRequest(
            request,
            new Uint8Array(),
          );
          enforceProtectedQuota(
            limiter,
            "catalog-title",
            ipAddress,
            identity.deviceID,
            quotas.catalogTitle,
            identity.trust,
          );
          const input = validateCatalogTitle(catalogMatch, url);
          const cacheKey = `title:${input.kind}:${input.id}:${input.region}`;
          const result = await cachedJSON(
            cache,
            cacheKey,
            3_600_000,
            request,
            () => tmdb.title(input.kind, input.id, input.region),
            config,
            "catalog-title",
          );
          status = result.status;
          code = result.status === 304 ? "not_modified" : "ok";
          return result;
        }

        const externalCatalogMatch = url.pathname.match(
          /^\/v1\/catalog\/resolve\/(tvdb)\/(\d+)$/,
        );
        if (request.method === "GET" && externalCatalogMatch) {
          if (!config.controls.catalogEnabled || !tmdb) {
            status = 503;
            code = "disabled";
            return disabled(config);
          }
          const identity = await security.authorizeRequest(
            request,
            new Uint8Array(),
          );
          enforceProtectedQuota(
            limiter,
            "catalog-resolve",
            ipAddress,
            identity.deviceID,
            quotas.catalogResolve,
            identity.trust,
          );
          const input = validateCatalogExternalID(externalCatalogMatch, url);
          const cacheKey = `resolve:${input.source}:${input.id}:${input.kind}:${input.region}`;
          const result = await cachedOptionalJSON(
            cache,
            cacheKey,
            604_800_000,
            request,
            () =>
              tmdb.resolveExternalID(
                input.source,
                input.id,
                input.kind,
                input.region,
              ),
            config,
            "catalog-resolve",
          );
          status = result.status;
          code =
            result.status === 304
              ? "not_modified"
              : result.status === 404
                ? "not_found"
                : "ok";
          return result;
        }

        if (
          request.method === "GET" &&
          url.pathname === "/v1/cinemas/showings"
        ) {
          if (!config.controls.cinemaEnabled) {
            status = 503;
            code = "disabled";
            return disabled(config);
          }
          const identity = await security.authorizeRequest(
            request,
            new Uint8Array(),
          );
          enforceProtectedQuota(
            limiter,
            "cinema",
            ipAddress,
            identity.deviceID,
            quotas.cinema,
            identity.trust,
          );
          const input = validateCinemaShowings(url, new Date(now()));
          const cacheKey = `cinema:${input.day}`;
          const result = await cachedJSON(
            cache,
            cacheKey,
            120_000,
            request,
            async () => ({
              showings: await cinema(input.day),
            }),
            config,
            "cinema",
          );
          status = result.status;
          code = result.status === 304 ? "not_modified" : "ok";
          return result;
        }

        status = 404;
        code = "not_found";
        return response({ error: "Not found" }, status, config);
      } catch (error) {
        if (error instanceof RateLimitError) {
          status = 429;
          code = "rate_limited";
          return response({ error: "Too many requests" }, status, config, {
            "Retry-After": String(error.retryAfterSeconds),
          });
        }
        if (error instanceof ValidationError) {
          status = 400;
          code = error.code;
          return response({ error: "Invalid request" }, status, config);
        }
        if (error instanceof SecurityError) {
          status = 401;
          code = error.code;
          return response({ error: "Unauthorized" }, status, config);
        }
        status = 502;
        code = "upstream_unavailable";
        return response(
          { error: "Service temporarily unavailable" },
          status,
          config,
        );
      } finally {
        logger({
          event: "request",
          requestID,
          method: request.method,
          path: url.pathname,
          status,
          code,
          durationMilliseconds: Math.max(0, now() - startedAt),
        });
      }
    },
  };
}

async function cachedJSON(
  cache: ResponseCache,
  key: string,
  ttlMilliseconds: number,
  request: Request,
  load: () => Promise<unknown>,
  config: ServerConfig,
  tag: string,
): Promise<Response> {
  const cached = cache.get(key);
  if (cached && request.headers.get("if-none-match") === cached.etag) {
    return response(
      null,
      304,
      config,
      cacheHeaders(cached.etag, tag, ttlMilliseconds),
    );
  }
  if (cached)
    return rawJSON(
      cached.body,
      200,
      config,
      cacheHeaders(cached.etag, tag, ttlMilliseconds),
    );
  const body = JSON.stringify(await load());
  const value = cache.set(key, body, ttlMilliseconds);
  return rawJSON(
    body,
    200,
    config,
    cacheHeaders(value.etag, tag, ttlMilliseconds),
  );
}

async function cachedOptionalJSON(
  cache: ResponseCache,
  key: string,
  ttlMilliseconds: number,
  request: Request,
  load: () => Promise<unknown | null>,
  config: ServerConfig,
  tag: string,
): Promise<Response> {
  const cached = cache.get(key);
  if (cached && request.headers.get("if-none-match") === cached.etag) {
    return response(
      null,
      304,
      config,
      cacheHeaders(cached.etag, tag, ttlMilliseconds),
    );
  }
  if (cached)
    return rawJSON(
      cached.body,
      200,
      config,
      cacheHeaders(cached.etag, tag, ttlMilliseconds),
    );
  const loaded = await load();
  if (loaded === null) return response({ error: "Not found" }, 404, config);
  const body = JSON.stringify(loaded);
  const value = cache.set(key, body, ttlMilliseconds);
  return rawJSON(
    body,
    200,
    config,
    cacheHeaders(value.etag, tag, ttlMilliseconds),
  );
}

function cacheHeaders(
  etag: string,
  tag: string,
  ttlMilliseconds: number,
): Record<string, string> {
  const maximumAge = Math.max(1, Math.floor(ttlMilliseconds / 1_000));
  return {
    "Cache-Control": `private, max-age=${maximumAge}, stale-while-revalidate=${Math.min(maximumAge * 2, 600)}`,
    "CDN-Cache-Control": "no-store",
    ETag: etag,
    Vary: "Authorization, X-App-Attest-Key-ID",
    "X-OpenTV-Cache-Tag": tag,
  };
}

function enforceIPQuota(
  limiter: BoundedRateLimiter,
  endpoint: string,
  ipAddress: string,
  quota: { ip: number; window: number },
): void {
  enforce(limiter, `${endpoint}:ip:${hash(ipAddress)}`, quota.ip, quota.window);
}

function enforceDeviceQuota(
  limiter: BoundedRateLimiter,
  endpoint: string,
  deviceID: string,
  quota: { device: number; window: number },
): void {
  enforce(
    limiter,
    `${endpoint}:device:${deviceID}`,
    quota.device,
    quota.window,
  );
}

function enforceProtectedQuota(
  limiter: BoundedRateLimiter,
  endpoint: string,
  ipAddress: string,
  deviceID: string,
  quota: { ip: number; device: number; window: number },
  trust: "attested" | "development",
): void {
  const multiplier = trust === "development" ? 0.25 : 1;
  enforce(
    limiter,
    `${endpoint}:ip:${hash(ipAddress)}`,
    Math.max(1, Math.floor(quota.ip * multiplier)),
    quota.window,
  );
  enforce(
    limiter,
    `${endpoint}:device:${deviceID}`,
    Math.max(1, Math.floor(quota.device * multiplier)),
    quota.window,
  );
}

function enforce(
  limiter: BoundedRateLimiter,
  key: string,
  limit: number,
  window: number,
): void {
  const result = limiter.consume(key, limit, window);
  if (!result.allowed) throw new RateLimitError(result.retryAfterSeconds);
}

class RateLimitError extends Error {
  constructor(readonly retryAfterSeconds: number) {
    super("rate_limited");
  }
}

function disabled(config: ServerConfig): Response {
  return response({ error: "Service temporarily unavailable" }, 503, config);
}

function hash(value: string): string {
  return createHash("sha256").update(value).digest("base64url").slice(0, 20);
}

function response(
  body: unknown,
  status: number,
  config: ServerConfig,
  extraHeaders: Record<string, string> = {},
): Response {
  return rawJSON(
    body === null ? null : JSON.stringify(body),
    status,
    config,
    extraHeaders,
  );
}

function rawJSON(
  body: string | null,
  status: number,
  config: ServerConfig,
  extraHeaders: Record<string, string> = {},
): Response {
  const headers: Record<string, string> = {
    "Cache-Control": "no-store",
    "Content-Type": "application/json; charset=utf-8",
    "X-Content-Type-Options": "nosniff",
    ...extraHeaders,
  };
  if (config.corsAllowedOrigin) {
    headers["Access-Control-Allow-Origin"] = config.corsAllowedOrigin;
    headers["Access-Control-Allow-Headers"] = [
      "Content-Type",
      "Authorization",
      "X-App-Attest-Key-ID",
      "X-App-Attest-Challenge-ID",
      "X-App-Attest-Assertion",
    ].join(", ");
    headers["Access-Control-Allow-Methods"] = "GET,POST,OPTIONS";
    headers.Vary = headers.Vary ? `${headers.Vary}, Origin` : "Origin";
  }
  return new Response(body, { status, headers });
}
