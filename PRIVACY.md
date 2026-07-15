# Privacy

OpenTV works without an account. By default, watch state, progress, ratings, notes, subscription choices, recommendation feedback, and imports stay on the iPhone in local SwiftData storage.

## Partner sharing

Partner sharing is optional and uses an invitation-only CloudKit share. Only the shared watchlist, shared activity, member identifiers, taste preferences, and immutable watched/correction events enter that share. Personal notes, the rest of the personal library, and subscription credentials do not.

The owner can revoke a share. A participant can leave it. Sign-out and account switching purge the retained shared cache, sync state, and outbox before another account is used.

## Recommendations

Deterministic recommendations run on-device. Optional AI reranking is off by default. When enabled, OpenTV sends only candidate TMDB IDs, deterministic scores, mood, and an optional runtime limit to the configured OpenTV service. Names, private notes, member names, and raw watch events are never included. Timeout or service failure falls back to the on-device result.

## Catalog and cinema services

Catalog searches and live cinema requests may reach the configured OpenTV service with the search text, page, media kind, date, and Malta region code. Provider credentials are never shipped in the app. Official cinema links open the selected venue website under that venue's privacy policy.

## Control and deletion

Library data can be exported as versioned JSON or CSV. Removing the app removes local data. Revoking or leaving a partner share removes CloudKit access and purges the app's retained shared cache. OpenTV does not sell data, track users across apps, or include advertising SDKs.

Security reports belong at the private contact in [SECURITY.md](SECURITY.md), not in a public issue.
