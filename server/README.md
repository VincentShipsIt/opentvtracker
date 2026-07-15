# OpenTV catalog proxy

The iOS app never contains provider secrets. This Bun service owns the TMDB boundary and the live Malta cinema feed.

## Run

```sh
cd server
bun install
cp .env.example .env
bun run dev
```

Configure the deployed HTTPS origin as `CATALOG_PROXY_BASE_URL` in the untracked
`Config/Secrets.xcconfig`. Keep both provider keys on the server.

## Environment

The server reads these runtime variables:

- `TMDB_READ_ACCESS_TOKEN` — TMDB API Read Access Token
- `OPENROUTER_API_KEY` — OpenRouter key used only for optional recommendation reranking
- `OPENROUTER_MODEL` — required OpenRouter model identifier when reranking is enabled
- `OPENROUTER_SITE_URL` — optional public service URL for OpenRouter attribution
- `OPENROUTER_APP_NAME` — optional attribution label; defaults to `OpenTV`
- `PORT` — supplied automatically by Render; defaults to `8787` locally

## Render

The repository-root `Dockerfile` runs only this Bun service. In the existing Render web service:

1. Keep the runtime set to **Docker** and the Dockerfile path set to `./Dockerfile`.
2. Add `TMDB_READ_ACCESS_TOKEN`, `OPENROUTER_API_KEY`, and `OPENROUTER_MODEL` under **Environment**.
3. Set the health-check path to `/health`.
4. Deploy `main` again.

For this service, set the app's untracked `Config/Secrets.xcconfig` to:

```xcconfig
CATALOG_PROXY_BASE_URL = https:/$()/opentvtracker.onrender.com
```

## Endpoints

- `GET /health`
- `GET /v1/catalog/search?q=&kind=&page=1&region=MT`
- `GET /v1/catalog/:movie|series/:tmdbID`
- `GET /v1/cinemas/showings?country=MT&date=YYYY-MM-DD`
- `POST /v1/recommendations/rerank` (OpenRouter structured-output reranking; returns 503 without its key or model)

The catalog uses TMDB metadata and its JustWatch-backed Malta flatrate provider availability. The cinema endpoint reads Embassy Cinemas' official booking schedule. Eden and Citadel remain outbound official links because they do not expose a stable machine-readable schedule.
