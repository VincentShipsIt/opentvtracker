# Self-hosting

Public source access does not grant access to Vincent's hosted provider account. App Attest intentionally rejects any build whose Team ID + bundle ID differs from the official app.

## 1. Apple configuration

Create your own explicit App ID, enable App Attest and Associated Domains, use your own bundle identifier, and set the correct development/production App Attest entitlement. Configure your own CloudKit container if partner sharing is required.

Choose an HTTPS OpenRouter callback URL on a domain associated with your app. Publish the required Apple association file for that domain, then override:

- `OPENROUTER_OAUTH_CALLBACK_URL`
- `OPENROUTER_ASSOCIATED_DOMAIN` (for example `applinks:example.com`)
- `OPENROUTER_SITE_URL`
- optionally `OPENROUTER_MODEL`

OpenRouter redirects the browser to the exact HTTPS callback and SwiftUI's web authentication session matches its host/path. The app exchanges the code with S256 PKCE and stores the resulting user key in Keychain.

## 2. Provider and server configuration

Create a dedicated TMDB API Read Access Token used by this proxy only. Do not reuse a personal or management credential. Copy `server/.env.example`, generate a random token-signing secret, and set your Team ID, bundle ID, persistent state path, and kill switches.

The bundled state store performs atomic JSON replacement and is suitable for one Bun process on a persistent disk. For multiple instances, replace `DeviceStore` with a transactional shared store that atomically enforces `nextCounter > previousCounter`; do not share the JSON file across writers.

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

Place a WAF/CDN in front of Render for coarse per-IP limits on challenge, registration, catalog, and cinema paths. Preserve origin IP forwarding only through a trusted proxy configuration. Keep the Bun per-IP and per-device limits; edge CORS or rate limiting is defense in depth.

Do not configure a shared cache that serves protected routes before authentication. The origin sends `CDN-Cache-Control: no-store` and performs its bounded cache lookup after verifying App Attest.

Follow [provider operations](PROVIDER_OPERATIONS.md) before production traffic.
