import SwiftUI

struct EpisodeTrackingActions: ViewModifier {
    @Environment(AppModel.self) private var model
    @State private var showsPreviousEpisodesConfirmation = false
    let title: MediaTitle
    let season: SeasonSummary
    let episode: EpisodeSummary

    func body(content: Content) -> some View {
        content
            .swipeActions(edge: .trailing, allowsFullSwipe: true) { toggleButton }
            .swipeActions(edge: .leading, allowsFullSwipe: false) { previousButton }
            .contextMenu {
                toggleButton
                previousButton
            }
            .accessibilityAction(named: isWatched ? "Mark unwatched" : "Mark watched") {
                toggleWatched()
            }
            .accessibilityAction(named: "Mark this and previous watched") {
                requestPreviousEpisodesConfirmation()
            }
            .confirmationDialog(
                "Mark previous episodes too?",
                isPresented: $showsPreviousEpisodesConfirmation,
                titleVisibility: .visible
            ) {
                Button("Episodes 1–\(episode.number)") {
                    markPreviousWatched()
                }
                Button("Only episode \(episode.number)") {
                    markOnlyThisEpisodeWatched()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Some earlier episodes in \(season.title) are still unwatched. What should be added to your history?")
            }
    }

    private var toggleButton: some View {
        Button {
            toggleWatched()
        } label: {
            Label(
                isWatched ? "Mark unwatched" : "Mark watched",
                systemImage: isWatched ? "arrow.uturn.backward.circle.fill" : "checkmark.circle.fill"
            )
        }
        .tint(isWatched ? .orange : .green)
    }

    private var previousButton: some View {
        Button("Mark this and previous watched", systemImage: "checkmark.circle.badge.plus") {
            requestPreviousEpisodesConfirmation()
        }
        .tint(.blue)
        .disabled(arePreviousWatched)
    }

    private var isWatched: Bool {
        model.isEpisodeWatched(
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )
    }

    private var arePreviousWatched: Bool {
        model.areEpisodesWatchedThrough(
            titleID: title.id,
            seasonNumber: season.number,
            episodeNumber: episode.number
        )
    }

    private var hasUnwatchedPreviousEpisodes: Bool {
        model.hasUnwatchedEpisodesBefore(
            titleID: title.id,
            seasonNumber: season.number,
            episodeNumber: episode.number
        )
    }

    private func toggleWatched() {
        if isWatched {
            model.setEpisodeWatched(
                false,
                titleID: title.id,
                seasonNumber: season.number,
                episodeID: episode.id
            )
        } else if hasUnwatchedPreviousEpisodes {
            requestPreviousEpisodesConfirmation()
        } else {
            markOnlyThisEpisodeWatched()
        }
    }

    private func requestPreviousEpisodesConfirmation() {
        guard hasUnwatchedPreviousEpisodes else {
            markOnlyThisEpisodeWatched()
            return
        }
        showsPreviousEpisodesConfirmation = true
    }

    private func markOnlyThisEpisodeWatched() {
        model.setEpisodeWatched(
            true,
            titleID: title.id,
            seasonNumber: season.number,
            episodeID: episode.id
        )
    }

    private func markPreviousWatched() {
        model.markEpisodesWatchedThrough(
            titleID: title.id,
            seasonNumber: season.number,
            episodeNumber: episode.number
        )
    }
}
