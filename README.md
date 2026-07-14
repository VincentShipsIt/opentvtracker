# OpenTV Tracker

An open-source, privacy-minded iPhone app for tracking TV shows and movies — solo or together.

The repository is private while the first usable release is taking shape. The intended public license is MIT.

## Product

- See new episodes and continue what you are already watching.
- Keep a single watchlist across shows and movies.
- Share progress and a watchlist with a partner.
- Discover what to watch next with transparent recommendations.
- See streaming availability and community context without building another social network first.

Read [the product vision](docs/VISION.md) and [roadmap](docs/ROADMAP.md).

## Technical direction

- Swift 6 and SwiftUI
- iOS 18 minimum; native Liquid Glass on iOS 26 with material fallbacks
- Offline-first local state
- CloudKit sharing for private partner spaces
- TMDB metadata and reviews, with JustWatch attribution for provider availability
- Provider-neutral AI recommendation service; API secrets stay server-side

## Development

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open OpenTVTracker.xcodeproj
```

No credentials are committed. Copy `Config/Secrets.example.xcconfig` to `Config/Secrets.xcconfig` when live metadata is introduced.

## License

MIT. See [LICENSE](LICENSE).
