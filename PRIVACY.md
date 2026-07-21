# Privacy

OpenTV works without an account. Watch state, progress, ratings, notes, subscription choices, recommendation feedback, and imports stay in local SwiftData by default.

## Partner sharing

Partner sharing is optional and uses an invitation-only CloudKit share. Only the shared watchlist, shared activity, member identifiers, taste preferences, and watched/correction events enter that share. Personal notes, the rest of the personal library, provider credentials, OpenRouter credentials, and App Attest credentials do not.

The owner can revoke a share and a participant can leave. Sign-out and account switching purge retained shared cache, sync state, and outbox data before another account is used.

## Recommendations and OpenRouter

Deterministic recommendations run on-device and are the default. Optional AI reranking is off until the user connects an OpenRouter account and enables it.

OpenRouter OAuth uses PKCE. The user-controlled API key returned by OpenRouter is stored as a this-device-only Keychain item and sent only to `openrouter.ai` as a bearer credential. It is never sent to the OpenTV proxy, Vincent, CloudKit, analytics, or logs. A reranking request contains a maximum of 20 public candidates with catalog ID, title, genres, runtime, rating, providers, deterministic score/reason, mood, and optional runtime limit. It excludes notes, member names, private watch events, and raw viewing history. OpenRouter receives the request directly and applies its own privacy policy.

Disconnecting OpenRouter deletes the Keychain item from this iPhone. The user must revoke the key in OpenRouter to invalidate it remotely; the settings screen links to that control. A timeout, revoked key, quota failure, invalid response, or provider outage silently restores the deterministic order.

## Official catalog and cinema proxy

The official app may send catalog query text, media kind, page, region, catalog ID, and cinema date to the configured proxy. Each request also contains App Attest material: a public key identifier, one-time challenge identifier, short-lived service token, and cryptographic assertion. The proxy persists the verified public key, Apple receipt, environment, monotonic counter, and registration/last-seen timestamps to prevent replay. These records are security identifiers, not advertising identifiers, and are not used for cross-app tracking.

Production request logs contain only a random request ID, method, route path, status, coarse error code, and duration. They exclude IP addresses, query values, bodies, App Attest keys/assertions/tokens, OpenRouter credentials, and personal data. IP addresses are hashed transiently in memory only for quota enforcement.

Devices without App Attest support do not receive anonymous access to the official hosted proxy. The app falls back to TVmaze and official cinema sources.

## Optional Trakt sync

Trakt sync is off until the user connects an account with device authorization. The resulting access and refresh tokens are stored as this-device-only Keychain items and sent only to `api.trakt.tv`. Sync sends TMDB identifiers, movie or episode watch dates, integer ratings, and watchlist changes. It imports the same fields plus personal-list names and membership. It never sends private notes, partner activity or member identities, recommendation feedback, moods, subscription choices, or OpenRouter credentials.

Disconnecting removes the Trakt token from this iPhone and asks Trakt to revoke it when the network is available. Local tracking continues unchanged when disconnected or offline.

## Control and deletion

Library data can be exported as versioned JSON or CSV. Removing the app removes local data and Keychain credentials. Revoking or leaving a partner share removes CloudKit access and purges retained shared state. Proxy operators can remove an App Attest device record from their configured state store. OpenTV does not sell data, track users across apps, or include advertising SDKs.

Report security issues privately as described in [SECURITY.md](SECURITY.md).
