import SwiftUI

struct DateRangeNavigator: View {
    let title: String
    let previousLabel: String
    let nextLabel: String
    let onPrevious: () -> Void
    let onToday: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(previousLabel, systemImage: "chevron.left", action: onPrevious)
                .labelStyle(.iconOnly)

            Button(action: onToday) {
                VStack(spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Jump to today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Jump to today")
            .accessibilityValue(title)

            Button(nextLabel, systemImage: "chevron.right", action: onNext)
                .labelStyle(.iconOnly)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08)) }
    }
}

struct UpcomingCalendarStatusBanner: View {
    let isRefreshing: Bool
    let errorMessage: String?
    let lastRefreshedAt: Date?
    let hasItems: Bool
    let regionCode: String
    let timeZoneIdentifier: String

    var body: some View {
        GlassSurface(tint: tint) {
            HStack(alignment: .top, spacing: 12) {
                if isRefreshing {
                    ProgressView()
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(tint)
                        .accessibilityHidden(true)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        if isRefreshing { return "Updating schedule" }
        if errorMessage != nil { return hasItems ? "Showing saved schedule" : "Schedule unavailable" }
        if lastRefreshedAt != nil { return "Schedule is current" }
        return "Saved schedule"
    }

    private var detail: String {
        let location = "Region \(regionCode) · \(timeZoneIdentifier)"
        if isRefreshing { return "\(location) · Checking for schedule changes." }
        if let errorMessage { return errorMessage }
        guard let lastRefreshedAt else {
            return "\(location) · Refresh to check for changes."
        }
        return "\(location) · Updated \(lastRefreshedAt.formatted(date: .omitted, time: .shortened))."
    }

    private var symbol: String {
        if isRefreshing { return "arrow.clockwise" }
        if errorMessage != nil { return hasItems ? "wifi.slash" : "exclamationmark.triangle.fill" }
        if lastRefreshedAt != nil { return "checkmark.circle.fill" }
        return "externaldrive.fill.badge.checkmark"
    }

    private var tint: Color {
        if isRefreshing { return .blue }
        if errorMessage != nil { return hasItems ? .orange : .red }
        return lastRefreshedAt != nil ? .green : .blue
    }
}

struct UpcomingCalendarDaySection: View {
    let day: UpcomingCalendarDay
    let calendar: Calendar

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: dayTitle, subtitle: "\(day.items.count) scheduled")
                .padding(.horizontal, AppTheme.horizontalPadding)

            VStack(spacing: 10) {
                ForEach(day.items) { item in
                    NavigationLink(value: destination(for: item)) {
                        UpcomingCalendarEventRow(item: item, calendar: calendar)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
        }
    }

    private var dayTitle: String {
        if calendar.isDateInToday(day.date) { return "Today" }
        if calendar.isDateInTomorrow(day.date) { return "Tomorrow" }
        return day.date.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private func destination(for item: UpcomingCalendarItem) -> UpcomingCalendarDestination {
        if let seasonID = item.seasonID, let episodeID = item.episodeID {
            return .episode(
                EpisodeDetailRoute(titleID: item.titleID, seasonID: seasonID, episodeID: episodeID)
            )
        }
        return .title(item.titleID)
    }
}

private struct UpcomingCalendarEventRow: View {
    let item: UpcomingCalendarItem
    let calendar: Calendar

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            HStack(spacing: 14) {
                Image(systemName: item.kind.symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 42, height: 42)
                    .background(Color.accentColor.opacity(0.14), in: Circle())
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.kind.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(eventDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(timeLabel)
                        .font(.caption.weight(.semibold).monospacedDigit())
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(item.episodeID == nil ? "Opens title details" : "Opens episode details")
    }

    private var eventDetail: String {
        if let season = item.seasonNumber, let episode = item.episodeNumber {
            if let episodeTitle = item.episodeTitle, !episodeTitle.isEmpty {
                return "S\(season) E\(episode) · \(episodeTitle)"
            }
            return "Season \(season), episode \(episode)"
        }
        if item.kind == .movieRelease { return item.watchState.label }
        return "Episode details will appear after the next metadata refresh."
    }

    private var timeLabel: String {
        if item.isAllDay { return "All day" }
        return item.date.formatted(date: .omitted, time: .shortened)
    }
}
