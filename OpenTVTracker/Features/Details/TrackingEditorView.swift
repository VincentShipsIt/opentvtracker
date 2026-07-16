import SwiftUI

struct TrackingEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: MediaTitle

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        summaryCard
                        statusSection

                        if currentTitle.kind == .series, !regularSeasons.isEmpty {
                            episodeSection
                        }

                        ratingSection
                        noteLink

                        if currentTitle.state == .completed {
                            rewatchButton
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle(currentTitle.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: EpisodeSeasonsRoute.self) { route in
                EpisodeSeasonsView(titleID: route.titleID)
            }
            .navigationDestination(for: SeasonEpisodesRoute.self) { route in
                SeasonEpisodesView(route: route)
            }
        }
    }

    private var currentTitle: MediaTitle {
        model.mediaTitle(withID: title.id) ?? title
    }

    private var summaryCard: some View {
        TrackingSummaryCard(
            title: currentTitle,
            watchedEpisodeCount: watchedEpisodeCount,
            totalEpisodeCount: totalEpisodeCount
        )
    }

    private var statusSection: some View {
        TrackingStatusSection(
            states: WatchState.available(for: currentTitle.kind),
            selectedState: currentTitle.state
        ) { state in
            model.setWatchState(state, for: currentTitle.id)
        }
    }

    @ViewBuilder
    private var episodeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Episodes")

            if let nextEpisode {
                GlassSurface(cornerRadius: AppTheme.compactRadius) {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top, spacing: 13) {
                            EpisodeStillArtwork(
                                url: nextEpisode.episode.stillURL,
                                fallbackURL: currentTitle.backdropURL ?? currentTitle.posterURL,
                                showTitle: currentTitle.title,
                                episodeLabel: nextEpisodeLabel,
                                palette: currentTitle.palette
                            )
                            .frame(width: 116, height: 66)

                            VStack(alignment: .leading, spacing: 5) {
                                Text("Up next")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(nextEpisodeTitle)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(nextEpisodeMetadata)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button {
                            model.markNextWatched(currentTitle.id)
                        } label: {
                            Label("Mark episode watched", systemImage: "checkmark.circle.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .controlSize(.large)
                        .adaptiveGlassButton(prominent: true)
                    }
                    .padding(14)
                }
            } else if totalEpisodeCount > 0 {
                GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .green) {
                    Label("All episodes watched", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                }
            }

            if !regularSeasons.isEmpty {
                NavigationLink(value: EpisodeSeasonsRoute(titleID: currentTitle.id)) {
                    Label("View all episodes", systemImage: "rectangle.stack")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .adaptiveGlassButton()
            }
        }
    }

    private var ratingSection: some View {
        TrackingRatingSection(rating: currentTitle.userRating) { rating in
            model.setUserRating(rating, for: currentTitle.id)
        }
    }

    private var noteLink: some View {
        NavigationLink {
            PersonalNoteEditorView(title: currentTitle)
        } label: {
            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                HStack(spacing: 12) {
                    Image(systemName: currentTitle.notes == nil ? "note.text.badge.plus" : "note.text")
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Private note")
                            .font(.headline)
                        Text(notePreview)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens your personal note editor")
    }

    private var rewatchButton: some View {
        Button("Record a rewatch", systemImage: "arrow.counterclockwise.circle") {
            model.recordRewatch(currentTitle.id)
        }
        .frame(maxWidth: .infinity)
        .controlSize(.large)
        .adaptiveGlassButton()
        .accessibilityValue("\(currentTitle.completedRewatches) rewatches recorded")
    }

    private var regularSeasons: [SeasonSummary] {
        (currentTitle.seasons ?? [])
            .filter { $0.number > 0 }
            .sorted { $0.number < $1.number }
    }

    private var watchedEpisodeCount: Int {
        regularSeasons.reduce(0) { count, season in
            count + model.watchedEpisodeCount(titleID: currentTitle.id, season: season)
        }
    }

    private var totalEpisodeCount: Int {
        regularSeasons.reduce(0) { $0 + $1.episodes.count }
    }

    private var nextEpisode: (season: SeasonSummary, episode: EpisodeSummary)? {
        model.nextUnwatchedEpisode(for: currentTitle)
    }

    private var nextEpisodeLabel: String {
        guard let nextEpisode else { return "Next episode" }
        return "Season \(nextEpisode.season.number), episode \(nextEpisode.episode.number)"
    }

    private var nextEpisodeTitle: String {
        guard let nextEpisode else { return "Next episode" }
        return "S\(nextEpisode.season.number) E\(nextEpisode.episode.number) · \(nextEpisode.episode.title)"
    }

    private var nextEpisodeMetadata: String {
        guard let nextEpisode else { return "" }
        var values: [String] = []
        if let airDate = nextEpisode.episode.airDate {
            values.append(airDate.formatted(date: .abbreviated, time: .omitted))
        }
        if let runtime = nextEpisode.episode.runtimeMinutes {
            values.append("\(runtime) min")
        }
        return values.joined(separator: " · ")
    }

    private var notePreview: String {
        currentTitle.notes ?? "Add something only you can see"
    }
}

struct EpisodeSeasonsRoute: Hashable {
    let titleID: MediaTitle.ID
}

#Preview {
    TrackingEditorView(title: LibrarySnapshot.sample.titles[0])
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
