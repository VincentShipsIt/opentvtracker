# OpenTV Tracker production

The API runs in the `api-opentvtracker-dev` container on the shared shipshit.dev
EC2 host. Caddy owns public TLS for `api.opentvtracker.dev`; PostgreSQL stores
only App Attest device keys and monotonic counters.

Deployment artifacts use distinct `api-opentvtracker-dev-*` keys in the existing
encrypted, versioned shared API deployment bucket. The GitHub OIDC role trusts
the OpenTV `Production` environment and can deploy only through SSM to the shared
host.

Runtime secrets live under `/shipshit/production/opentvtracker/` in SSM Parameter
Store (`us-east-1`). The host deployment fails closed unless `DATABASE_URL`,
`APP_ATTEST_MODE`, `APP_ATTEST_TEAM_ID`, `APP_ATTEST_BUNDLE_ID`,
`APP_ATTEST_TOKEN_SECRET`, and `TMDB_READ_ACCESS_TOKEN` all exist.

The application workflow never edits the shared Caddyfile. Apply the tracked
fragment during host bootstrap, validate it, and reload Caddy before the first
application deployment.

Kill switches (`PROXY_ENABLED`, `CATALOG_ENABLED`, `CINEMA_ENABLED`,
`APP_ATTEST_REGISTRATION_ENABLED`) and rotation steps are in
[provider operations](../../docs/PROVIDER_OPERATIONS.md). There is no Render
hosting path.
