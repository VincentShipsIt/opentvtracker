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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            primaryButton

            HStack(spacing: 8) {
                trailerAction
                watchlistButton
                togetherButton
                overflowMenu
            }
            .controlSize(.small)
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

    private var togetherButton: some View {
        Button {
            model.toggleTogether(title.id)
        } label: {
            compactLabel(
                "Our list",
                systemImage: model.isShared(title.id) ? "person.2.fill" : "person.2"
            )
        }
        .adaptiveGlassButton()
        .accessibilityLabel("Our watchlist")
        .accessibilityValue(model.isShared(title.id) ? "Added" : "Not added")
        .accessibilityHint("Adds or removes this title from the watchlist you share")
    }

    private var overflowMenu: some View {
        Menu {
            Button("More like this", systemImage: "sparkles") {
                presentsMoreLikeThis = true
            }

            Button("Activity and private note", systemImage: "checkmark.rectangle.stack") {
                showsTrackingEditor = true
            }

            Button("Add to custom list", systemImage: "list.bullet.rectangle") {
                listPickerTitle = title
            }

            Button(reminderLabel, systemImage: reminderSymbol) {
                showsReminderEditor = true
            }
            .disabled(!title.isReminderEligible)

            if model.isShared(title.id) {
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
        .accessibilityHint("Shows recommendations, activity, notes, lists, reminders, and shared actions")
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
}
