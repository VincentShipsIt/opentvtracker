# Third-party software and data

The app target links ZIPFoundation 0.9.20 (MIT) to inspect TV Time data-export ZIP archives in memory. ZIPFoundation is Copyright © 2017-2025 Thomas Zoechling and contributors; its license is available at https://github.com/weichsel/ZIPFoundation/blob/0.9.20/LICENSE.

The remaining app dependencies are Apple system frameworks: SwiftUI, Observation, Foundation, SwiftData, CloudKit, UIKit, UniformTypeIdentifiers, and WebKit. No third-party binary SDK is embedded.

Development and CI use XcodeGen and SwiftLint under their respective upstream licenses. GitHub Actions uses `actions/checkout` and the Gitleaks action.

The optional Bun proxy depends on `node-app-attest` (MIT) for Apple App Attest verification. Its cryptography and CBOR dependency tree includes `asn1js` and `pkijs` (BSD-3-Clause) and `cbor` (MIT), plus their transitive dependencies recorded in `server/bun.lock`. Distribution of a self-hosted proxy must retain the dependency license notices shipped in `server/node_modules` or the corresponding package archives.

Catalog metadata, artwork, and reviews are sourced from TMDB; streaming provider data is JustWatch-backed through TMDB and is attributed in-app. IMDb is accessed only through user-initiated outbound search links. Malta cinema links point to Eden Cinemas, Embassy Cinemas, and Citadel Cinema official sites. Their content is not redistributed by this repository.

# Data sources

- TVmaze API data is licensed under CC BY-SA. Each TVmaze-backed detail screen links to its original TVmaze page.
- TMDB metadata is used only through the operator proxy and is attributed in the app.
- Regional streaming availability returned by TMDB is backed by JustWatch and visibly attributed.
- Embassy Cinemas showtimes link directly to the official booking page for each performance.
