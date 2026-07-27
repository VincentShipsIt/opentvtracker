# OpenTV catalog proxy

This Bun service protects a dedicated TMDB read token and live Embassy Cinemas fetches. It has no OpenRouter credential or reranking endpoint.

## Production contract

Protected catalog/cinema requests require an official App Attest key, a valid short-lived service token, a fresh request challenge, a payload-bound assertion, and a strictly increasing counter. Production fails to start without:

- `APP_ATTEST_MODE=production`
- `APP_ATTEST_TEAM_ID` — Apple Team/App ID prefix
- `APP_ATTEST_BUNDLE_ID` — official app bundle ID
- `APP_ATTEST_TOKEN_SECRET` — at least 32 random characters
- `DATABASE_URL` — PostgreSQL storage for App Attest device keys and counters
- `TMDB_READ_ACCESS_TOKEN` — dedicated read-only token for this service

`APP_ATTEST_STATE_PATH` remains available only for development and test environments without `DATABASE_URL`. Production uses PostgreSQL so assertion-counter updates remain atomic across restarts and multiple API instances. The database contains no accounts, watch history, taste profile, or recommendation data.

Optional TTLs default to 60 seconds for challenges and 10 minutes for tokens. Native iOS clients do not need CORS. If `CORS_ALLOWED_ORIGIN` is set, it permits one exact origin but does not change App Attest authorization.

By default, per-IP quotas use the direct peer address. Set `CLIENT_IP_HEADER` only when the origin accepts traffic exclusively from a trusted edge that overwrites that header (for example, `CF-Connecting-IP` behind Cloudflare). Never trust a client-supplied forwarding header on a directly reachable origin.

Request/token challenges, token refreshes, catalog reads, and cinema reads have stable per-device quotas in addition to per-IP quotas. Initial attestation registration is not yet a verified device and is therefore limited by IP until validation succeeds.

Rate/challenge/cache maps and verified-device records have explicit capacity limits. Rate-limit saturation rejects new identities rather than evicting live quota buckets. Catalog search is intentionally stricter than title lookup because one search can fan out to multiple TMDB detail requests.

## Run locally

```sh
cd server
bun install
cp .env.example .env
```

For a local simulator only, set `APP_ATTEST_MODE=development` and a random `APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN`, then put the matching value in ignored `Config/Secrets.xcconfig` as `APP_ATTEST_DEVELOPMENT_TOKEN`. Development bypass traffic receives one quarter of normal origin quotas. Never configure or ship the bypass in production.

Release builds ignore `APP_ATTEST_DEVELOPMENT_TOKEN` at compile time and accept only an HTTPS proxy origin. Debug builds additionally permit loopback HTTP for local development.

Start with `bun run dev`. The repository-root Dockerfile runs the same service.

## Endpoints

- `GET /health` — always generic `{ "status": "ok" }`
- `POST /v1/app-attest/challenge`
- `POST /v1/app-attest/register`
- `POST /v1/app-attest/token`
- `GET /v1/catalog/search?q=&kind=&page=1&region=MT`
- `GET /v1/catalog/:movie|series/:tmdbID?region=MT`
- `GET /v1/cinemas/showings?country=MT&date=YYYY-MM-DD`

`POST /v1/recommendations/rerank` does not exist. OpenRouter traffic goes directly from the iOS app using each user's Keychain credential.

## Production

The official service runs at `https://api.opentvtracker.dev` in the `api-opentvtracker-dev` container on the shared shipshit.dev EC2 host. PostgreSQL is the only shared state. Set `/health` as the health check, keep origin quotas enabled, and do not enable shared caching ahead of App Attest.

Set the official app's ignored configuration to the HTTPS service origin. Forks must deploy their own instance with their own Team ID, bundle ID, provider token, storage, quotas, and domain.

See [self-hosting](../docs/SELF_HOSTING.md), [threat model](../docs/THREAT_MODEL.md), and [provider operations](../docs/PROVIDER_OPERATIONS.md).
