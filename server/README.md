# OpenTV catalog proxy

The iOS app never contains provider secrets. This Bun service owns the TMDB boundary and the live Malta cinema feed.

## Run

```sh
cd server
bun install
TMDB_READ_ACCESS_TOKEN=your_tmdb_read_token OPENAI_API_KEY=optional bun run dev
```

Configure the deployed HTTPS origin as `CATALOG_PROXY_BASE_URL` in the untracked
`Config/Secrets.xcconfig`. Keep both provider keys on the server.

## Endpoints

- `GET /health`
- `GET /v1/catalog/search?q=&kind=&page=1&region=MT`
- `GET /v1/catalog/:movie|series/:tmdbID`
- `GET /v1/cinemas/showings?country=MT&date=YYYY-MM-DD`
- `POST /v1/recommendations/rerank` (real OpenAI structured-output reranking; returns 503 without `OPENAI_API_KEY`)

The catalog uses TMDB metadata and its JustWatch-backed Malta flatrate provider availability. The cinema endpoint reads Embassy Cinemas' official booking schedule. Eden and Citadel remain outbound official links because they do not expose a stable machine-readable schedule.
