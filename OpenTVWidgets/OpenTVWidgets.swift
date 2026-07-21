import SwiftUI
import WidgetKit

private struct OpenTVWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: OpenTVWidgetSnapshot
}

private struct OpenTVWidgetProvider: TimelineProvider {
    func placeholder(in _: Context) -> OpenTVWidgetEntry {
        OpenTVWidgetEntry(
            date: .now,
            snapshot: OpenTVWidgetSnapshot(
                generatedAt: .now,
                upNext: OpenTVWidgetItem(
                    id: "placeholder",
                    title: "Your next show",
                    detail: "Ready to watch",
                    date: nil,
                    symbol: "play.circle.fill"
                ),
                upcoming: []
            )
        )
    }

    func getSnapshot(in _: Context, completion: @escaping (OpenTVWidgetEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in _: Context, completion: @escaping (Timeline<OpenTVWidgetEntry>) -> Void) {
        let entry = entry()
        let refreshDate = Calendar.current.date(byAdding: .minute, value: 30, to: entry.date)
            ?? entry.date.addingTimeInterval(1_800)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func entry() -> OpenTVWidgetEntry {
        OpenTVWidgetEntry(
            date: .now,
            snapshot: OpenTVWidgetSnapshotStore.load() ?? .empty
        )
    }
}

@main
struct OpenTVWidgetsBundle: WidgetBundle {
    var body: some Widget {
        UpNextWidget()
        UpcomingReleasesWidget()
    }
}

private struct UpNextWidget: Widget {
    let kind = "OpenTVUpNext"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OpenTVWidgetProvider()) { entry in
            UpNextWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Up Next")
        .description("See the next title in your personal OpenTV queue.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private struct UpcomingReleasesWidget: Widget {
    let kind = "OpenTVUpcoming"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: OpenTVWidgetProvider()) { entry in
            UpcomingWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color.clear
                }
        }
        .configurationDisplayName("Upcoming")
        .description("Keep the next tracked episode or release on your Home or Lock Screen.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

private struct UpNextWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OpenTVWidgetEntry

    var body: some View {
        if let item = entry.snapshot.upNext {
            content(item)
        } else {
            emptyContent(title: "Queue clear", symbol: "checkmark.circle")
        }
    }

    @ViewBuilder
    private func content(_ item: OpenTVWidgetItem) -> some View {
        switch family {
        case .accessoryInline:
            Label(item.title, systemImage: item.symbol)
        case .accessoryCircular:
            Image(systemName: item.symbol)
                .font(.title2)
                .accessibilityLabel("Up next: \(item.title)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text("UP NEXT")
                    .font(.caption2.weight(.bold))
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(item.detail)
                    .font(.caption)
                    .lineLimit(1)
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Label("Up Next", systemImage: item.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                Text(item.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private func emptyContent(title: String, symbol: String) -> some View {
        switch family {
        case .accessoryInline:
            Label(title, systemImage: symbol)
        case .accessoryCircular:
            Image(systemName: symbol)
                .accessibilityLabel(title)
        default:
            ContentUnavailableView(title, systemImage: symbol)
        }
    }
}

private struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: OpenTVWidgetEntry

    var body: some View {
        if let item = entry.snapshot.upcoming.first {
            content(item)
        } else {
            emptyContent
        }
    }

    @ViewBuilder
    private func content(_ item: OpenTVWidgetItem) -> some View {
        switch family {
        case .accessoryInline:
            if let date = item.date {
                Text("\(Image(systemName: item.symbol)) \(item.title) \(date, style: .relative)")
            } else {
                Label(item.title, systemImage: item.symbol)
            }
        case .accessoryCircular:
            Image(systemName: item.symbol)
                .font(.title2)
                .accessibilityLabel("Upcoming: \(item.title)")
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 2) {
                Text(item.detail.uppercased())
                    .font(.caption2.weight(.bold))
                Text(item.title)
                    .font(.headline)
                    .lineLimit(1)
                if let date = item.date {
                    Text(date, style: .relative)
                        .font(.caption)
                }
            }
        default:
            VStack(alignment: .leading, spacing: 8) {
                Label("Upcoming", systemImage: item.symbol)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(item.title)
                    .font(.title3.weight(.bold))
                    .lineLimit(2)
                if let date = item.date {
                    Text(date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var emptyContent: some View {
        switch family {
        case .accessoryInline:
            Label("Nothing scheduled", systemImage: "calendar")
        case .accessoryCircular:
            Image(systemName: "calendar")
                .accessibilityLabel("Nothing scheduled")
        default:
            ContentUnavailableView("Nothing scheduled", systemImage: "calendar")
        }
    }
}
