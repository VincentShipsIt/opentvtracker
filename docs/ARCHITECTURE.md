# Architecture

## Current architecture

```text
SwiftUI features
    ↓
@MainActor AppModel
    ↓
LibraryPersisting
    ├── SwiftDataLibraryStore (versioned, local-only)
    ├── FileLibraryStore (legacy migration/fallback)
    └── MemoryLibraryStore (previews/tests)
```

Catalog, cinema, recommendation, persistence, and partner-sharing protocols isolate SwiftUI from DTOs, provider failures, CloudKit records, and credentials.

## Identity

- `MediaTitle.id` is a stable app identity, independent from mutable titles.
- Catalog lookups always carry both `MediaKind` and the numeric catalog identifier because movie and TV namespaces can overlap.
- Future local records, spaces, members, events, and CloudKit records receive separate stable identifiers.

## Personal data

The personal library is the immediate UI source of truth and works offline. Future remote changes are reconciled into local storage; UI never queries a sync provider directly.

SwiftData is explicitly local-only and never mirrors the records managed by the CloudKit collaboration engine.

## Partner sharing

Partner data stays separate from the personal library. Separate private and shared `CKSyncEngine` workers reconcile persisted local caches and durable outboxes through CloudKit.

One custom CloudKit zone represents one private partner space:

```text
PartnerSpace_<stable ID>
├── zone-wide CKShare (invitation-only)
├── Space
├── Member
├── SharedTitle
├── WatchEvent
└── ProgressCorrection
```

Progress is event-based rather than one mutable episode counter. Concurrent watch events converge by set union. Moving progress backward requires an explicit correction, so ordinary sync never silently erases viewing history.

CloudKit is opt-in. Local tracking never requires an Apple account. Account changes, revocation, and leaving purge retained shared state.

## Catalog and community data

```text
App → operator catalog proxy → TMDB
```

The shipped binary contains no TMDB, cinema-feed, or AI provider secret. Server DTOs are mapped into domain values and the app falls back to its local catalog when the endpoint is absent.

- TMDB provides catalog metadata and source reviews.
- TMDB's JustWatch-backed endpoints provide regional availability with visible attribution.
- IMDb remains outbound-link only until a licensed data path exists.

## Recommendations

Deterministic, explainable recommendations ship first. An optional AI service may rerank catalog candidates later, but it must:

- stay provider-neutral;
- use an operator-controlled server boundary;
- minimize consented history before sending it;
- exclude private notes and raw shared activity by default;
- return grounded catalog identifiers and explanations;
- fall back to deterministic ranking on failure.

## Availability and UI

- iOS 18 is the deployment floor.
- iOS 26 uses native `glassEffect` and glass button styles.
- iOS 18–25 use material and bordered-control fallbacks.
- Standard SwiftUI bars and controls provide most glass behavior; custom glass is reserved for meaningful grouped surfaces.
