# Self-hosting

Public source access does not grant access to Vincent's hosted provider account. App Attest intentionally rejects any build whose Team ID + bundle ID differs from the official app.

This guide is for forks. The service contract is [server/README.md](../server/README.md). Official hosting is EC2 + Caddy + SSM at `api.opentvtracker.dev`; see [deploy/aws/README.md](../deploy/aws/README.md).

## 1. Apple configuration

Create your own explicit App ID, enable App Attest and Associated Domains, use your own bundle identifier, and set the correct development/production App Attest entitlement. Configure your own CloudKit container if partner sharing is required.

Choose an HTTPS OpenRouter callback URL on a domain associated with your app. Publish the required Apple association file for that domain, then override:

- `OPENROUTER_OAUTH_CALLBACK_URL`
- `OPENROUTER_ASSOCIATED_DOMAIN` (for example `applinks:example.com`)
- `OPENROUTER_SITE_URL`
- optionally `OPENROUTER_MODEL`

The domain must serve `/.well-known/apple-app-site-association` as JSON without a redirect and include the application identifier `<TEAM_ID>.<BUNDLE_ID>` for the OAuth callback path. Verify the production file and entitlement together before release; an HTTPS URL alone is insufficient for `ASWebAuthenticationSession.Callback.https`.

The official app uses `https://opentvtracker.dev/opentv/openrouter/callback` with the associated domain `applinks:opentvtracker.dev`.

OpenRouter redirects the browser to the exact HTTPS callback and SwiftUI's web authentication session matches its host/path. The app exchanges the code with S256 PKCE and stores the resulting user key in Keychain.

## 2. Provider and server configuration

Create a dedicated TMDB API Read Access Token used by this proxy only. Do not reuse a personal or management credential. Copy `server/.env.example`, generate a random token-signing secret, and set your Team ID, bundle ID, `DATABASE_URL`, and kill switches.

Set `DATABASE_URL` to a PostgreSQL database. Production and any multi-instance deployment must use `PostgresDeviceStore` through `DATABASE_URL` so assertion counters stay atomic across restarts and writers. That store is already implemented. The database holds App Attest device keys and counters only.

`APP_ATTEST_STATE_PATH` is a single-writer JSON fallback for development and test without Postgres. Do not share that file across writers, and do not use it as the official or multi-instance production store.

Production fails closed unless Team ID, bundle ID, token secret, TMDB read token, and `DATABASE_URL` are all set.

## 3. iOS configuration

Copy `Config/Secrets.example.xcconfig` to ignored `Config/Secrets.xcconfig` and set `CATALOG_PROXY_BASE_URL` to your HTTPS origin. Use the xcconfig slash escaping shown in the example. Production builds must leave `APP_ATTEST_DEVELOPMENT_TOKEN` empty.

Unsupported devices and unconfigured builds use TVmaze and official cinema fallbacks. Do not add a production anonymous bypass.

## 4. Local development

App Attest does not work in every simulator. Development mode is deliberately separate:

1. Set server `APP_ATTEST_MODE=development`.
2. Generate an untracked random `APP_ATTEST_DEVELOPMENT_BYPASS_TOKEN`.
3. Put the same value in ignored iOS `APP_ATTEST_DEVELOPMENT_TOKEN`.
4. Use only local/non-production provider credentials and remove the token before archive.

Production configuration rejects a development bypass token and accepts only production App Attest attestations.

## 5. Edge and persistence

Place a WAF/CDN or Caddy in front of the Bun origin for coarse per-IP limits on challenge, registration, catalog, and cinema paths. Restrict direct origin access, configure `CLIENT_IP_HEADER` only for a header the trusted edge overwrites, and otherwise leave it empty so the Bun service uses the peer address. Keep the Bun per-IP and per-device limits; edge CORS or rate limiting is defense in depth.

Do not configure a shared cache that serves protected routes before authentication. The origin sends `CDN-Cache-Control: no-store` and performs its bounded cache lookup after verifying App Attest.

Follow [provider operations](PROVIDER_OPERATIONS.md) before production traffic.
