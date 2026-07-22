# TestFlight releases

Publishing a GitHub release from a `vX.Y.Z` tag archives the tagged commit and uploads it directly to App Store Connect. The tag must point to a commit on `main`. The workflow does not commit signing material or retain the signed IPA as a GitHub artifact.

## One-time setup

Create a GitHub environment named `testflight`. Allow deployments only from `v*` tags and the `main` branch (for manual retries), then add any desired required reviewers. Store these environment secrets:

- `APPLE_DISTRIBUTION_CERTIFICATE_BASE64`: base64-encoded Apple Distribution `.p12` certificate and private key.
- `APPLE_DISTRIBUTION_CERTIFICATE_PASSWORD`: password used when exporting the `.p12`.
- `APP_STORE_CONNECT_API_KEY_BASE64`: base64-encoded App Store Connect `AuthKey_<KEY_ID>.p8` file.
- `APP_STORE_CONNECT_KEY_ID`: App Store Connect API key ID.
- `APP_STORE_CONNECT_ISSUER_ID`: App Store Connect issuer ID.

Use a team App Store Connect API key that can upload builds and access Certificates, Identifiers & Profiles. The App ID and widget extension must already exist for team `C76R5DRH64`, with automatic signing able to create or download their App Store provisioning profiles.

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
