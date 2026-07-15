# Security policy

## Supported versions

Only the latest beta and current default branch receive security fixes.

## Reporting

Do not open a public issue for a vulnerability or exposed credential. Use GitHub Security Advisories for this repository and include impact, reproduction steps, affected commit, and suggested mitigation. If a credential may be exposed, revoke it before investigating.

## Hard boundaries

- No TMDB, signing, DeviceCheck, CloudKit, cinema-feed, management, or other operator credential belongs in the app bundle or repository.
- OpenRouter keys are created by user OAuth PKCE, stored in the iOS Keychain, and used only for direct calls to OpenRouter.
- Vincent's production proxy accepts the official Team ID + bundle ID only. Forks must operate a separate service.
- Production proxy access requires a verified App Attest key, short-lived token, fresh one-time challenge, payload-bound assertion, and strictly increasing counter.
- Development bypass is allowed only when `APP_ATTEST_MODE=development`, requires an explicit untracked token, receives lower quotas, and is forbidden by production configuration validation.
- CORS is browser policy, never authentication.
- Logs must not contain IPs, search terms, request bodies, provider credentials, Keychain values, assertions, tokens, receipts, share URLs, notes, or raw watch events.
- CloudKit shares remain invitation-only and separate from personal SwiftData.

## Operator response

Use the kill switches and rotation runbook in [provider operations](docs/PROVIDER_OPERATIONS.md). `PROXY_ENABLED=false` is the global stop; catalog, cinema, and new registrations can be disabled independently without rebuilding.
