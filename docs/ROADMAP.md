# Roadmap

Last reviewed 2026-08-24. Current app version and build metadata are defined in [`project.yml`](../project.yml); published source versions are listed under [GitHub Releases](https://github.com/VincentShipsIt/opentvtracker/releases).

## Shipped

- Native SwiftUI tracker designed around Liquid Glass on iOS 26, targeting iPhone and iPad
- Three tabs — Today, Discover, Library — plus a Personal/Shared overlay
- Live TV discovery, search, artwork, trailers, seasons, and episodes from TVmaze
- Operator-owned TMDB boundary for movie and TV metadata, Malta provider availability, trailers, attributed reviews, and TVDB resolve
- Personal and shared watchlists, episode progress, ratings, notes, rewatches, and release-aware Up Next
- Invitation-only partner sharing, nearby pairing, partner notifications, and offline reconciliation through CloudKit
- Native custom lists (shared lists sync; Trakt imported lists stay in `TraktSyncState.importedLists`)
- Viewing diary, upcoming calendar, local reminders, and home-screen widgets
- Trakt device-OAuth sync and TV Time data-export import
- Content-language preference forwarded as the catalog `language` query parameter
- Food-delivery-style illustrated category discovery, service selection, and More Like This
- Text and voice discovery assistant with deterministic recommendations and opt-in OpenRouter reranking
- Live Embassy Cinemas schedules and official Embassy, Eden, and Citadel booking links for Malta
- Versioned JSON/CSV import and export (including diary and lists CSV)
- Public repository, TestFlight upload workflow, and PostgreSQL App Attest device store

## After v1 extras above

- App Store metadata and wider TestFlight distribution
- Additional licensed regional cinema and review providers
- On-device semantic recommendation experiments
- Multiple partner spaces and an opt-in community layer
