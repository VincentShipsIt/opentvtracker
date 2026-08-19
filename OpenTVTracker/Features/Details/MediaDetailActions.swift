import SwiftUI

enum MediaDetailPrimaryAction: Equatable {
    case advanceProgress
    case editActivity

    init(state: WatchState) {
        self = state.isCurrentViewingComplete ? .editActivity : .advanceProgress
    }
}

struct MediaDetailActions: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    @Binding var presentedTrailer: TrailerPresentation?
    @Binding var listPickerTitle: MediaTitle?
    @Binding var presentsMoreLikeThis: Bool
    @Binding var showsTrackingEditor: Bool
    @Binding var showsSharedNoteEditor: Bool
    @Binding var showsReminderEditor: Bool
    @Binding var showsPartnerInvitation: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            primaryButton
            secondaryActions
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Actions for \(title.title)")
    }

    private var primaryButton: some View {
        Button(action: performPrimaryAction) {
            Label(primaryActionLabel, systemImage: primaryActionSymbol)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .adaptiveGlassButton(prominent: true)
        .accessibilityHint(primaryActionHint)
        .accessibilityIdentifier("details.primary-action")
    }

    @ViewBuilder
    private var trailerAction: some View {
        if let sourceURL = title.trailerURL,
           let trailer = TrailerPresentation(title: title.title, sourceURL: sourceURL) {
            Button {
                presentedTrailer = trailer
            } label: {
                compactLabel("Trailer", systemImage: "play.fill")
            }
            .adaptiveGlassButton()
            .accessibilityHint("Plays the trailer in OpenTV")
        } else if let sourceURL = title.trailerURL,
                  let externalURL = TrailerURLNormalizer.safeExternalURL(sourceURL) {
            Link(destination: externalURL) {
                compactLabel("Trailer", systemImage: "arrow.up.right.square")
            }
            .adaptiveGlassButton()
            .accessibilityHint("Opens the trailer externally")
        } else if title.trailerURL != nil {
            compactLabel("Unavailable", systemImage: "play.slash.fill")
                .foregroundStyle(.secondary)
                .accessibilityLabel("Trailer unavailable")
        }
    }

    private var watchlistButton: some View {
        Button {
            model.toggleWatchlist(title.id)
        } label: {
            compactLabel(
                "My list",
                systemImage: title.isOnPersonalWatchlist ? "bookmark.fill" : "bookmark"
            )
        }
        .adaptiveGlassButton()
        .accessibilityLabel("My watchlist")
        .accessibilityValue(title.isOnPersonalWatchlist ? "Added" : "Not added")
        .accessibilityHint("Adds or removes this title without changing your viewing progress")
    }

    @ViewBuilder
    private var secondaryActions: some View {
        if shouldPromoteActivity {
            ViewThatFits(in: .horizontal) {
                compactActionRow(includesActivity: true)
                VStack(alignment: .leading, spacing: 10) {
                    activityButton(style: .fullWidth)
                    compactActionRow(includesActivity: false)
                }
            }
        } else {
            compactActionRow(includesActivity: false)
        }
    }

    private func compactActionRow(includesActivity: Bool) -> some View {
        HStack(spacing: 8) {
            trailerAction
            if includesActivity {
                activityButton(style: .compact)
            }
            watchlistButton
            togetherButton
            overflowMenu
        }
        .controlSize(.small)
    }

    private func activityButton(style: ActivityButtonStyle) -> some View {
        Button {
            showsTrackingEditor = true
        } label: {
            switch style {
            case .compact:
                compactLabel("Activity", systemImage: "checkmark.rectangle.stack")
            case .fullWidth:
                Label("Activity", systemImage: "checkmark.rectangle.stack")
                    .frame(maxWidth: .infinity)
            }
        }
        .controlSize(style == .fullWidth ? .large : .small)
        .adaptiveGlassButton()
        .accessibilityHint("Opens status, ratings, watch dates, and private notes")
        .accessibilityIdentifier("details.activity-action")
        .minimumTouchTarget()
    }

    private var togetherButton: some View {
        Button {
            performTogetherAction()
        } label: {
            compactLabel(
                "Our list",
                systemImage: model.isShared(title.id) ? "person.2.fill" : "person.2"
            )
        }
        .adaptiveGlassButton()
        .accessibilityLabel("Our watchlist")
        .accessibilityValue(model.isShared(title.id) ? "Added" : "Not added")
        .accessibilityHint(togetherHint)
    }

    private var overflowMenu: some View {
        Menu {
            // Only offered while it would change something, so it never reads as a no-op on a
            // show that is already fully tracked.
            if model.hasUnwatchedReleasedEpisodes(for: title) {
                Button("Mark whole show watched", systemImage: "checkmark.seal.fill") {
                    model.markWatched(title.id)
                }
                .accessibilityIdentifier("details.mark-show-watched")
                .accessibilityHint("Marks every aired episode of every season watched")

                Divider()
            }

            Button("More like this", systemImage: "sparkles") {
                presentsMoreLikeThis = true
            }

            if !shouldPromoteActivity {
                Button("Activity and private note", systemImage: "checkmark.rectangle.stack") {
                    showsTrackingEditor = true
                }
            }

            Button("Add to custom list", systemImage: "list.bullet.rectangle") {
                listPickerTitle = title
            }

            Button(reminderLabel, systemImage: reminderSymbol) {
                showsReminderEditor = true
            }
            .disabled(!title.isReminderEligible)

            if model.togetherConnectionPhase == .connected, model.isShared(title.id) {
                Divider()

                Button("Mark watched together", systemImage: "person.2.fill") {
                    model.markWatchedTogether(title.id)
                }

                Button("Add shared note", systemImage: "note.text.badge.plus") {
                    showsSharedNoteEditor = true
                }
            }
        } label: {
            compactLabel("More", systemImage: "ellipsis.circle")
        }
        .adaptiveGlassButton()
        .accessibilityLabel("More actions for \(title.title)")
        .accessibilityHint(overflowHint)
    }

    private var primaryAction: MediaDetailPrimaryAction {
        MediaDetailPrimaryAction(state: title.state)
    }

    private var primaryActionLabel: String {
        switch primaryAction {
        case .advanceProgress:
            title.kind == .movie ? "Mark watched" : "Mark next watched"
        case .editActivity:
            "Edit activity"
        }
    }

    private var primaryActionSymbol: String {
        switch primaryAction {
        case .advanceProgress: "checkmark.circle.fill"
        case .editActivity: "checkmark.rectangle.stack.fill"
        }
    }

    private var primaryActionHint: String {
        switch primaryAction {
        case .advanceProgress:
            title.kind == .movie
                ? "Adds this movie to your viewing history"
                : "Marks the next unwatched episode and updates your progress"
        case .editActivity:
            "Opens status, ratings, watch dates, and private notes"
        }
    }

    private var shouldPromoteActivity: Bool {
        title.state != .planned
    }

    private var hasAcceptedPartner: Bool {
        model.togetherConnectionPhase == .connected
    }

    private var togetherHint: String {
        if hasAcceptedPartner || model.isShared(title.id) {
            return "Adds or removes this title from the watchlist you share"
        }
        return "Opens the partner invitation before adding this title to Our list"
    }

    private var overflowHint: String {
        shouldPromoteActivity
            ? "Marks the whole show watched, and shows recommendations, lists, reminders, and shared actions"
            : "Marks the whole show watched, and shows recommendations, activity, notes, lists, reminders, and shared actions"
    }

    private var reminderLabel: String {
        model.isReminderEnabled(for: title.id) ? "Edit reminder" : "Set reminder"
    }

    private var reminderSymbol: String {
        model.isReminderEnabled(for: title.id) ? "bell.fill" : "bell"
    }

    private func compactLabel(_ label: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.body)
            Text(label)
                .font(.caption2.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
    }

    private func performPrimaryAction() {
        switch primaryAction {
        case .advanceProgress:
            model.markNextWatched(title.id)
        case .editActivity:
            showsTrackingEditor = true
        }
    }

    private func performTogetherAction() {
        if hasAcceptedPartner || model.isShared(title.id) {
            model.toggleTogether(title.id)
        } else {
            showsPartnerInvitation = true
        }
    }
}

private enum ActivityButtonStyle {
    case compact
    case fullWidth
}
