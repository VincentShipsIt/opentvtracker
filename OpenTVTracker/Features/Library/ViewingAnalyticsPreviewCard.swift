import SwiftUI

struct ViewingAnalyticsPreviewCard: View {
    let summary: ViewingAnalyticsSummary

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: accent) {
            HStack(spacing: 14) {
                Image(systemName: summary.scope == .personal ? "chart.bar.fill" : "person.2.fill")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(accent.opacity(0.12), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.scope == .personal ? "My viewing stats" : "Our viewing stats")
                        .font(.headline)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private var accent: Color {
        summary.scope == .personal ? .indigo : .pink
    }

    private var detail: String {
        guard !summary.isEmpty else {
            return summary.scope == .personal
                ? "Your watched hours, genres, movies and episodes"
                : "Hours, genres, movies and episodes watched together"
        }
        let titleLabel = summary.titleCount == 1 ? "title" : "titles"
        let episodeLabel = summary.episodeCount == 1 ? "episode" : "episodes"
        return "\(duration) · \(summary.titleCount) \(titleLabel) · \(summary.episodeCount) \(episodeLabel)"
    }

    private var duration: String {
        let hours = summary.totalMinutes / 60
        let minutes = summary.totalMinutes % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }
}
