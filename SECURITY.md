# Security policy

## Supported versions

Only the latest beta and the current default branch receive security fixes.

## Reporting

Do not open a public issue for a vulnerability or exposed credential. Report it privately through GitHub Security Advisories for this repository. Include impact, reproduction steps, affected commit, and any suggested mitigation.

## Boundaries

- No TMDB, AI, cinema-feed, or other provider secret belongs in the app bundle or repository.
- CloudKit shares are invitation-only and use custom zones separated from personal SwiftData.
- Diagnostic text must not include private notes, share URLs, auth tokens, raw watch events, or full server responses.
- Imported files are previewed before commit and never uploaded as part of import.
