# Threat model

## Protected data

Personal viewing history, notes, ratings, partner membership, share URLs, CloudKit account identity, and server configuration are sensitive. Public catalog IDs, artwork URLs, and cinema venue URLs are not secrets.

## Trust boundaries

| Boundary | Data allowed across it | Controls |
| --- | --- | --- |
| Local SwiftData | Personal library and preferences | Local-only model container, versioned archive, export under user action |
| Invitation-only CloudKit share | Shared list, profiles, activity, watched/correction events | Custom zone, stable IDs, CKShare, persisted outbox, revocation/leave purge |
| OpenTV catalog/cinema service | Query, media kind, page, region/date | HTTPS endpoint, timeout, no bundled upstream credentials |
| Optional AI reranker | Catalog IDs, local scores, mood/runtime | Explicit opt-in, payload preview, short timeout, deterministic fallback |
| External links | Selected TMDB, IMDb, or cinema page | User gesture; external site's policy applies |

## Failure handling

- Offline changes enter a durable CloudKit outbox and retry idempotently.
- Ordinary watch events are append-only; backwards progress requires an explicit correction referencing the superseded event.
- Account sign-out/switch purges shared caches, state, and queued mutations.
- Revocation and leave remove the zone and retained local shared data.
- Logs and user-facing diagnostics contain categories and recovery text, not payloads or secrets.

## Residual risks

The Apple ID and device security model protect CloudKit access. A compromised unlocked device can read app-visible data. External catalog and cinema providers observe requests made to them. Community excerpts and provider availability may be incomplete or stale and are attributed to their source.
