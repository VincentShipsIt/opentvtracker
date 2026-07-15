import SwiftUI

struct SeasonEpisodesRoute: Hashable {
    let titleID: MediaTitle.ID
    let seasonID: SeasonSummary.ID
}

struct EpisodeDetailRoute: Hashable {
    let titleID: MediaTitle.ID
    let seasonID: SeasonSummary.ID
    let episodeID: EpisodeSummary.ID
}

struct SeasonEpisodesView: View {
    @Environment(AppModel.self) private var model
    @State private var pendingSeasonAction: SeasonWatchAction?
    @State private var showsSeasonConfirmation = false
    let route: SeasonEpisodesRoute

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let title, let season {
                List {
                    SeasonProgressHeader(
                        title: title,
                        season: season,
                        watchedCount: model.watchedEpisodeCount(titleID: title.id, season: season),
                        onMarkAllWatched: {
                            requestSeasonAction(.markWatched)
                        },
                        onMarkAllUnwatched: {
                            requestSeasonAction(.markUnwatched)
                        }
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))

                    ForEach(season.episodes) { episode in
                        TrackableEpisodeRow(title: title, season: season, episode: episode)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                ContentUnavailableView(
                    "Episodes unavailable",
                    systemImage: "rectangle.stack.badge.exclamationmark",
                    description: Text("Refresh the title details and try again.")
                )
            }
        }
        .navigationTitle(season?.title ?? "Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: EpisodeDetailRoute.self) { route in
            EpisodeDetailView(route: route)
        }
        .toolbar {
            if let title, let season {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu("Episode actions", systemImage: "ellipsis.circle") {
                        Button("Mark all watched", systemImage: "checkmark.circle.fill") {
                            requestSeasonAction(.markWatched)
                        }
                        .disabled(
                            model.watchedEpisodeCount(titleID: title.id, season: season)
                                == season.episodes.count
                        )

                        Button("Mark all unwatched", systemImage: "arrow.uturn.backward.circle") {
                            requestSeasonAction(.markUnwatched)
                        }
                        .disabled(model.watchedEpisodeCount(titleID: title.id, season: season) == 0)
                    }
                }
            }
        }
        .confirmationDialog(
            pendingSeasonAction?.title ?? "Update season progress?",
            isPresented: $showsSeasonConfirmation,
            presenting: pendingSeasonAction
        ) { action in
            Button(action.confirmationTitle, role: action.role) {
                applySeasonAction(action)
            }
            Button("Cancel", role: .cancel) {}
        } message: { action in
            Text(action.message(for: season?.title ?? "this season"))
        }
    }

    private var title: MediaTitle? {
        model.mediaTitle(withID: route.titleID)
    }

    private var season: SeasonSummary? {
        title?.seasons?.first(where: { $0.id == route.seasonID })
    }

    private func requestSeasonAction(_ action: SeasonWatchAction) {
        pendingSeasonAction = action
        showsSeasonConfirmation = true
    }

    private func applySeasonAction(_ action: SeasonWatchAction) {
        defer { pendingSeasonAction = nil }
        guard let title, let season else { return }
        model.setSeasonEpisodesWatched(
            action.watched,
            titleID: title.id,
            seasonNumber: season.number
        )
    }
}

private enum SeasonWatchAction: Equatable {
    case markWatched
    case markUnwatched

    var watched: Bool { self == .markWatched }
    var title: String { watched ? "Mark the full season watched?" : "Reset the full season?" }
    var confirmationTitle: String { watched ? "Mark season watched" : "Mark season unwatched" }
    var role: ButtonRole? { watched ? nil : .destructive }

    func message(for seasonTitle: String) -> String {
        watched
            ? "Every episode in \(seasonTitle) will be added to your watch history and recommendation profile."
            : "Every episode in \(seasonTitle) will be removed from your watched progress."
    }
}

private struct TrackableEpisodeRow: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    let season: SeasonSummary
    let episode: EpisodeSummary

    var body: some View {
        NavigationLink(value: detailRoute) {
            EpisodeRow(
                title: title,
                seasonNumber: season.number,
                episode: episode,
                isWatched: isWatched
            )
        }
        .buttonStyle(.plain)
        .contentShape(.rect)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .modifier(EpisodeTrackingActions(title: title, season: season, episode: episode))
        .accessibilityIdentifier("episode.\(episode.number)")
    }

    private var detailRoute: EpisodeDetailRoute {
        EpisodeDetailRoute(titleID: title.id, seasonID: season.id, episodeID: episode.id)
    }

    private var isWatched: Bool {
        model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )
    }
}

private struct SeasonProgressHeader: View {
    let title: MediaTitle
    let season: SeasonSummary
    let watchedCount: Int
    let onMarkAllWatched: () -> Void
    let onMarkAllUnwatched: () -> Void

    var body: some View {
        GlassSurface(tint: Color(hex: title.palette.primaryHex)) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title.title)
                    .font(.title2.weight(.black))
                HStack {
                    Label("\(season.episodes.count) episodes", systemImage: "play.rectangle.on.rectangle")
                    Spacer()
                    Text("\(watchedCount) watched")
                        .fontWeight(.semibold)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                ProgressView(value: Double(watchedCount), total: Double(max(season.episodes.count, 1)))
                    .tint(.accentColor)
                Text("Tap an episode for details, or swipe it for watch actions.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button(action: onMarkAllWatched) {
                        Label("Mark all", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButton(prominent: true)
                    .disabled(watchedCount == season.episodes.count)
                    .accessibilityIdentifier("season.mark-all-watched")

                    Button(action: onMarkAllUnwatched) {
                        Label("Reset", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity)
                    }
                    .adaptiveGlassButton()
                    .disabled(watchedCount == 0)
                }
            }
            .padding(16)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Season progress")
    }
}

private struct EpisodeRow: View {
    let title: MediaTitle
    let seasonNumber: Int
    let episode: EpisodeSummary
    let isWatched: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            EpisodeStillArtwork(
                url: episode.stillURL,
                fallbackURL: title.backdropURL ?? title.posterURL,
                showTitle: title.title,
                episodeLabel: "Season \(seasonNumber), episode \(episode.number)",
                palette: title.palette
            )
            .frame(width: 116, height: 66)
            .overlay(alignment: .bottomTrailing) {
                if isWatched {
                    Image(systemName: "checkmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .green)
                        .padding(5)
                }
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("E\(episode.number) · \(episode.title)")
                    .font(.headline)
                    .lineLimit(2)
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let overview = episode.overview, !overview.isEmpty {
                    Text(overview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

        }
        .opacity(isWatched ? 0.68 : 1)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens episode details. Swipe for tracking actions")
    }

    private var metadata: String {
        var values: [String] = []
        if let airDate = episode.airDate {
            values.append(airDate.formatted(date: .abbreviated, time: .omitted))
        } else {
            values.append("TBA")
        }
        if let runtime = episode.runtimeMinutes {
            values.append("\(runtime) min")
        }
        return values.joined(separator: " · ")
    }

    private var accessibilityLabel: String {
        let watchedStatus = isWatched ? "Watched" : "Unwatched"
        return "Episode \(episode.number), \(episode.title). \(metadata). \(watchedStatus)."
    }
}

#Preview {
    NavigationStack {
        SeasonEpisodesView(
            route: SeasonEpisodesRoute(titleID: "severance", seasonID: "season-1")
        )
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
    }
}
