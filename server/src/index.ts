import { embassyShowings } from "./cinema";
import { rerankWithOpenRouter, type RerankRequest } from "./openrouter";
import { TMDBClient, type MediaKind } from "./tmdb";

const port = Number(Bun.env.PORT ?? 8787);
const token = Bun.env.TMDB_READ_ACCESS_TOKEN ?? Bun.env.TMDB_API_READ_ACCESS_TOKEN;
const tmdb = token ? new TMDBClient(token) : null;
const openRouterKey = Bun.env.OPENROUTER_API_KEY;
const openRouterModel = Bun.env.OPENROUTER_MODEL;

Bun.serve({
  hostname: "0.0.0.0",
  port,
  async fetch(request) {
    if (request.method === "OPTIONS") return response(null, 204);

    const url = new URL(request.url);
    try {
      if (request.method === "GET" && url.pathname === "/health") {
        return response({
          status: "ok",
          tmdb: tmdb ? "configured" : "missing",
          aiReranking: openRouterKey && openRouterModel ? "configured" : "missing",
        });
      }

      if (request.method === "GET" && url.pathname === "/v1/catalog/search") {
        if (!tmdb) return configurationError();
        const query = url.searchParams.get("q")?.trim() ?? "";
        const kind = mediaKind(url.searchParams.get("kind"));
        const page = positiveInteger(url.searchParams.get("page"), 1);
        const region = regionCode(url.searchParams.get("region") ?? "MT");
        const results = await tmdb.search(query, kind, page, region);
        return response({ results }, 200, true);
      }

      const catalogMatch = url.pathname.match(/^\/v1\/catalog\/(movie|series)\/(\d+)$/);
      if (request.method === "GET" && catalogMatch) {
        if (!tmdb) return configurationError();
        const kind = catalogMatch[1] as MediaKind;
        const id = Number(catalogMatch[2]);
        const region = regionCode(url.searchParams.get("region") ?? "MT");
        const result = await tmdb.title(kind, id, region);
        return response(result, 200, true);
      }

      if (request.method === "GET" && url.pathname === "/v1/cinemas/showings") {
        const country = regionCode(url.searchParams.get("country") ?? "MT");
        if (country !== "MT") return response({ error: "Only Malta cinema listings are supported." }, 400);
        const day = isoDay(url.searchParams.get("date"));
        const showings = await embassyShowings(day);
        return response({ showings }, 200, true);
      }

      if (request.method === "POST" && url.pathname === "/v1/recommendations/rerank") {
        if (!openRouterKey) return response({ error: "OPENROUTER_API_KEY is not configured on this server." }, 503);
        if (!openRouterModel) return response({ error: "OPENROUTER_MODEL is not configured on this server." }, 503);
        const payload = await request.json() as RerankRequest;
        const catalogIDs = await rerankWithOpenRouter(openRouterKey, payload, {
          model: openRouterModel,
          siteURL: Bun.env.OPENROUTER_SITE_URL,
          appName: Bun.env.OPENROUTER_APP_NAME,
        });
        return response({ catalogIDs });
      }

      return response({ error: "Not found" }, 404);
    } catch (error) {
      const message = error instanceof Error ? error.message : "Unknown upstream error";
      process.stderr.write(`${JSON.stringify({ path: url.pathname, message })}\n`);
      return response({ error: "An upstream provider is temporarily unavailable." }, 502);
    }
  },
});

function response(body: unknown, status = 200, cacheable = false): Response {
  return new Response(body === null ? null : JSON.stringify(body), {
    status,
    headers: {
      "Access-Control-Allow-Headers": "Content-Type",
      "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
      "Access-Control-Allow-Origin": "*",
      "Cache-Control": status === 200 && cacheable ? "public, max-age=300" : "no-store",
      "Content-Type": "application/json; charset=utf-8",
    },
  });
}

function configurationError(): Response {
  return response({ error: "TMDB_READ_ACCESS_TOKEN is not configured on this server." }, 503);
}

function mediaKind(value: string | null): MediaKind | null {
  return value === "movie" || value === "series" ? value : null;
}

function positiveInteger(value: string | null, fallback: number): number {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}

function regionCode(value: string): string {
  return /^[A-Z]{2}$/.test(value.toUpperCase()) ? value.toUpperCase() : "MT";
}

function isoDay(value: string | null): string {
  if (value && /^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
  return new Date().toISOString().slice(0, 10);
}
