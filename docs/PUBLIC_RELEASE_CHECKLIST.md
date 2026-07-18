# Public release checklist

- [ ] Rotate and scan for API keys, App Attest/DeviceCheck material, certificates, profiles, private keys, credential exports, share URLs, OAuth artifacts, PKCE verifiers, private fixtures, and generated state files.
- [ ] Confirm `.gitignore`, Docker context, GitHub secret scanning/push protection, Dependabot, and private vulnerability reporting.
- [ ] Confirm MIT license and dependency inventory, including pinned `node-app-attest` and transitive cryptography packages.
- [ ] Provision the production App ID with App Attest, Associated Domains, production entitlement, official Team ID/bundle ID, and the HTTPS OAuth callback association file.
- [ ] Verify `https://opentvtracker.dev/.well-known/apple-app-site-association` serves JSON without a redirect and authorizes `C76R5DRH64.dev.opentvtracker.app` for `/opentv/openrouter/callback`.
- [ ] Verify a fork/self-built bundle is rejected by the official proxy and works only with its own proxy configuration.
- [ ] Mount and back up a persistent single-writer App Attest state path; exercise atomic persistence and counter recovery.
- [ ] Verify production refuses missing identity/token/provider configuration, development attestations, and any bypass token.
- [ ] Test registration, token renewal, payload binding, expired/one-time challenge rejection, replayed counter rejection, and kill switches on physical devices.
- [ ] Configure edge per-IP limits in front of Render, keep origin per-IP/device limits, and confirm shared caches cannot bypass authentication.
- [ ] Create a dedicated least-privilege TMDB token, enable monitoring/alerts, and rehearse rotation plus provider kill switch.
- [ ] Confirm the server has no OpenRouter key or reranking route. Connect/revoke a user OAuth key, set a daily/monthly spend cap, and verify deterministic fallback.
- [ ] Validate `PrivacyInfo.xcprivacy`, App Store privacy answers, privacy/deletion language, and secret-free structured logs.
- [ ] Import the source-controlled [CloudKit schema](CLOUDKIT_SCHEMA.md), create a Development invitation to seed `cloudkit.share`, promote all sharing changes, and verify `PartnerSpace`, `PartnerSpaceState`, and `cloudkit.share` in Production.
- [ ] On two devices, test invite, accept, watched-together partner notification, denied-then-enabled notification permission, decline, revoke, leave, offline retry, relaunch persistence, and Apple ID switch.
- [ ] Test JSON/CSV export/import rollback, VoiceOver, Dynamic Type, contrast, reduced motion/transparency, and button shapes.
- [ ] Verify TMDB/JustWatch/TVmaze attribution and official cinema links.
- [ ] Require green iOS, server, and secret-scan CI on the release commit; create the archive with release signing outside source control.
