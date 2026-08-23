import SwiftUI

/// The system navigation title stays collapsible at ordinary sizes, but it cannot wrap.
/// Accessibility sizes get this scroll-owned counterpart so the full greeting and date
/// participate in layout instead of truncating inside a single-line bar title.
struct TodayAccessibilityHeader: View {
    let greeting: String
    let formattedDate: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(greeting)
                .font(.largeTitle.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("today.greeting")

            Text(formattedDate)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("today.date")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 8)
    }
}

/// Keeps Today's three ordinary-size actions visible while collapsing the same semantic
/// controls into one reachable menu when accessibility text leaves no inline title room.
struct TodayToolbar: ToolbarContent {
    let usesCompactPresentation: Bool
    let onAskOpenTV: () -> Void
    let onOpenSettings: () -> Void

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if usesCompactPresentation {
                Menu {
                    upcomingCalendarLink
                    askOpenTVButton
                    settingsButton
                } label: {
                    Label("Today actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .tint(Color.primary)
                .accessibilityHint("Shows calendar, suggestions, and settings actions")
                .accessibilityIdentifier("today.actions")
            } else {
                upcomingCalendarLink
                askOpenTVButton
                settingsButton
            }
        }
    }

    private var upcomingCalendarLink: some View {
        NavigationLink {
            UpcomingCalendarView()
        } label: {
            Label("Upcoming calendar", systemImage: "calendar")
        }
        .tint(Color.primary)
        .accessibilityHint("Shows upcoming episodes and movie releases")
        .accessibilityIdentifier("home.upcoming-calendar")
    }

    private var askOpenTVButton: some View {
        Button("Ask OpenTV", systemImage: "sparkles", action: onAskOpenTV)
            .tint(Color.primary)
            .accessibilityHint("Opens personalized viewing suggestions")
            .accessibilityIdentifier("today.ask-opentv")
    }

    private var settingsButton: some View {
        // Same glyph, same meaning on Today, Discover, and Library. At accessibility
        // sizes it moves into Today's labelled actions menu instead of disappearing.
        Button("Profile and settings", systemImage: "person.crop.circle", action: onOpenSettings)
            .tint(Color.primary)
            .accessibilityHint("Opens your private profile, app settings, and backup status")
            .accessibilityIdentifier("today.settings")
    }
}
