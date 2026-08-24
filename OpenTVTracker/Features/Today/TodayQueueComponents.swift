import SwiftUI

struct UpNextPosterCard: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: title) {
                MediaProgressPosterCard(
                    title: title,
                    summary: model.progressSummary(for: title),
                    subtitle: subtitle ?? title.nextReleaseDescription
                )
            }
            .buttonStyle(.plain)

            QueueActionsMenu(title: title)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(width: 144)
    }
}

struct UpNextAccessibilityRow: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink(value: title) {
                TodayAccessibilityShelfRow(
                    title: title,
                    detail: subtitle ?? title.nextReleaseDescription ?? "Ready when you are",
                    progress: model.progressSummary(for: title)
                )
            }
            .buttonStyle(.plain)

            QueueActionsMenu(title: title, displaysLabel: true)
                .controlSize(.large)
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .accessibilityIdentifier("today.shelf-item.\(title.id)")
    }
}

struct QueueActionsMenu: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    var includesProgressAction = true
    var displaysLabel = false
    @State private var progressTrigger = 0

    var body: some View {
        Menu {
            if includesProgressAction, let progressAction {
                Button {
                    model.markNextWatched(title.id)
                    progressTrigger += 1
                } label: {
                    Label(progressAction.label, systemImage: "checkmark.circle.fill")
                }
                .accessibilityIdentifier("today.queue-mark-watched")
            }

            Button {
                model.setUpNextPinned(title.isUpNextPinned != true, for: title.id)
            } label: {
                Label(
                    title.isUpNextPinned == true ? "Unpin" : "Pin to top",
                    systemImage: title.isUpNextPinned == true ? "pin.slash" : "pin"
                )
            }

            if title.isSnoozed(at: .now) {
                Button {
                    model.snoozeUpNext(title.id, until: nil)
                } label: {
                    Label("Bring back now", systemImage: "arrow.uturn.backward")
                }
            } else {
                Button {
                    model.snoozeUpNext(title.id, until: snoozeDate)
                } label: {
                    Label("Snooze for one week", systemImage: "clock.badge")
                }
            }

            Button {
                model.moveUpNextLower(title.id)
            } label: {
                Label("Move lower", systemImage: "arrow.down")
            }

            if title.kind == .series {
                Button {
                    model.setWatchState(.dropped, for: title.id)
                } label: {
                    Label("Mark dropped", systemImage: "xmark.circle")
                }
            }
        } label: { menuLabel }
        .accessibilityLabel("Queue actions for \(title.title)")
        .accessibilityIdentifier("today.queue-actions.\(title.id)")
        .minimumTouchTarget()
        .sensoryFeedback(.success, trigger: progressTrigger)
    }

    @ViewBuilder
    private var menuLabel: some View {
        if displaysLabel {
            Label("Queue actions", systemImage: "ellipsis.circle")
                .frame(maxWidth: .infinity)
        } else {
            Label("Queue actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
    }

    private var progressAction: QueueProgressAction? {
        QueueProgressAction(
            title: title,
            hasUnwatchedReleasedEpisodes: model.hasUnwatchedReleasedEpisodes(for: title)
        )
    }

    private var snoozeDate: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    }
}

enum QueueProgressAction: Equatable {
    case markNextEpisode
    case markMovieWatched

    init?(title: MediaTitle, hasUnwatchedReleasedEpisodes: Bool) {
        switch title.kind {
        case .series:
            guard hasUnwatchedReleasedEpisodes else { return nil }
            self = .markNextEpisode
        case .movie:
            guard !title.state.isCurrentViewingComplete else { return nil }
            self = .markMovieWatched
        }
    }

    var label: String {
        switch self {
        case .markNextEpisode: "Mark next episode watched"
        case .markMovieWatched: "Mark watched"
        }
    }
}
