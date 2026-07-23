import SwiftUI

struct EpisodeDetailView: View {
    @Environment(AppModel.self) private var model
    @State private var showsPreviousEpisodesConfirmation = false
    let route: EpisodeDetailRoute

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let title, let season, let episode {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        hero(title: title, season: season, episode: episode)
                        trackingActions(title: title, season: season, episode: episode)
                        EpisodeDiarySection(title: title, season: season, episode: episode)
                        EpisodeConversationView(
                            title: title,
                            season: season,
                            episode: episode
                        )
                        episodeInformation(episode)
                        EpisodeStorySection(title: title, season: season, episode: episode)
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView(
                    "Episode unavailable",
                    systemImage: "play.rectangle.on.rectangle",
                    description: Text("Refresh the title details and try again.")
                )
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Mark previous episodes too?",
            isPresented: $showsPreviousEpisodesConfirmation,
            titleVisibility: .visible
        ) {
            if let title, let season, let episode {
                Button("Episodes 1–\(episode.number)") {
                    model.markEpisodesWatchedThrough(
                        titleID: title.id,
                        seasonNumber: season.number,
                        episodeNumber: episode.number
                    )
                }
                Button("Only episode \(episode.number)") {
                    model.setEpisodeWatched(
                        true,
                        titleID: title.id,
                        seasonNumber: season.number,
                        episodeID: episode.id
                    )
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Some earlier episodes in this season are still unwatched. What should be added to your history?")
        }
    }

    private var title: MediaTitle? {
        model.mediaTitle(withID: route.titleID)
    }

    private var season: SeasonSummary? {
        title?.seasons?.first(where: { $0.id == route.seasonID })
    }

    private var episode: EpisodeSummary? {
        season?.episodes.first(where: { $0.id == route.episodeID })
    }

    private var navigationTitle: String {
        guard let season, let episode else { return "Episode details" }
        return "S\(season.number) E\(episode.number)"
    }

    @ViewBuilder
    private func hero(
        title: MediaTitle,
        season: SeasonSummary,
        episode: EpisodeSummary
    ) -> some View {
        let isWatched = model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )
        AdaptiveHeroSurface(minimumHeight: 210, cornerRadius: 10) {
            if isWatched {
                EpisodeStillArtwork(
                    url: episode.stillURL,
                    fallbackURL: title.backdropURL ?? title.posterURL,
                    showTitle: title.title,
                    episodeLabel: "Season \(season.number), episode \(episode.number)",
                    palette: title.palette
                )
            } else {
                EpisodeSpoilerArtworkPlaceholder(label: "Artwork hidden until watched")
            }
        } content: {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(season.title) · Episode \(episode.number)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                Text(isWatched ? episode.title : "Episode title hidden until watched")
                    .font(.title2.weight(.black))
                    .foregroundStyle(.white)
                    .lineLimit(2)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func trackingActions(
        title: MediaTitle,
        season: SeasonSummary,
        episode: EpisodeSummary
    ) -> some View {
        let isWatched = model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )
        let arePreviousWatched = model.areEpisodesWatchedThrough(
            titleID: title.id,
            seasonNumber: season.number,
            episodeNumber: episode.number
        )

        return VStack(spacing: 10) {
            Button {
                requestEpisodeWatch(
                    isWatched: isWatched,
                    title: title,
                    season: season,
                    episode: episode
                )
            } label: {
                Label(
                    isWatched ? "Mark episode unwatched" : "Mark episode watched",
                    systemImage: isWatched ? "arrow.uturn.backward.circle" : "checkmark.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .adaptiveGlassButton(prominent: !isWatched)
            .accessibilityIdentifier("episode.mark-watched")

            Button {
                requestPreviousEpisodesWatch(
                    title: title,
                    season: season,
                    episode: episode
                )
            } label: {
                Label(
                    arePreviousWatched ? "This and previous episodes watched" : "Mark this and previous watched",
                    systemImage: arePreviousWatched ? "checkmark.seal.fill" : "checkmark.circle.badge.plus"
                )
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .adaptiveGlassButton()
            .disabled(arePreviousWatched)
        }
    }

    private func requestPreviousEpisodesWatch(
        title: MediaTitle,
        season: SeasonSummary,
        episode: EpisodeSummary
    ) {
        if model.hasUnwatchedEpisodesBefore(
            titleID: title.id,
            seasonNumber: season.number,
            episodeNumber: episode.number
        ) {
            showsPreviousEpisodesConfirmation = true
        } else {
            model.setEpisodeWatched(
                true,
                titleID: title.id,
                seasonNumber: season.number,
                episodeID: episode.id
            )
        }
    }

    private func requestEpisodeWatch(
        isWatched: Bool,
        title: MediaTitle,
        season: SeasonSummary,
        episode: EpisodeSummary
    ) {
        if isWatched {
            model.setEpisodeWatched(
                false,
                titleID: title.id,
                seasonNumber: season.number,
                episodeID: episode.id
            )
        } else if model.hasUnwatchedEpisodesBefore(
            titleID: title.id,
            seasonNumber: season.number,
            episodeNumber: episode.number
        ) {
            showsPreviousEpisodesConfirmation = true
        } else {
            model.setEpisodeWatched(
                true,
                titleID: title.id,
                seasonNumber: season.number,
                episodeID: episode.id
            )
        }
    }

    private func episodeInformation(_ episode: EpisodeSummary) -> some View {
        return VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Episode details")

            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                VStack(spacing: 0) {
                    DetailRow(label: "Air date", value: airDateLabel(for: episode))
                    Divider().padding(.leading, 16)
                    DetailRow(label: "Runtime", value: runtimeLabel(for: episode))
                    if let rating = episode.rating, rating > 0 {
                        Divider().padding(.leading, 16)
                        HStack {
                            Text("TMDB rating")
                            Spacer()
                            RatingLabel(rating: rating)
                        }
                        .padding(16)
                    }
                }
            }
        }
    }

    private func airDateLabel(for episode: EpisodeSummary) -> String {
        episode.airDate?.formatted(date: .long, time: .omitted) ?? "To be announced"
    }

    private func runtimeLabel(for episode: EpisodeSummary) -> String {
        episode.runtimeMinutes.map { "\($0) minutes" } ?? "Not available"
    }
}

private struct EpisodeDiarySection: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    let season: SeasonSummary
    let episode: EpisodeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Your diary")

            if isWatched {
                NavigationLink {
                    ViewingDiaryEditorView(target: target)
                } label: {
                    GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .indigo) {
                        HStack(spacing: 12) {
                            Image(systemName: "book.pages.fill")
                                .font(.title3)
                                .foregroundStyle(.indigo)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Rating, note, and watch dates")
                                    .font(.headline)
                                Text("Private to this device and your exports")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .padding(14)
                    }
                }
                .buttonStyle(.plain)
            } else {
                GlassSurface(cornerRadius: AppTheme.compactRadius) {
                    Label(
                        "Mark this episode watched to unlock private notes and ratings",
                        systemImage: "eye.slash.fill"
                    )
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(16)
                }
            }
        }
    }

    private var isWatched: Bool {
        model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )
    }

    private var target: ViewingDiaryTarget {
        .episode(
            titleID: title.id,
            seasonID: season.id,
            seasonNumber: season.number,
            episodeID: episode.id,
            episodeNumber: episode.number
        )
    }
}

private struct EpisodeStorySection: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    let season: SeasonSummary
    let episode: EpisodeSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Story")

            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                if isWatched {
                    Text(episode.overview?.nilIfBlank ?? "No episode description is available yet.")
                        .font(.body)
                        .lineSpacing(5)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                } else {
                    Label("Episode summary hidden until watched", systemImage: "eye.slash.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18)
                }
            }
        }
    }

    private var isWatched: Bool {
        model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

#Preview {
    NavigationStack {
        EpisodeDetailView(
            route: EpisodeDetailRoute(
                titleID: "severance",
                seasonID: "season-1",
                episodeID: "severance-s1e1"
            )
        )
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
    }
}
