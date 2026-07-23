import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Binding var selectedTab: AppTab
    @State private var presentsAssistant = false
    @State private var presentedSheet: TodaySheet?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        TodayHeader(
                            memberName: model.currentMember.name,
                            onOpenLibrary: { selectedTab = .library }
                        )

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
                        partnerActivity
                    }
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
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
                        presentsAssistant = true
                    }
                    .accessibilityHint("Opens personalized viewing suggestions")
                    .accessibilityIdentifier("today.ask-opentv")
                }
            }
            .fullScreenCover(isPresented: $presentsAssistant) {
                DiscoveryAssistantView()
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .services:
                    ServiceManagerView()
                }
            }
        }
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

    @ViewBuilder
    private var partnerActivity: some View {
        if !model.togetherActivity.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Together", subtitle: "Latest from \(model.sharedSpace.name)")
                VStack(spacing: 12) {
                    ForEach(model.togetherActivity.prefix(2)) { activity in
                        ActivityCard(
                            activity: activity,
                            space: model.sharedSpace,
                            title: model.mediaTitle(for: activity)
                        )
                    }
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
        }
    }

}

private enum TodaySheet: Hashable, Identifiable {
    case services

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

            GeometryReader { geometry in
                ZStack(alignment: .bottomLeading) {
                    BackdropArtwork(title: title, cornerRadius: 0)
                        .frame(width: geometry.size.width, height: geometry.size.height)

                    LinearGradient(
                        colors: [.clear, .black.opacity(0.28), .black.opacity(0.96)],
                        startPoint: .top,
                        endPoint: .bottom
                    )

                    VStack(alignment: .leading, spacing: 13) {
                        NavigationLink(value: title) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(title.title)
                                    .font(.largeTitle.weight(.black))
                                    .foregroundStyle(.white)
                                    .lineLimit(2)
                                Text("\(title.kind.label) · \(title.genres.prefix(2).joined(separator: " · ")) · \(title.runtimeMinutes) min")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.white.opacity(0.82))
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

                        HStack(spacing: 10) {
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
                    }
                    .frame(width: max(geometry.size.width - (AppTheme.horizontalPadding * 2), 0))
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 24)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
            }
            .frame(height: 430)
        }
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
