# Architecture

## Local application

```text
SwiftUI features
    ↓
@MainActor AppModel
    ├── local SwiftData / versioned import-export
    ├── private and shared CloudKit sync (optional)
    ├── direct user-authorized Trakt interoperability (optional)
    ├── deterministic recommendation engine
    └── service protocols
          ├── public TVmaze / official cinema fallbacks
          ├── App Attest-protected operator proxy
          └── direct user-funded OpenRouter reranking (optional)
```

The personal library is the immediate source of truth and works offline. SwiftData never mirrors CloudKit collaboration records. Catalog, cinema, recommendation, persistence, and sharing protocols keep SwiftUI independent from DTOs, provider failures, and credentials.

## Catalog identity and migration

TV Time imports resolve explicit legacy TVDB identifiers through the protected operator boundary, which maps a unique TVDB result to a TMDB title. Only confirmed mappings are cached. The client also stores confirmed automatic and manual source-ID mappings in the portable library snapshot, so a re-import can reuse them without network access.

Title fallback is deliberately staged: exact display, original, or localized aliases plus release year; then a controlled terminal `(YYYY)` or `- YYYY` suffix; then explicit anime relations. Ambiguous remakes never fall through to the first search result and catalog misses remain visible in the import preview for manual resolution.

Anime titles ending in `Season N` may map source season 1 to TMDB season N only when the candidate is categorized as Animation and uniquely identified. Parts, cours, specials, OVAs, ONAs, and movies are not collapsed into generic seasons; they require manual confirmation.

## Official proxy trust flow

```text
iPhone                           Bun proxy                         Apple / providers
  │ POST challenge (attestation)   │
  │◀──────────────── random, 60 s ─│
  │ attest Secure Enclave key ──────────────────────────────────▶ App Attest
  │ POST attestation               │ verify cert chain, nonce,
  │                                │ Team ID, bundle ID, key ID
  │◀──────────── 10 min token ─────│ persist public key + counter
  │
  │ POST challenge (request)       │ validate token + key
  │◀──────────────── random, 60 s ─│
  │ sign challenge + method + exact target + body hash
  │ GET catalog + assertion ──────▶│ consume challenge; verify signature/counter
  │                                │ quota device + IP; validate; cache
  │                                │─────────────────────────────▶ TMDB / cinema
  │◀──────────────── response ─────│
```

Tokens reduce unauthenticated challenge abuse but never replace assertions. Every protected request is bound to its exact method, percent-encoded path/query, body digest, and one-time challenge. The server updates the counter before provider access. Challenges, rate buckets, and response caches are bounded and expire; verified device keys and counters use an atomic file-backed state store on a persistent disk.

Production starts only with Team ID, bundle ID, token secret, and TMDB read token. Development/test mode is explicit and production rejects any configured bypass token.

The server cache is private and evaluated after authorization. `CDN-Cache-Control: no-store` prevents an ordinary shared cache from bypassing App Attest. An edge cache may be enabled only if App Attest and quota enforcement run before cache lookup.

## Unsupported devices and forks

The official service does not expose an anonymous fallback. Unsupported devices use TVmaze and direct official cinema pages. This is lower functionality without operator-funded abuse risk.

App Attest validates the App ID (`TeamID.BundleID`), so a public fork cannot authenticate to Vincent's service. Self-hosters configure their own App ID, persistent state path, TMDB key, proxy URL, associated OAuth domain, and edge controls.

## OpenRouter

OAuth PKCE runs in a SwiftUI web authentication session using an associated HTTPS callback. The exchanged user key is a this-device-only Keychain item. Direct chat-completions calls send at most 20 public candidates and validate that structured output contains every supplied ID exactly once. The operator server has no OpenRouter route, key, model, or spend exposure.

## Trakt

Optional Trakt interoperability uses device OAuth directly between the iPhone and `api.trakt.tv`. Access and refresh tokens are this-device-only Keychain items. The local library remains authoritative and usable offline; provider failures never replace it. Sync compares Trakt's last-activity timestamp before fetching, then applies additive history plus three-way rating and watchlist reconciliation. Remote history deletion never moves local progress backward, and a simultaneous rating conflict keeps the local value. Imported personal-list membership is retained in the versioned local archive even where OpenTV has no matching editable field. See [TRAKT_SYNC.md](TRAKT_SYNC.md).

## Partner sharing

One custom CloudKit zone represents one private partner space with a zone-wide `CKShare`, members, shared titles, append-only watch events, explicit progress corrections, and episode conversation entries. Notes and bounded reaction asset identifiers reference an exact watch event. Conversation deletes use timestamped tombstones so offline merges cannot resurrect older private content. Account changes, revocation, and leaving purge retained shared state.
