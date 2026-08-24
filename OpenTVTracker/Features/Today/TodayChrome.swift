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

/// Today's poster shelves stay horizontally browsable at ordinary text sizes, but a
/// carousel of narrow fixed-width cards is not a readable AX layout. Accessibility sizes
/// use full-width rows in the parent vertical scroll view instead, so every title and
/// control gets the device width and normal vertical scrolling semantics.
struct TodayResponsiveShelf<RegularContent: View, AccessibilityContent: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let regularContent: RegularContent
    private let accessibilityContent: AccessibilityContent

    init(
        @ViewBuilder regularContent: () -> RegularContent,
        @ViewBuilder accessibilityContent: () -> AccessibilityContent
    ) {
        self.regularContent = regularContent()
        self.accessibilityContent = accessibilityContent()
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            LazyVStack(spacing: 12) {
                accessibilityContent
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
        } else {
            HorizontalShelf {
                LazyHStack(alignment: .top, spacing: 14) {
                    regularContent
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.bottom, 4)
            }
        }
    }
}

/// A full-width alternative to Today's poster cards. It deliberately has no title line
/// limit and caps its scaled artwork so AX5 copy receives most of the available width.
struct TodayAccessibilityShelfRow: View {
    @ScaledMetric(relativeTo: .body) private var scaledPosterWidth: CGFloat = 64
    let title: MediaTitle
    let detail: String
    var progress: MediaProgressSummary?

    private var posterWidth: CGFloat {
        min(scaledPosterWidth, 96)
    }

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: Color(hex: title.palette.primaryHex)) {
            HStack(alignment: .top, spacing: 14) {
                PosterArtwork(title: title, cornerRadius: 10)
                    .frame(width: posterWidth)
                    .aspectRatio(AppTheme.posterAspectRatio, contentMode: .fit)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(title.title)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let progress {
                        Text(progress.label)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.tint)
                            .fixedSize(horizontal: false, vertical: true)

                        ProgressView(value: progress.fraction)
                            .accessibilityLabel("Viewing progress")
                            .accessibilityValue(progress.label)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(12)
        }
        .accessibilityElement(children: .combine)
    }
}
