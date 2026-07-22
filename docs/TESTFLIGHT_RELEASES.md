# TestFlight releases

Publishing a GitHub release from a `vX.Y.Z` tag archives the tagged commit and uploads it directly to App Store Connect. The tag must point to a commit on `main`. The workflow does not commit signing material or retain the signed IPA as a GitHub artifact.

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

Use a team App Store Connect API key that can upload builds and access Certificates, Identifiers & Profiles. The App ID and widget extension must already exist for `APPLE_TEAM_ID`, with automatic signing able to create or download their App Store provisioning profiles.

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

The workflow derives `CFBundleShortVersionString` from the tag and assigns a monotonically increasing CI build number. For a controlled retry, dispatch the workflow manually with the same tag and, only when necessary, a larger integer build-number override.

If automatic provisioning fails, verify the API key's team scope and Certificates, Identifiers & Profiles access, the distribution certificate, and both bundle IDs (`dev.opentvtracker.app` and `dev.opentvtracker.app.widgets`). Rotate any credential immediately if its value is exposed in logs or outside the protected GitHub environment.
