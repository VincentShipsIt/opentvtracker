import Charts
import SwiftUI

struct ViewingAnalyticsView: View {
    @Environment(AppModel.self) private var model
    @State private var sharePayload: ViewingAnalyticsSharePayload?
    let scope: ViewingAnalyticsScope

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                LazyVStack(spacing: AppTheme.sectionSpacing) {
                    if summary.isEmpty {
                        emptyState
                    } else {
                        AnalyticsHero(summary: summary)
                        AnalyticsStatGrid(summary: summary)
                        ViewingMixSection(summary: summary)
                        GenreHoursSection(summary: summary)
                        ServiceHoursSection(summary: summary)
                        if scope == .together {
                            MemberHoursSection(summary: summary)
                        }
                        Button {
                            share()
                        } label: {
                            Label("Share card on X", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                        }
                        .adaptiveGlassButton(prominent: true)
                        .accessibilityHint("Opens the share sheet with a generated image and post text")
                        trackingNote
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.vertical, 12)
                .padding(.bottom, 32)
            }
        }
        .navigationTitle(scope == .personal ? "My viewing stats" : "Our viewing stats")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Share analytics", systemImage: "square.and.arrow.up") {
                    share()
                }
                .disabled(summary.isEmpty)
            }
        }
        .sheet(item: $sharePayload) { payload in
            ActivityShareSheet(items: [payload.text, payload.image])
                .presentationDetents([.medium, .large])
        }
    }

    private var summary: ViewingAnalyticsSummary {
        ViewingAnalyticsEngine.summarize(snapshot: model.snapshot, scope: scope)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                scope == .personal ? "No viewing history yet" : "Nothing watched together yet",
                systemImage: "chart.bar.xaxis"
            )
        } description: {
            Text(
                scope == .personal
                    ? "Mark a movie or episode watched and your analytics will start here."
                    : "Use Mark watched together on a shared title to build your joint history."
            )
        }
        .frame(minHeight: 420)
    }

    private var trackingNote: some View {
        Label(
            summary.includesEstimates
                ? "Imported progress is included as an estimate. New watches are measured from exact events."
                : "Calculated from your private on-device and iCloud watch history.",
            systemImage: summary.includesEstimates ? "approximately" : "lock.shield"
        )
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(
            summary.includesEstimates
                ? "Some imported viewing time is estimated"
                : "Calculated from private watch history"
        )
    }

    private func share() {
        guard let image = ViewingAnalyticsShareRenderer.render(summary: summary) else { return }
        sharePayload = ViewingAnalyticsSharePayload(text: summary.shareText, image: image)
    }
}

private struct AnalyticsHero: View {
    let summary: ViewingAnalyticsSummary

    var body: some View {
        GlassSurface(tint: summary.scope == .together ? .pink : .indigo) {
            VStack(alignment: .leading, spacing: 12) {
                Label(
                    summary.scope == .personal ? "Your screen time" : "Your time together",
                    systemImage: summary.scope == .personal ? "person.fill" : "person.2.fill"
                )
                .font(.headline)
                .foregroundStyle(.secondary)

                Text(summary.totalMinutes.analyticsDuration)
                    .font(.system(size: 50, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                Text(periodDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .accessibilityElement(children: .combine)
    }

    private var periodDescription: String {
        guard let start = summary.periodStart, let end = summary.periodEnd else {
            return "Tracked viewing history"
        }
        if Calendar.current.isDate(start, inSameDayAs: end) {
            return "Tracked on \(start.formatted(date: .abbreviated, time: .omitted))"
        }
        return "\(start.formatted(date: .abbreviated, time: .omitted)) – \(end.formatted(date: .abbreviated, time: .omitted))"
    }
}

private struct AnalyticsStatGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let summary: ViewingAnalyticsSummary

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            AnalyticsStatTile(value: summary.titleCount, label: "Titles", symbol: "rectangle.stack.fill")
            AnalyticsStatTile(value: summary.episodeCount, label: "Episodes", symbol: "play.square.stack.fill")
            AnalyticsStatTile(value: summary.movieCount, label: "Movies", symbol: "film.fill")
            AnalyticsStatTile(value: summary.seriesCount, label: "Series", symbol: "tv.fill")
        }
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible()),
            count: dynamicTypeSize.isAccessibilitySize ? 1 : 2
        )
    }
}

