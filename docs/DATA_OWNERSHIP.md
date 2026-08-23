# Data ownership and continuity promise

OpenTV is built so a hosted service ending does not take a viewer's history with it. The personal library is local, portable, and useful without an OpenTV account. Privacy payloads and network boundaries live in [PRIVACY.md](../PRIVACY.md).

## What works without OpenTV-hosted services

The following core features remain available when the official catalog and cinema proxy is unconfigured, disabled, over quota, or retired:

- opening and editing the local library;
- tracking titles, episodes, progress, ratings, notes, rewatches, diary entries, custom lists, and watch dates;
- importing and exporting library data;
- deterministic on-device recommendations;
- TVmaze-backed TV search and metadata where the public provider is available; and
- direct links to official cinema sources.

Optional partner sharing depends on the viewer's iCloud account and Apple's CloudKit service. Optional AI reranking depends on the viewer's own OpenRouter account and spend cap. Optional Trakt sync depends on the viewer's Trakt account. None of those are required for local tracking.

## Export guarantee

OpenTV provides a complete, versioned JSON export of the current local library snapshot without an account, subscription, or support request. It includes the locally retained title and tracking data, diary, custom lists, preferences needed to restore the library, and the locally retained shared-space snapshot. The same JSON format can be imported into OpenTV.

OpenTV also provides narrower, human-readable CSV exports:

| Format | Purpose | Contents |
| --- | --- | --- |
| Versioned JSON | Restorable backup | Current local library snapshot and supported settings |
| Titles CSV | Inspection and interoperability | Titles, year, media kind, state, watchlist membership, progress, rating, notes, rewatches, and last-watched date |
| Watch events CSV | Event-level inspection | Shared watched, watched-together, correction, and rewatch events retained in the local snapshot |
| Diary CSV | Private diary inspection | Entry IDs, title IDs, scope, season/episode, watched date, rating, note, rewatch flag, and timestamps |
| Private conversations CSV | Shared-space inspection | Episode watch-event IDs, member IDs, bounded reaction asset IDs, private notes, and timestamps retained in the local snapshot |
| Lists CSV | Custom-list inspection | List IDs, names, positions, title membership, catalog IDs, year, and kind |

Exports never include Keychain secrets, App Attest credentials, provider credentials, or an undisclosed server-side profile. A complete JSON export is a snapshot of data currently available to the app; it cannot recover CloudKit records that are no longer accessible or third-party data OpenTV never stored.

The owner of a private shared space can delete its retained episode notes and reactions without deleting watch history. OpenTV syncs timestamped deletion tombstones to invited members so an older offline copy cannot silently restore deleted conversation data. Leaving or revoking a space continues to purge the device's retained CloudKit state.

Episode reactions are limited to five Unicode emoji and three GIFs bundled with OpenTV. Shared records contain only the bounded asset identifier; they never contain arbitrary media URLs, uploaded files, or third-party tracking requests. Optional local notifications are generated only for entries authored by another member of the accepted invitation-only space, and their text never includes the private note, reaction, title, or episode spoiler.

The importer accepts supported older archive schemas and rejects a newer unsupported schema instead of silently applying a partial restore. On a fresh install, the JSON restores the archived local snapshot. On an existing library, titles added after the backup remain, matching titles use the archived tracking values, and shared history merges by stable identity without deleting newer shared entries. The preview states these rules and identifies settings restored from the archive, including whether optional AI reranking will be enabled. If a future migration cannot preserve a field, the release must document that limitation before changing the export format.

Import safety limits are deliberately above normal personal-library exports while keeping hostile inputs bounded: JSON and standalone CSV files may be up to 25 MiB; TV Time ZIPs retain the 100 MiB compressed, 300 MiB expanded, and 75 MiB per-entry limits. An import may contain up to 250,000 logical CSV records, 2,000,000 CSV values, 128 CSV fields per record, 250,000 elements in any decoded JSON collection, and 1,000,000 decoded collection elements in aggregate. Text fields are capped at 1 MiB; TV Time's aggregate `lists-prod-lists.csv` representation may use up to 8 MiB for its single membership field. ZIPs may contain up to 1,024 total entries, and duplicate recognized TV Time paths are rejected case-insensitively. Imported auto-loaded artwork is retained only from the HTTPS image hosts used by the supported TMDB and TVmaze catalog boundaries, with redirect/tracking query parameters removed; Gravatar avatars retain only bounded size and rating options. Private tracking, diary, rating, note, watch-history, and list state is unaffected by that normalization.

## Backup health

OpenTV records the date of a successful complete JSON export on the device. Settings and the data-transfer screen show whether no backup exists, the backup is current, or 30 days have elapsed and a fresh copy is due. Preparing an export or exporting a narrower CSV does not mark the restorable backup current.

This reminder is local. It does not upload the backup, inspect where the file was saved, schedule a notification, or report backup activity.

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
