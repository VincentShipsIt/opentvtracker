# TestFlight releases

Publishing a GitHub release from a `vX.Y.Z` tag archives the tagged commit and uploads it directly to App Store Connect. The tag must point to a commit on `main`. The workflow does not commit signing material or retain the signed IPA as a GitHub artifact.

GitHub release tags identify source releases; they do not set the App Store version. `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project's Release configuration are the source of truth for the TestFlight version and build. Increment those values intentionally before publishing or dispatching an upload.

## One-time setup

Create a GitHub environment named `testflight`. Allow deployments only from `v*` tags and the `main` branch (for manual retries), then add any desired required reviewers.

Use the same non-sensitive repository variables as ShipCode, MeterBar, and MacSweep:

- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`

Store the shared App Store Connect key and iOS-specific signing certificate as environment secrets:

- `APPLE_API_PRIVATE_KEY_P8_BASE64`: the same base64-encoded App Store Connect API key used by the other release workflows.
- `APPLE_DISTRIBUTION_P12_BASE64`: base64-encoded Apple Distribution `.p12` certificate and private key.
- `APPLE_DISTRIBUTION_P12_PASSWORD`: password used when exporting the Apple Distribution `.p12`.

Do not reuse `DEVELOPER_ID_P12_BASE64` or `DEVELOPER_ID_P12_PASSWORD`: those contain the macOS Developer ID identity used outside the App Store and cannot sign an iOS TestFlight build.

Use a team App Store Connect API key that can upload builds and access Certificates, Identifiers & Profiles. The App ID and widget extension must already exist for `APPLE_TEAM_ID`. The workflow matches the stored distribution certificate to the Developer account, reuses or creates App Store provisioning profiles for both bundle IDs, and signs the archive manually. It never creates or revokes a signing certificate.

Encode binary and key files without line wrapping:

```sh
base64 -i Distribution.p12 | tr -d '\n'
base64 -i AuthKey_KEYID.p8 | tr -d '\n'
```

## Release

1. Confirm the release commit has green iOS, server, and secret-scan checks on `main`.
2. Create and publish a GitHub release from a new `vX.Y.Z` tag on that commit.
3. Approve the `testflight` environment if it has a reviewer gate.
4. Watch the **TestFlight** workflow. A successful upload enters Apple's normal build-processing queue before it appears in TestFlight.

The workflow reads `CFBundleShortVersionString` and `CFBundleVersion` from the Xcode project's Release configuration. For a controlled retry, dispatch the workflow manually with a commit, branch, or tag on `main`; use the optional version or build overrides only when App Store Connect requires a corrected identifier.

If profile preparation fails, verify the API key's team scope and Certificates, Identifiers & Profiles access, the distribution certificate, and both bundle IDs (`dev.opentvtracker.app` and `dev.opentvtracker.app.widgets`). Rotate any credential immediately if its value is exposed in logs or outside the protected GitHub environment.

## Public release checklist

Operational gates for a public or TestFlight source release. The former standalone checklist now lives here.

### Already in place

- [x] Public GitHub repository.
- [x] MIT license and [dependency inventory](THIRD_PARTY_LICENSES.md), including pinned `node-app-attest` and transitive cryptography packages.
- [x] `.gitignore`, Docker context, GitHub secret scanning / push protection, and private vulnerability reporting. Dependabot is not used.
- [x] Official App ID `C76R5DRH64.dev.opentvtracker.app` with App Attest, Associated Domains, production entitlement, widget bundle `dev.opentvtracker.app.widgets`, and HTTPS OpenRouter callback association.
- [x] Official proxy at `https://api.opentvtracker.dev` on EC2 + Caddy + SSM, with PostgreSQL (`DATABASE_URL`) as the App Attest device store.
- [x] Server has no OpenRouter key or reranking route.

### Still required before a given release

- [ ] Rotate and scan for API keys, App Attest/DeviceCheck material, certificates, profiles, private keys, credential exports, share URLs, OAuth artifacts, PKCE verifiers, private fixtures, and generated state files.
- [ ] Verify `https://opentvtracker.dev/.well-known/apple-app-site-association` serves JSON without a redirect and authorizes `C76R5DRH64.dev.opentvtracker.app` for `/opentv/openrouter/callback`.
- [ ] Verify a fork/self-built bundle is rejected by the official proxy and works only with its own proxy configuration.
- [ ] Back up PostgreSQL App Attest device rows; confirm production refuses missing Team ID, bundle ID, token secret, TMDB token, or `DATABASE_URL`, and rejects development attestations and any bypass token.
- [ ] Test registration, token renewal, payload binding, expired/one-time challenge rejection, replayed counter rejection, and kill switches on physical devices.
- [ ] Configure coarse edge per-IP limits in front of Caddy, keep origin per-IP/device limits, and confirm shared caches cannot bypass authentication.
- [ ] Confirm the dedicated least-privilege TMDB token, monitoring/alerts, rotation, and provider kill switch.
- [ ] Connect/revoke a user OpenRouter key, set a daily/monthly spend cap, and verify deterministic fallback.
- [ ] Validate `PrivacyInfo.xcprivacy`, App Store privacy answers, privacy/deletion language, and secret-free structured logs.
- [ ] Import the source-controlled [CloudKit schema](CLOUDKIT_SCHEMA.md), create a Development invitation to seed `cloudkit.share`, promote all sharing changes, and verify `PartnerSpace`, `PartnerSpaceState`, and `cloudkit.share` in Production.
- [ ] On two devices, test invite, accept, watched-together partner notification, denied-then-enabled notification permission, decline, revoke, leave, offline retry, relaunch persistence, and Apple ID switch.
- [ ] Test JSON/CSV export/import rollback (including diary and lists CSV), VoiceOver, Dynamic Type, contrast, reduced motion/transparency, and button shapes.
- [ ] Verify TMDB/JustWatch/TVmaze attribution and official cinema links (live Embassy showtimes; Eden/Citadel booking links).
- [ ] Require green iOS, server, and secret-scan CI on the release commit, then publish a `vX.Y.Z` GitHub release using the steps above.
