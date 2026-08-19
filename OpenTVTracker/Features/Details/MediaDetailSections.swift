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
                            title: title,
                            watchedCount: model.watchedEpisodeCount(titleID: title.id, season: season)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("season.\(season.number)")
                }
            }
        } else if title.kind == .series, let error = model.catalogDetailError(for: title.id) {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(
                    title: "Episodes",
                    subtitle: "Air dates and runtimes from \(title.metadataSource?.displayName ?? "the catalog")"
                )
                GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .orange) {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("Episode list unavailable", systemImage: "exclamationmark.triangle.fill")
                            .font(.headline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Button("Try again") {
                            Task { await model.refreshCatalogDetails(for: title.id) }
                        }
                        .adaptiveGlassButton()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }
            }
            .accessibilityIdentifier("episodes.unavailable")
        }
    }
}

struct SeasonNavigationRow: View {
    let season: SeasonSummary
    let title: MediaTitle
    let watchedCount: Int

    var body: some View {
        HStack(spacing: 12) {
            // A list of seasons is otherwise a stack of near-identical text rows. Key art
            // gives each one something to recognise it by before reading the label.
            SeasonArtwork(season: season, title: title)
                .frame(width: 44, height: 66)

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
        let episodeCount = season.episodes.count
        guard watchedCount > 0 else {
            return CountLabel.episodes(episodeCount)
        }
        return "\(watchedCount) of \(episodeCount) watched"
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
