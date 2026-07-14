# Architecture

## Current foundation

The first pull request is a representative-data vertical slice, not a production schema commitment.

```text
SwiftUI features
    ↓
@MainActor AppModel
    ↓
LibraryPersisting
    ├── FileLibraryStore (small local JSON snapshot)
    └── MemoryLibraryStore (previews and tests)
```

The local file makes tracking interactions survive relaunches while the domain is still moving. Milestone 1 replaces it with a versioned SwiftData implementation behind the same boundary.

Catalog, recommendation, and partner-sharing protocols exist as seams only. Views do not know about TMDB DTOs, AI providers, CloudKit records, or credentials.

## Identity

- `MediaTitle.id` is a stable app identity, independent from mutable titles.
- Catalog lookups always carry both `MediaKind` and the numeric catalog identifier because movie and TV namespaces can overlap.
- Future local records, spaces, members, events, and CloudKit records receive separate stable identifiers.

## Personal data

The personal library is the immediate UI source of truth and works offline. Future remote changes are reconciled into local storage; UI never queries a sync provider directly.

When SwiftData lands, it is explicitly local-only. It must not automatically mirror the same records managed by the manual CloudKit collaboration engine.

## Partner sharing

Partner data stays separate from the personal library. Milestone 2 adds a durable local shared cache and outbox, then reconciles them through CloudKit.

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

Do not enable CloudKit capabilities, `CKSharingSupported`, or remote notifications until invitation acceptance, account changes, revocation, and cache purging are implemented together.

## Catalog and community data

```text
App → operator catalog proxy → TMDB
```

The shipped binary contains no TMDB or AI provider secret. TMDB DTOs and image configuration remain inside a future data adapter and are mapped into domain values.

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
