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

The personal library is the immediate UI source of truth and works offline. Remote changes are reconciled into local storage; UI never queries a sync provider directly.

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

The shipped binary contains no TMDB or AI provider secret. Server DTOs are mapped into domain values. When the operator endpoint is absent or unavailable, the app uses TVmaze's real public API for TV discovery and reads Embassy Cinemas' official schedule directly; production never falls back to bundled catalog records.

- TMDB provides catalog metadata and source reviews.
- TMDB's JustWatch-backed endpoints provide regional availability with visible attribution.
- TVmaze provides keyless TV metadata, streaming schedules, seasons, and episodes under CC BY-SA with in-app source links.
- Embassy Cinemas provides live Malta showtimes; Eden and Citadel are official outbound listings until stable feeds exist.
- IMDb remains outbound-link only until a licensed data path exists.

## Recommendations

Deterministic, explainable recommendations are always available. When the user opts in, the operator service reranks the same bounded candidate set with OpenAI structured output. The AI boundary:

- stay provider-neutral;
- use an operator-controlled server boundary;
- minimize consented history before sending it;
- exclude private notes and raw shared activity by default;
- returns every supplied catalog identifier exactly once and cannot introduce titles;
- fall back to deterministic ranking on failure.

## Availability and UI

- iOS 18 is the deployment floor.
- iOS 26 uses native `glassEffect` and glass button styles.
- iOS 18–25 use material and bordered-control fallbacks.
- Standard SwiftUI bars and controls provide most glass behavior; custom glass is reserved for meaningful grouped surfaces.
