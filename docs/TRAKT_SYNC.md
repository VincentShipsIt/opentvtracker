# Trakt sync mapping

OpenTV's optional Trakt connection is an interoperability layer, not the source of truth. The app works without Trakt and all local edits remain available while offline.

## Authorization and storage

- Device OAuth uses the configured public Trakt application's client ID and secret.
- Trakt requires that application secret in its native device flow, so it identifies the public client but is extractable from the app binary; it is not treated as a user credential.
- The user enters the short code at Trakt's HTTPS activation page.
- Access and refresh tokens use a this-device-only Keychain item.
- The versioned OpenTV archive contains sync cursors and field baselines, never OAuth tokens.
- Disconnect removes the local token and attempts remote revocation without making local deletion depend on network access.

## Exact mapping

| OpenTV | Trakt | Direction | Conflict behavior |
| --- | --- | --- | --- |
| Movie TMDB ID | `movie.ids.tmdb` | two-way | Exact kind and ID match only |
| Series TMDB ID | `show.ids.tmdb` | two-way | Exact kind and ID match only |
| Movie watch date | history `watched_at` | two-way | History is additive; latest date wins |
| Episode season and number | episode history | two-way | Watched episode IDs are unioned |
| Title rating | movie/show rating, integer 1–10 | two-way | Changed side wins; simultaneous changes keep local |
| Personal watchlist | sync watchlist | two-way | Three-way merge from the last agreed baseline |
| Personal list name/privacy/membership | personal lists | Trakt to OpenTV | Preserved in portable sync metadata |

OpenTV records the IDs of successfully uploaded watch events because Trakt does not deduplicate `item + watched_at`. Rating and watchlist writes are idempotent. History uploads run last so a later failure cannot cause an already accepted play to be retried before its deduplication marker is saved.

Remote history removal never marks a local movie or episode unwatched and never moves episode progress backward. A remote watch can only add watched episodes, advance progress, or move a title to completed.

## Fields without a lossless counterpart

The following stay local and are never sent: private notes, fractional rating precision, provider subscriptions, moods, recommendation feedback, partner members/activity/reactions, local correction events, and OpenRouter data.

OpenTV does not currently map Trakt episode/season ratings, playback percentage, collections, favorites, hidden/dropped state, comments, social sharing, list notes, list item rank, or collaborative-list permissions. Personal-list names and TMDB membership are preserved so a future native list surface can adopt them without another import.
