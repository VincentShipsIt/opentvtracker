import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedTab: AppTab
    @State private var presentedSheet: TodaySheet?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        TodayHeader(memberName: model.currentMember.name)

                        if let first = model.activeUpNext.first {
                            UpNextHero(title: first)
                        } else if let recommendation = model.recommendations.first {
                            TodayRecommendationCard(
                                title: recommendation,
                                onAdd: { model.setWatchState(.planned, for: recommendation.id) },
                                onOpenDiscover: { selectedTab = .discover }
                            )
                            .padding(.horizontal, AppTheme.horizontalPadding)
                        } else {
                            TodayRecoveryCard(
                                hasSelectedServices: !model.selectedProviderIDs.isEmpty,
                                catalogError: model.catalogSearchError,
                                onManageServices: { presentedSheet = .services },
                                onOpenDiscover: { selectedTab = .discover }
                            )
                            .padding(.horizontal, AppTheme.horizontalPadding)
                        }

                        remainingQueue
                        staleQueue
                        newReleases
                        catalogShelf
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
            .spaceModeToolbar()
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        UpcomingCalendarView()
                    } label: {
                        Label("Upcoming calendar", systemImage: "calendar")
                    }
                    .accessibilityHint("Shows upcoming episodes and movie releases")
                    .accessibilityIdentifier("home.upcoming-calendar")

                    Button("Ask OpenTV", systemImage: "sparkles") {
                        presentedSheet = .assistant
                    }
                    .accessibilityHint("Opens personalized viewing suggestions")
                    .accessibilityIdentifier("today.ask-opentv")

                    // Same glyph, same corner, same meaning on Today, Discover, and
                    // Library. It used to switch to the Library tab here and open
                    // settings there, which is exactly the inconsistency it looked like.
                    Button("Profile and settings", systemImage: "person.crop.circle") {
                        presentedSheet = .settings
                    }
                    .accessibilityHint("Opens your private profile, app settings, and backup status")
                    .accessibilityIdentifier("today.settings")
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .assistant:
                    DiscoveryAssistantView()
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                case .services:
                    ServiceManagerView()
                case .settings:
                    AppSettingsView()
                }
            }
        }
    }

    /// The list of things to watch, which Today used to be missing entirely.
    ///
    /// Everything above this point is drawn from the queue or from `recommendations`,
    /// and both are empty on a new library — so the home screen was one card and a wall
    /// of black. This is the browse pool: catalog titles the user has not tracked,
    /// ordered so selected services come first. It sits below the personal shelves
    /// because it is the least personal thing here, and on a full library that is
    /// exactly where it should be.
    @ViewBuilder
    private var catalogShelf: some View {
        let picks = model.browsableCatalogTitles(limit: 24, excluding: shownTitleIDs)
        if !picks.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(
                    title: "Start watching",
                    subtitle: "Highly rated titles you haven't tracked yet"
                )
                .padding(.horizontal, AppTheme.horizontalPadding)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(picks) { title in
                            NavigationLink(value: title) {
                                PosterShelfCard(title: title)
                                    .frame(width: 144)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
            .accessibilityIdentifier("today.start-watching")
        }
    }

    /// Titles already on screen above the browse shelf, so it never repeats one.
    private var shownTitleIDs: Set<MediaTitle.ID> {
        var identifiers = Set(model.activeUpNext.map(\.id))
        identifiers.formUnion(model.staleUpNext.map(\.id))
        identifiers.formUnion(model.newReleasesOnSelectedProviders().map(\.id))
        if let recommendation = model.recommendations.first {
            identifiers.insert(recommendation.id)
        }
        return identifiers
    }

    @ViewBuilder
    private var remainingQueue: some View {
        let remaining = Array(model.activeUpNext.dropFirst())
        if !remaining.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Also up next", subtitle: "Small commitments, ready when you are")
                    .padding(.horizontal, AppTheme.horizontalPadding)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(remaining) { title in
                            UpNextPosterCard(title: title)
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var staleQueue: some View {
        if !model.staleUpNext.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(
                    title: "Haven't watched in a while",
                    subtitle: "Resume, snooze, or drop these without losing your place"
                )
                .padding(.horizontal, AppTheme.horizontalPadding)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(model.staleUpNext) { title in
                            UpNextPosterCard(
                                title: title,
                                subtitle: title.lastWatchedAt.map {
                                    "Last watched \($0.formatted(.relative(presentation: .named)))"
                                } ?? "Ready when you are"
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private var newReleases: some View {
        let releases = model.newReleasesOnSelectedProviders()
        if !releases.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(
                    title: "New on your services",
                    subtitle: "Released in the last two weeks"
                )
                .padding(.horizontal, AppTheme.horizontalPadding)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(releases) { title in
                            NavigationLink(value: title) {
                                PosterShelfCard(title: title)
                                    .frame(width: 144)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

}

private enum TodaySheet: Hashable, Identifiable {
    case assistant
    case services
    case settings

    var id: Self { self }
}

private struct UpNextHero: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    @State private var progressTrigger = 0

    private var progressSummary: MediaProgressSummary {
        model.progressSummary(for: title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Up next", subtitle: title.nextReleaseDescription)
                .padding(.horizontal, AppTheme.horizontalPadding)

            AdaptiveHeroSurface(
                minimumHeight: 430,
                cornerRadius: 0,
                contentInsets: EdgeInsets(
                    top: 24,
                    leading: AppTheme.horizontalPadding,
                    bottom: 24,
                    trailing: AppTheme.horizontalPadding
                )
            ) {
                BackdropArtwork(title: title, cornerRadius: 0)
                    .accessibilityHidden(true)
            } content: {
                VStack(alignment: .leading, spacing: 13) {
                    NavigationLink(value: title) {
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title.title)
                                .font(.largeTitle.weight(.black))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text("\(title.kind.label) · \(title.genres.prefix(2).joined(separator: " · ")) · \(title.runtimeMinutes) min")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(progressSummary.label)
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.up-next-title")

                    ProgressView(value: progressSummary.fraction)
                        .tint(.white)
                        .accessibilityLabel("Viewing progress")
                        .accessibilityValue(progressSummary.label)

                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 10) {
                            heroActionButtons
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            heroActionButtons
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var heroActionButtons: some View {
        Button {
            model.markNextWatched(title.id)
            progressTrigger += 1
        } label: {
            Label(watchedActionTitle, systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .tint(.white)
        .foregroundStyle(.black)
        .sensoryFeedback(.success, trigger: progressTrigger)

        QueueActionsMenu(title: title)
            .controlSize(.large)
            .buttonStyle(.bordered)
            .tint(.white)
    }

    private var watchedActionTitle: String {
        title.kind == .movie ? "Mark watched" : "Mark next episode watched"
    }
}

private struct UpNextPosterCard: View {
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

private struct QueueActionsMenu: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle

    var body: some View {
        Menu {
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
        } label: {
            Label("Queue actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .accessibilityLabel("Queue actions for \(title.title)")
        .minimumTouchTarget()
    }

    private var snoozeDate: Date {
        Calendar.current.date(byAdding: .day, value: 7, to: .now) ?? .now
    }
}

#Preview {
    TodayView(selectedTab: .constant(.today))
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
