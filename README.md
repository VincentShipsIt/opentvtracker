# OpenTV Tracker

An open-source, privacy-minded iPhone app for tracking TV shows and movies — solo or together.

The repository is private while the first usable release is taking shape. The intended public license is MIT.

## Product

- See new episodes and continue what you are already watching.
- Keep a single watchlist across shows and movies.
- Browse rich poster and backdrop artwork, then watch official trailers in-app.
- Filter discovery to streaming services you already pay for.
- Share progress and a watchlist with a partner.
- Compare personal and shared viewing analytics, then share a generated recap card on X.
- Discover what to watch next with transparent recommendations.
- Check Malta cinema listings and jump to Eden, Embassy, or Citadel booking pages.
- Import or export a portable versioned library as JSON/CSV.
- See streaming availability and attributed community context without building another social network first.

Read [the product vision](docs/VISION.md), [architecture](docs/ARCHITECTURE.md), and [roadmap](docs/ROADMAP.md).

## Current implementation

- Swift 6 and SwiftUI
- iOS 18 minimum; native Liquid Glass on iOS 26 with material fallbacks
- Versioned local-only SwiftData storage with safe migration from the original JSON snapshot
- Invitation-only CloudKit custom zones, private/shared sync engines, durable outboxes, and account-change purging
- Keyless live TV discovery from TVmaze, including seasons and episodes
- A Bun operator proxy for TMDB/JustWatch movie and TV metadata, Malta cinema listings, and optional OpenAI reranking
- Live Embassy Cinemas showtimes from its official booking schedule, plus official Eden and Citadel links
- Deterministic on-device recommendations with couple-match explanations and feedback exclusions
- Air-date/release-aware Up Next tracking, ratings, notes, rewatches, explicit progress corrections, and immutable watch events
- Event-backed hours watched, title/episode totals, genre and service breakdowns, partner stats, and shareable recap cards

## Development

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open OpenTVTracker.xcodeproj
```

No credentials are committed. The app works without keys for TV shows and Embassy Malta showtimes. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` and set the operator catalog proxy URL to add TMDB movies, Malta streaming availability, reviews, trailers, and optional OpenAI reranking. Provider credentials stay on that server; they never enter the app bundle. See [`server/README.md`](server/README.md).

The app runs on iOS 18 and later, including iPhone 11 Pro. To enable partner sharing on a physical device, select your Apple Developer team, attach the `iCloud.dev.shipshit.opentvtracker` CloudKit container to the app identifier, and let Xcode create the provisioning profile. Local tracking does not require iCloud.

See [PRIVACY.md](PRIVACY.md), [CONTRIBUTING.md](CONTRIBUTING.md), and the [public release checklist](docs/PUBLIC_RELEASE_CHECKLIST.md).

## License

MIT. See [LICENSE](LICENSE).
