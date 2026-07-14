# Roadmap

## Milestone 0 — Foundation

- SwiftUI app shell and native Liquid Glass design system
- Today, artwork-led Discover, Together, Library, trailer, and detail flows using representative preview data
- Persistent subscription filters for Netflix, Prime Video, Apple TV+, and other supported providers
- Domain models and repository/service boundaries
- Local progress interactions
- Accessibility, empty, loading, and failure states

## Milestone 1 — Personal tracker

- TMDB search, details, seasons, episodes, images, reviews, and provider availability
- SwiftData persistence and migrations
- Air-date-aware Up Next queue
- Watch states, ratings, notes, rewatching, and notification preferences
- JSON/CSV export and TV Time-compatible import investigation

## Milestone 2 — Together

- CloudKit custom zone, local cache, and sync engine
- Private share invitation and acceptance
- Shared list, membership, activity, reactions, and conflict rules
- Push-driven incremental sync and offline reconciliation

## Milestone 3 — Discovery

- Deterministic recommendations from history, genres, providers, mood, and runtime
- Explainable couple-match scoring
- Optional server-side AI reranking and conversational discovery skill
- Privacy controls and recommendation feedback

## Milestone 4 — Public beta

- Onboarding, credits, privacy policy, diagnostics, and feedback
- TestFlight and App Store metadata
- Public repository hardening, contribution guide, security policy, and issue templates
- Import/export validation against real libraries

## Open decisions

- Final product name and bundle identifier
- Whether v1 supports one partner space or multiple spaces
- Which country/provider set is the launch default
- Whether AI is self-hosted, OpenAI-backed, or entirely on-device
- Whether a future public community layer is federated, centralized, or source-only
