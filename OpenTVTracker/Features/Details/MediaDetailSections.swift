import SwiftUI

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.trailing)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }
}

struct MediaEpisodeSection: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle

    var body: some View {
        if let seasons = title.seasons, !seasons.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(
                    title: "Episodes",
                    subtitle: "Air dates and runtimes from \(title.metadataSource?.displayName ?? "the catalog")"
                )
                ForEach(seasons) { season in
                    NavigationLink(
                        value: SeasonEpisodesRoute(titleID: title.id, seasonID: season.id)
                    ) {
                        SeasonNavigationRow(
                            season: season,
                            watchedCount: model.watchedEpisodeCount(titleID: title.id, season: season)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("season.\(season.number)")
                }
            }
        }
    }
}

struct SeasonNavigationRow: View {
    let season: SeasonSummary
    let watchedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(season.title)
                    .font(.body.weight(.medium))
                Text(progressLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full episode list")
    }

    private var progressLabel: String {
        guard watchedCount > 0 else { return "\(season.episodes.count) episodes" }
        return "\(watchedCount) of \(season.episodes.count) watched"
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
