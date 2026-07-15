import SwiftUI

struct SeasonEpisodesRoute: Hashable {
    let titleID: MediaTitle.ID
    let seasonID: SeasonSummary.ID
}

struct SeasonEpisodesView: View {
    @Environment(AppModel.self) private var model
    let route: SeasonEpisodesRoute

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let title, let season {
                List {
                    SeasonProgressHeader(
                        title: title,
                        season: season,
                        watchedCount: model.watchedEpisodeCount(titleID: title.id, season: season)
                    )
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 10, leading: 20, bottom: 10, trailing: 20))

                    ForEach(season.episodes) { episode in
                        episodeRow(title: title, season: season, episode: episode)
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
    }

    private var title: MediaTitle? {
        model.mediaTitle(withID: route.titleID)
    }

    private var season: SeasonSummary? {
        title?.seasons?.first(where: { $0.id == route.seasonID })
    }

    private func episodeRow(
        title: MediaTitle,
        season: SeasonSummary,
        episode: EpisodeSummary
    ) -> some View {
        let isWatched = model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )

        return EpisodeRow(
            title: title,
            seasonNumber: season.number,
            episode: episode,
            isWatched: isWatched
        )
        .contentShape(.rect)
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                model.setEpisodeWatched(
                    !isWatched,
                    titleID: title.id,
                    seasonNumber: season.number,
                    episodeID: episode.id
                )
            } label: {
                Label(
                    isWatched ? "Mark unwatched" : "Mark watched",
                    systemImage: isWatched ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill"
                )
            }
            .tint(isWatched ? .orange : .green)
        }
        .accessibilityAction(named: isWatched ? "Mark unwatched" : "Mark watched") {
            model.setEpisodeWatched(
                !isWatched,
                titleID: title.id,
                seasonNumber: season.number,
                episodeID: episode.id
            )
        }
    }
}

private struct SeasonProgressHeader: View {
    let title: MediaTitle
    let season: SeasonSummary
    let watchedCount: Int

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
                Text("Swipe an episode left to mark it watched or unwatched.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
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
        .accessibilityHint("Swipe left for tracking actions")
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