private struct AnalyticsStatTile: View {
    let value: Int
    let label: String
    let symbol: String

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(value, format: .number)
                        .font(.title2.bold())
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ViewingMixSection: View {
    let summary: ViewingAnalyticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Viewing mix", subtitle: "How your tracked time splits")
            GlassSurface {
                HStack(spacing: 22) {
                    Chart(summary.kindBreakdown) { metric in
                        SectorMark(
                            angle: .value("Minutes", metric.minutes),
                            innerRadius: .ratio(0.62),
                            angularInset: 2
                        )
                        .cornerRadius(5)
                        .foregroundStyle(by: .value("Type", metric.label))
                        .accessibilityLabel(metric.label)
                        .accessibilityValue(metric.minutes.analyticsDuration)
                    }
                    .chartLegend(.hidden)
                    .frame(width: 128, height: 128)
                    .accessibilityLabel("Viewing time by title type")

                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(summary.kindBreakdown) { metric in
                            AnalyticsLegendRow(metric: metric)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(18)
            }
        }
    }
}

private struct AnalyticsLegendRow: View {
    let metric: ViewingAnalyticsMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(metric.label)
                .font(.subheadline.weight(.semibold))
            Text(metric.minutes.analyticsDuration)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GenreHoursSection: View {
    let summary: ViewingAnalyticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Top genres", subtitle: "The stories getting most of your time")
            GlassSurface {
                Chart(Array(summary.genreBreakdown.prefix(5))) { metric in
                    BarMark(
                        x: .value("Minutes", metric.minutes),
                        y: .value("Genre", metric.label)
                    )
                    .foregroundStyle(Color.accentColor.gradient)
                    .cornerRadius(5)
                    .annotation(position: .trailing) {
                        Text(metric.minutes.analyticsShortDuration)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel(metric.label)
                    .accessibilityValue(metric.minutes.analyticsDuration)
                }
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks { value in
                        AxisValueLabel {
                            if let label = value.as(String.self) {
                                Text(label).font(.caption)
                            }
                        }
                    }
                }
                .frame(height: max(CGFloat(min(summary.genreBreakdown.count, 5)) * 46, 100))
                .padding(18)
                .accessibilityLabel("Top genres by viewing time")
            }
        }
    }
}

private struct ServiceHoursSection: View {
    let summary: ViewingAnalyticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Where you watched", subtitle: "Based on each title's available services")
            GlassSurface {
                VStack(spacing: 16) {
                    ForEach(summary.serviceBreakdown.prefix(5)) { metric in
                        MetricProgressRow(metric: metric, maximum: maximum)
                    }
                }
                .padding(18)
            }
        }
    }

    private var maximum: Int { summary.serviceBreakdown.first?.minutes ?? 1 }
}

private struct MemberHoursSection: View {
    let summary: ViewingAnalyticsSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Shared by", subtitle: "Time each person joined the session")
            GlassSurface {
                VStack(spacing: 16) {
                    ForEach(summary.memberBreakdown) { metric in
                        MetricProgressRow(metric: metric, maximum: max(summary.totalMinutes, 1))
                    }
                }
                .padding(18)
            }
        }
    }
}

private struct MetricProgressRow: View {
    let metric: ViewingAnalyticsMetric
    let maximum: Int

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text(metric.label)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(metric.minutes.analyticsDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(metric.minutes), total: Double(max(maximum, 1)))
                .tint(.accentColor)
        }
        .accessibilityElement(children: .combine)
    }
}

extension Int {
    fileprivate var analyticsDuration: String {
        let hours = self / 60
        let minutes = self % 60
        if hours == 0 { return "\(minutes) min" }
        if minutes == 0 { return "\(hours) hr" }
        return "\(hours) hr \(minutes) min"
    }

    fileprivate var analyticsShortDuration: String {
        guard self >= 60 else { return "\(self)m" }
        let hours = Double(self) / 60
        return "\(hours.formatted(.number.precision(.fractionLength(1))))h"
    }
}

#Preview {
    NavigationStack {
        ViewingAnalyticsView(scope: .personal)
            .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
    }
}
