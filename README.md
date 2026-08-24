# OpenTV Tracker

An open-source, privacy-minded iPhone and iPad app for tracking TV shows and movies — solo or with one invited partner. No account is required.

Website: [opentvtracker.dev](https://opentvtracker.dev)

The app's marketing version and build number are owned by [`project.yml`](project.yml). Published source versions are listed under [GitHub Releases](https://github.com/VincentShipsIt/opentvtracker/releases); release tags do not override the app build settings.

## Product

- Track episodes, movies, ratings, notes, rewatches, a viewing diary, and native custom lists. All of it stays on the device.
- Discover titles on selected streaming services with transparent on-device recommendations.
- Optionally rerank the same bounded candidates with a user-controlled OpenRouter key.
- Import from Trakt or a TV Time data-export ZIP. Keep an upcoming-episode calendar, local reminders, and home-screen widgets.
- Share a watchlist and progress through an invitation-only CloudKit space. Personal and Shared are an overlay (shake or toolbar), not a fourth tab.
- View live Embassy Cinemas showtimes and open official Embassy, Eden, and Citadel booking pages.
- Import and export a portable, versioned library.

The three tabs are **Today**, **Discover**, and **Library**. Tracking works without iCloud, Trakt, OpenRouter, or the official proxy.

## Documentation

| Topic | Document |
| --- | --- |
| Privacy | [PRIVACY.md](PRIVACY.md) |
| Data ownership and export | [docs/DATA_OWNERSHIP.md](docs/DATA_OWNERSHIP.md) |
| Architecture and App Attest | [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) |
| Threat model | [docs/THREAT_MODEL.md](docs/THREAT_MODEL.md) |
| Self-hosting a fork | [docs/SELF_HOSTING.md](docs/SELF_HOSTING.md) |
| Proxy contract | [server/README.md](server/README.md) |
| Official hosting | [deploy/aws/README.md](deploy/aws/README.md) |
| Provider operations | [docs/PROVIDER_OPERATIONS.md](docs/PROVIDER_OPERATIONS.md) |
| Vision | [docs/VISION.md](docs/VISION.md) |
| Roadmap | [docs/ROADMAP.md](docs/ROADMAP.md) |
| Security | [SECURITY.md](SECURITY.md) |
| Contributing | [CONTRIBUTING.md](CONTRIBUTING.md) |
| TestFlight and public release | [docs/TESTFLIGHT_RELEASES.md](docs/TESTFLIGHT_RELEASES.md) |
| Public release checklist | [docs/PUBLIC_RELEASE_CHECKLIST.md](docs/PUBLIC_RELEASE_CHECKLIST.md) |
| CloudKit schema | [docs/CLOUDKIT_SCHEMA.md](docs/CLOUDKIT_SCHEMA.md) |
| Trakt mapping | [docs/TRAKT_SYNC.md](docs/TRAKT_SYNC.md) |

## Development

The Xcode project is generated from `project.yml` using the repository-pinned XcodeGen 2.46.0 entrypoint. The app targets iPhone and iPad (`TARGETED_DEVICE_FAMILY: 1,2`) on iOS 26+.

```sh
.github/scripts/generate-ios-project.sh generate
.github/scripts/generate-ios-project.sh check
open OpenTVTracker.xcodeproj
```

`generate` verifies the pinned XcodeGen release checksum, the exact ZIPFoundation lock, and the app's entitlement contract before regenerating the project. `check` generates twice, requires byte-stable output, and rejects committed-project drift. The ZIPFoundation requirement is owned by [`project.yml`](project.yml), while the resolved revision is owned by the committed [`Package.resolved`](OpenTVTracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved). CI refuses package versions outside that lock.

Release-gate workflow/check pairs are owned by [`.github/scripts/required-checks.sh`](.github/scripts/required-checks.sh) and the corresponding workflow job names. [The TestFlight runbook](docs/TESTFLIGHT_RELEASES.md#exact-sha-verification-contract) explains the gate without redefining that machine-readable contract.

The keyless build works with public TV sources. For a local proxy, copy `Config/Secrets.example.xcconfig` to the ignored `Config/Secrets.xcconfig`, set your proxy URL, and use the development-only App Attest bypass described in [self-hosting](docs/SELF_HOSTING.md). Never ship that bypass token.

OpenRouter OAuth requires an HTTPS callback domain associated with the app. Official defaults point to `opentvtracker.dev`; forks must change `OPENROUTER_OAUTH_CALLBACK_URL`, `OPENROUTER_ASSOCIATED_DOMAIN`, and `OPENROUTER_SITE_URL` in their own build configuration.

To enable partner sharing on a physical device, configure your own CloudKit container and provisioning profile. Local tracking does not require iCloud. Record types and deployment steps are in the [CloudKit schema guide](docs/CLOUDKIT_SCHEMA.md).

The official signed app may use Vincent's hosted proxy at `https://api.opentvtracker.dev`. Forks cannot. Trust-model detail lives in [architecture](docs/ARCHITECTURE.md), [privacy](PRIVACY.md), and [self-hosting](docs/SELF_HOSTING.md).

## License

MIT. See [LICENSE](LICENSE).
