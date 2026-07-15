import SwiftUI

struct MediaEpisodeSection: View {
    let title: MediaTitle

    var body: some View {
        if let seasons = title.seasons, !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(
                    title: "Episodes",
                    subtitle: "Air dates and runtimes from \(title.metadataSource?.displayName ?? "the catalog")"
                )
                ForEach(seasons) { season in
                    seasonGroup(season)
                }
            }
        }
    }

    private func seasonGroup(_ season: SeasonSummary) -> some View {
        DisclosureGroup {
            ForEach(season.episodes) { episode in
                episodeRow(episode)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(season.title)
                Text("\(season.episodes.count) episodes")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func episodeRow(_ episode: EpisodeSummary) -> some View {
        LabeledContent {
            VStack(alignment: .trailing, spacing: 3) {
                Text(episode.airDate?.formatted(date: .abbreviated, time: .omitted) ?? "TBA")
                if let runtime = episode.runtimeMinutes {
                    Text("\(runtime) min")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Text("E\(episode.number) · \(episode.title)")
                .lineLimit(2)
        }
        .padding(.vertical, 4)
    }
}

struct MediaRatingSummary: View {
    let title: MediaTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Ratings", subtitle: "Use scores as a signal, then check the reviews")
            HStack(spacing: 12) {
                RatingSourceCard(source: title.metadataSource?.displayName ?? "Catalog", rating: title.rating)
                if let userRating = title.userRating {
                    RatingSourceCard(source: "You", rating: userRating)
                }
            }
        }
    }
}

private struct RatingSourceCard: View {
    let source: String
    let rating: Double

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            VStack(alignment: .leading, spacing: 5) {
                Text(source)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                RatingLabel(rating: rating)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
    }
}
