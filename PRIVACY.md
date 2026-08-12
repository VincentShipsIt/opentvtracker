# Privacy

OpenTV works without an account. Watch state, progress, ratings, notes, the viewing diary, custom lists, subscription choices, recommendation feedback, content-language preference, and imports stay in local SwiftData by default.

This file is the privacy source of truth. Architecture and App Attest mechanics are in [ARCHITECTURE.md](docs/ARCHITECTURE.md). Export formats are in [DATA_OWNERSHIP.md](docs/DATA_OWNERSHIP.md).

## Partner sharing

Partner sharing is optional and uses an invitation-only CloudKit share. The share contains:

- the shared watchlist and shared activity;
- member identifiers and taste preferences;
- watched and correction events;
- episode reactions and notes attached to an exact shared watch event;
- conversation deletion tombstones;
- title metadata needed to render shared titles; and
- shared custom lists.

Personal notes on the rest of the library, the private diary, Trakt imported lists, provider credentials, OpenRouter credentials, and App Attest credentials do not enter that share.

The owner can revoke a share and a participant can leave. Sign-out and account switching purge retained shared cache, sync state, and outbox data before another account is used.

## Recommendations and OpenRouter

Deterministic recommendations run on-device and are the default. Optional AI reranking is off until the user connects an OpenRouter account and enables it.

OpenRouter OAuth uses PKCE. The user-controlled API key returned by OpenRouter is stored as a this-device-only Keychain item and sent only to `openrouter.ai` as a bearer credential. It is never sent to the OpenTV proxy, Vincent, CloudKit, analytics, or logs.

A reranking request contains:

- at most 20 public candidates (catalog ID, title, genres, runtime, rating, providers, deterministic score/reason);
- mood and optional runtime limit; and
- `viewingProfile`: aggregate counts (watched minutes, episode count, title count, top genres) plus up to 20 recent titles (title, genres, watched episode count, completion fraction, user rating, last-watched date).

It excludes notes, member names, private watch events, diary text, and list names. It does not send the raw watch-event log. OpenRouter receives the request directly and applies its own privacy policy.

Disconnecting OpenRouter deletes the Keychain item from this device. The user must revoke the key in OpenRouter to invalidate it remotely; the settings screen links to that control. A timeout, revoked key, quota failure, invalid response, or provider outage silently restores the deterministic order.

## Official catalog and cinema proxy

The official app may send catalog query text, media kind, page, region, catalog ID, content-language code (`language=`), cinema date, and TVDB identifiers (for confirmed import resolution) to the configured proxy. Each request also contains App Attest material: a public key identifier, one-time challenge identifier, short-lived service token, and cryptographic assertion. The proxy persists the verified public key, Apple receipt, environment, monotonic counter, and registration/last-seen timestamps in PostgreSQL (`DATABASE_URL`). These records are security identifiers, not advertising identifiers, and are not used for cross-app tracking.

Production request logs contain only a random request ID, method, route path, status, coarse error code, and duration. They exclude IP addresses, query values, bodies, App Attest keys/assertions/tokens, OpenRouter credentials, and personal data. IP addresses are hashed transiently in memory only for quota enforcement.

Devices without App Attest support do not receive anonymous access to the official hosted proxy. The app falls back to TVmaze and official cinema sources.

## Ask OpenTV speech

Ask OpenTV may use the microphone and Apple Speech Recognition only while the user holds the voice control. Spoken audio is used to produce a discovery query and is not stored by OpenTV. Recognition may use Apple's speech service. The resulting text is treated as catalog query text if the user submits it. Denying the microphone or speech permission leaves typed search available.

## Widgets and App Group

Home-screen widgets read a bounded Up Next / upcoming snapshot from the App Group `group.dev.opentvtracker.app`. That snapshot contains title names, short detail text, dates, and SF Symbol names. It does not contain notes, diary text, ratings, credentials, or CloudKit identifiers.

## Optional Trakt sync

Trakt sync is off until the user connects an account with device authorization. The resulting access and refresh tokens are stored as this-device-only Keychain items and sent only to `api.trakt.tv`. Sync sends TMDB identifiers, movie or episode watch dates, integer ratings, and watchlist changes. It imports the same fields plus personal-list names and membership into `TraktSyncState.importedLists`. It never sends private notes, diary entries, partner activity or member identities, recommendation feedback, moods, subscription choices, or OpenRouter credentials.

Disconnecting removes the Trakt token from this device and asks Trakt to revoke it when the network is available. Local tracking continues unchanged when disconnected or offline.

## Control and deletion

Library data can be exported as versioned JSON or as titles, watch events, diary, conversations, and lists CSV. Removing the app removes local data, the App Group widget snapshot, and Keychain credentials. Revoking or leaving a partner share removes CloudKit access and purges retained shared state. Proxy operators can remove an App Attest device record from PostgreSQL, or from the file store if a self-hosted instance is running without `DATABASE_URL`. OpenTV does not sell data, track users across apps, or include advertising SDKs.

Report security issues privately as described in [SECURITY.md](SECURITY.md).
