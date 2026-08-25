# Contributing

OpenTV accepts focused, public-safe contributions. Contributors should:

1. Start from a focused issue and keep pull requests reviewable.
2. Preserve local-only use. Keep TMDB credentials server-side and user-authorized OpenRouter credentials in Keychain.
3. Add or update tests for domain, persistence, import, recommendation, and sync behavior.
4. Generate the Xcode project with `.github/scripts/generate-ios-project.sh generate`, then run `.github/scripts/generate-ios-project.sh check` from a clean commit. Do not invoke an unpinned XcodeGen directly or update `Package.resolved` without reviewing its exact revision. Run [`.github/scripts/run-swiftlint.sh`](.github/scripts/run-swiftlint.sh) and `bun test` in `server/`. GitHub Actions runs pinned SwiftLint and one iOS Simulator destination in the existing iOS build-and-test job, plus the server tests/typecheck/image build and a secret scan. There is no multi-destination build matrix.
5. Include VoiceOver labels, Dynamic Type behavior, and non-color state indicators for new UI.
6. Update attribution, privacy metadata, and the data-lifecycle documentation when a dependency or network payload changes.

By contributing, you agree that your work is licensed under the repository's MIT license.
