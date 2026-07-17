# Data ownership and continuity promise

OpenTV is built so a hosted service ending does not take a viewer's history with it. The personal library is local, portable, and useful without an OpenTV account.

## What works without OpenTV-hosted services

The following core features remain available when the official catalog and cinema proxy is unconfigured, disabled, over quota, or retired:

- opening and editing the local library;
- tracking titles, episodes, progress, ratings, notes, rewatches, and watch dates;
- importing and exporting library data;
- deterministic on-device recommendations;
- TVmaze-backed TV search and metadata where the public provider is available; and
- direct links to official cinema sources.

Optional partner sharing depends on the viewer's iCloud account and Apple's CloudKit service. Optional AI reranking depends on the viewer's own OpenRouter account and spend cap. Neither is required for local tracking.

## Export guarantee

OpenTV provides a complete, versioned JSON export of the current local library snapshot without an account, subscription, or support request. It includes the locally retained title and tracking data, preferences needed to restore the library, and the locally retained Together-space snapshot. The same JSON format can be imported into OpenTV.

OpenTV also provides two narrower, human-readable CSV exports:

| Format | Purpose | Contents |
| --- | --- | --- |
| Versioned JSON | Restorable backup | Current local library snapshot and supported settings |
| Titles CSV | Inspection and interoperability | Titles, year, media kind, state, watchlist membership, progress, rating, notes, rewatches, and last-watched date |
| Watch events CSV | Event-level inspection | Shared watched, watched-together, correction, and rewatch events retained in the local snapshot |

Exports never include Keychain secrets, App Attest credentials, provider credentials, or an undisclosed server-side profile. A complete JSON export is a snapshot of data currently available to the app; it cannot recover CloudKit records that are no longer accessible or third-party data OpenTV never stored.

The importer accepts supported older archive schemas and rejects a newer unsupported schema instead of silently applying a partial restore. On a fresh install, the JSON restores the archived local snapshot. On an existing library, titles added after the backup remain, matching titles use the archived tracking values, and Together history merges by stable identity without deleting newer shared entries. Confirmed source-ID mappings used for safe re-imports are part of this portable snapshot; they contain catalog identifiers, not credentials or viewing data held only by a provider. The preview states these rules and identifies settings restored from the archive, including whether optional AI reranking will be enabled. If a future migration cannot preserve a field, the release must document that limitation before changing the export format.

## Backup health

OpenTV records the date of a successful complete JSON export on the device. Settings and the data-transfer screen show whether no backup exists, the backup is current, or 30 days have elapsed and a fresh copy is due. Preparing an export or exporting a narrower CSV does not mark the restorable backup current.

This reminder is local. It does not upload the backup, inspect where the file was saved, schedule a notification, or report backup activity.

## Services, costs, and fallbacks

| Boundary | Who controls or funds it | If it is unavailable |
| --- | --- | --- |
| Local SwiftData and import/export | The viewer's device | Core tracking requires available device storage; no OpenTV server is involved |
| Official TMDB/cinema proxy | Maintainer-funded during the beta, within provider quotas and operating budgets | The app falls back to TVmaze and official cinema sources; richer TMDB artwork, discovery, and availability may be reduced |
| TVmaze and official cinema pages | Independent public providers under their own terms | Existing local data and tracking continue; affected lookup or listing data may be temporarily unavailable |
| Private CloudKit sharing | The viewer's iCloud account and Apple's service | Personal local data continues; invitations and partner synchronization wait for CloudKit |
| OpenRouter reranking | The viewer's optional, capped OpenRouter key | Deterministic on-device ranking is restored automatically |

The official proxy is a convenience for the official signed app, not a condition of data access. It uses App Attest, quotas, bounded caches, and kill switches to control provider spend. Public forks cannot consume the maintainer's provider credentials and must configure their own Apple identity, proxy, provider keys, budgets, and operational controls.

## Maintenance and funding

OpenTV is MIT licensed. The current beta has no ads, paid plan, or sale of viewing data, and monetization is not a v1 product goal. The maintainer currently funds and operates the optional official proxy within a bounded beta budget. That is not a promise to operate a free hosted service forever.

Material changes to funding, data handling, export compatibility, or hosted-service availability should be documented in the repository and release notes before they affect a release. Security support covers the latest beta and current default branch.

## Continuity plan

If active development slows or the official hosted proxy ends:

1. Existing installations keep their local library and core tracking behavior.
2. Viewers can create a complete JSON backup without contacting the maintainer.
3. Keyless public-provider fallbacks remain the default degraded path where those providers permit access.
4. The MIT-licensed repository, architecture, self-hosting guide, provider runbook, and schema documentation remain the handoff path for forks or successor maintainers.
5. A successor cannot access a viewer's local library, Keychain, or private CloudKit share merely by operating a fork.

No continuity plan can guarantee Apple, TVmaze, TMDB, JustWatch, cinema, or OpenRouter availability. The durable guarantee is narrower: OpenTV does not make access to the current local library or its complete export depend on OpenTV-hosted account infrastructure.
