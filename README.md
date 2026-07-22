# OpenTV Tracker

An open-source, privacy-minded iPhone app for tracking TV shows and movies — solo or together.

Website: [opentvtracker.dev](https://opentvtracker.dev)

## Product

- Track episodes, movies, ratings, notes, rewatches, and a unified watchlist.
- Discover titles on selected streaming services with transparent on-device recommendations.
- Optionally rerank the same bounded candidates using a user-controlled OpenRouter key.
- Share a watchlist and progress through invitation-only CloudKit records.
- View Malta cinema listings and open official booking pages.
- Import and export a portable, versioned library.

Read the [data ownership promise](docs/DATA_OWNERSHIP.md), [product vision](docs/VISION.md), [architecture](docs/ARCHITECTURE.md), [threat model](docs/THREAT_MODEL.md), and [roadmap](docs/ROADMAP.md).

## Trust model

OpenTV works without an account or hosted service. Personal tracking and deterministic recommendations stay on the iPhone. TVmaze and official cinema pages provide public-source fallbacks.

The official binary may use Vincent's hosted TMDB/cinema proxy. That service accepts only production App Attest keys for `C76R5DRH64.dev.opentvtracker.app`; every protected request carries a fresh challenge and a payload-bound assertion. Unsupported devices fall back gracefully and do not receive an anonymous hosted-service bypass.

Forks and self-built apps cannot use Vincent's hosted proxy. Configure and operate your own proxy, Apple App ID, provider key, state storage, OAuth callback, quotas, and edge controls. See [self-hosting](docs/SELF_HOSTING.md) and [provider operations](docs/PROVIDER_OPERATIONS.md).

AI reranking never uses an operator OpenRouter key. The user authorizes OpenRouter with OAuth PKCE, the resulting user-controlled API key is stored in the iOS Keychain, and requests go directly from the iPhone to OpenRouter. AI stays off by default and any failure returns the deterministic ranking.

## Current implementation

- Swift 6, SwiftUI, and iOS 26+
- Local-only SwiftData with versioned import/export
- Invitation-only CloudKit custom zones and durable sync outboxes
- Secure nearby partner pairing over peer-to-peer networking, with an ephemeral TLS code and no invitation link to send
- TVmaze public catalog fallback and official Malta cinema sources
- App Attest-protected Bun proxy for TMDB/JustWatch metadata and Embassy showtimes
- User-funded OpenRouter OAuth PKCE with Keychain storage and direct reranking
- Docker packaging and GitHub Actions for iOS, server, and secret scanning

## Development

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open OpenTVTracker.xcodeproj
```

The keyless build works with public TV sources. For a local proxy, copy `Config/Secrets.example.xcconfig` to the ignored `Config/Secrets.xcconfig`, set your proxy URL, and use the development-only App Attest bypass described in [self-hosting](docs/SELF_HOSTING.md). Never ship that bypass token.

OpenRouter OAuth requires an HTTPS callback domain associated with the app. Official defaults point to `opentvtracker.dev`; forks must change `OPENROUTER_OAUTH_CALLBACK_URL`, `OPENROUTER_ASSOCIATED_DOMAIN`, and `OPENROUTER_SITE_URL` in their own build configuration.

To enable partner sharing on a physical device, configure your own CloudKit container and provisioning profile. Local tracking does not require iCloud. The exact record types and deployment steps are documented in the [CloudKit schema guide](docs/CLOUDKIT_SCHEMA.md).

See [PRIVACY.md](PRIVACY.md), [SECURITY.md](SECURITY.md), [CONTRIBUTING.md](CONTRIBUTING.md), the [public release checklist](docs/PUBLIC_RELEASE_CHECKLIST.md), and the [TestFlight release runbook](docs/TESTFLIGHT_RELEASES.md).

## License

MIT. See [LICENSE](LICENSE).
