import SwiftUI

struct MediaDetailWatchlistActions: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle

    var body: some View {
        HStack(spacing: 10) {
            Button {
                model.toggleWatchlist(title.id)
            } label: {
                Label(
                    "My watchlist",
                    systemImage: title.isOnPersonalWatchlist ? "bookmark.fill" : "bookmark"
                )
                .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
            .accessibilityValue(title.isOnPersonalWatchlist ? "Added" : "Not added")
            .accessibilityHint("Adds or removes this title without changing your viewing progress")

            Button {
                model.toggleTogether(title.id)
            } label: {
                Label(
                    "Our watchlist",
                    systemImage: model.isShared(title.id) ? "person.2.fill" : "person.2"
                )
                .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
            .accessibilityValue(model.isShared(title.id) ? "Added" : "Not added")
            .accessibilityHint("Adds or removes this title from the watchlist you share")
        }
    }
}

struct MediaDetailReminderAction: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    @Binding var showsReminderEditor: Bool

    var body: some View {
        Button {
            showsReminderEditor = true
        } label: {
            Label(
                model.isReminderEnabled(for: title.id) ? "Reminder on" : "Set reminder",
                systemImage: model.isReminderEnabled(for: title.id) ? "bell.fill" : "bell"
            )
            .frame(maxWidth: .infinity)
        }
        .adaptiveGlassButton()
        .accessibilityValue(model.isReminderEnabled(for: title.id) ? "Enabled" : "Disabled")
        .accessibilityHint("Configures a spoiler-safe local notification for this title")
    }
}
