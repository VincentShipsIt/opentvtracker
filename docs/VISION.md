# Product vision

## The promise

OpenTV Tracker answers three questions quickly:

1. What is new?
2. What should I watch next?
3. What are we watching together?

It should feel calm, personal, and fast. Tracking is useful without an account. Sharing is private by default. Recommendations explain themselves instead of presenting an opaque feed.

## Who it is for

- People leaving closed or declining TV trackers who want ownership and portability.
- Couples and small households coordinating a shared watchlist and episode progress.
- Viewers who want discovery based on their actual history, mood, time, and available streaming services.

## Product principles

- **Local first.** Opening the app and marking something watched must work offline.
- **Private together.** Shared spaces are invitation-only; public activity is never the default.
- **Explain recommendations.** Every suggestion says why it fits.
- **Open data paths.** Export and import are first-class, not retention afterthoughts.
- **Useful before social.** Community context is additive; no empty-feed problem.
- **Native over ornamental.** Liquid Glass supports hierarchy and interaction rather than coating every surface.

## v1 experience

### Today

A personal queue combining the next episode, recently released episodes, unfinished movies, and partner activity. One primary action marks progress without opening a detail screen.

### Discover

Search plus artwork-led recommendation shelves inspired by the speed of modern delivery apps. Filters default to the streaming services the viewer already pays for, then narrow by mood, runtime, genre, and whether both partners are likely to enjoy it. Every title exposes its official trailer before demanding a commitment.

### Together

One invitation-only space with a shared watchlist, independent or shared progress, reactions, and lightweight notes. Conflict resolution never silently moves progress backward.

### Library

Watching, planned, paused, and completed titles with portable history and clear progress.

### Details

Episode and movie metadata, progress controls, streaming availability, spoiler-safe community excerpts, and links to source sites such as TMDB and IMDb.

## Data sources and boundaries

- TMDB is the primary catalog, artwork, discovery, and review source. Its required attribution belongs in Settings/Credits.
- Streaming availability comes through TMDB's JustWatch-backed provider endpoints and must visibly attribute JustWatch.
- IMDb is used through outbound links or a future licensed data path; the app does not scrape IMDb pages.
- AI calls go through an operator-controlled proxy. Personal history is minimized and redacted before leaving the device.

## Non-goals for v1

- A public follower graph or user-generated review network.
- Playback, torrenting, or hosting copyrighted media.
- A web or Android client.
- Household groups larger than a small private space.
- Monetization.

## Success signals

- A user reaches a useful Today screen within two minutes of first launch.
- Marking an episode watched takes one tap from Today.
- A partner can accept an invite and see the same shared list without creating a separate app password.
- The recommendation flow produces a credible choice in under one minute and explains why.
- A complete export can be produced without contacting support.
