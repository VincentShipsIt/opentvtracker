import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Binding var selectedTab: AppTab
    @State private var presentedSheet: TodaySheet?
    private let floatingChromeClearance = AppAccessibility.minimumTouchTarget * 2

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        if dynamicTypeSize.isAccessibilitySize {
                            TodayAccessibilityHeader(
                                greeting: greeting,
                                formattedDate: formattedDate
                            )
                        }

                        if let first = model.activeUpNext.first {
                            UpNextHero(title: first)
                        } else if let recommendation = model.recommendations.first {
                            // Full-bleed like the hero it stands in for, so no horizontal
                            // padding here — the banner insets its own content instead.
                            TodayRecommendationCard(
                                title: recommendation,
                                onAdd: { model.setWatchState(.planned, for: recommendation.id) },
                                onOpenDiscover: { selectedTab = .discover },
                                onHide: { model.setRecommendationDismissed(true, for: recommendation.id) }
                            )
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
                // The iOS 26 tab bar floats over the scroll viewport instead of consuming
                // its full height. At accessibility sizes its labelled controls become tall
                // enough to cover Today's progress and actions while they pass underneath.
                // Shrinking the actual viewport by two minimum touch targets reserves the
                // 83-point system bar plus separation; trailing scroll content alone would
                // still draw beneath it. Default-size layout and visual direction stay unchanged.
                .padding(
                    .bottom,
                    dynamicTypeSize.isAccessibilitySize ? floatingChromeClearance : 0
                )
                .scrollEdgeEffectStyle(
                    dynamicTypeSize.isAccessibilitySize ? .hard : .automatic,
                    for: .bottom
                )
                .accessibilityIdentifier("today.scroll")
            }
            .suspendsSpaceSwitchWhenCovered()
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
            // Default sizes keep the collapsible navigation treatment used throughout the
            // app. A system large title is single-line, though, so at accessibility sizes it
            // becomes a short stable screen title while the full greeting reflows in the
            // scroll content below.
            .navigationTitle(dynamicTypeSize.isAccessibilitySize ? "Today" : greeting)
            .navigationSubtitle(dynamicTypeSize.isAccessibilitySize ? "" : formattedDate)
            .navigationBarTitleDisplayMode(dynamicTypeSize.isAccessibilitySize ? .inline : .large)
            .spaceModeToolbar()
            .toolbar {
                TodayToolbar(
                    usesCompactPresentation: dynamicTypeSize.isAccessibilitySize,
                    onAskOpenTV: { presentedSheet = .assistant },
                    onOpenSettings: { presentedSheet = .settings }
                )
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .assistant:
                    DiscoveryAssistantView()
                case .services:
                    ServiceManagerView()
                case .settings:
                    AppSettingsView()
                }
            }
        }
    }

    private var formattedDate: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    private var greeting: String {
        let name = model.currentMember.name == "You" ? nil : model.currentMember.name
        let prefix: String
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: prefix = "Good morning"
        case 12..<18: prefix = "Good afternoon"
        default: prefix = "Good evening"
        }
        return name.map { "\(prefix), \($0)" } ?? prefix
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

                TodayResponsiveShelf {
                    ForEach(picks) { title in
                        NavigationLink(value: title) {
                            PosterShelfCard(title: title)
                                .frame(width: 144)
                        }
                        .buttonStyle(.plain)
                    }
                } accessibilityContent: {
                    ForEach(picks) { title in
                        NavigationLink(value: title) {
                            TodayAccessibilityShelfRow(
                                title: title,
                                detail: "\(title.displayYear) · \(title.kind.label) · \(title.runtimeMinutes) min"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.shelf-item.\(title.id)")
                    }
                }
            }
            // Grouped, not just identified. An identifier on a bare `VStack` never reaches
            // the accessibility tree, so the section could not be found by name — by VoiceOver
            // rotor or by the UI test that drags across this shelf to prove a sideways flick
            // scrolls it instead of switching spaces.
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Start watching")
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

                TodayResponsiveShelf {
                    ForEach(remaining) { title in
                        UpNextPosterCard(title: title)
                    }
                } accessibilityContent: {
                    ForEach(remaining) { title in
                        UpNextAccessibilityRow(title: title)
                    }
                }
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

                TodayResponsiveShelf {
                    ForEach(model.staleUpNext) { title in
                        UpNextPosterCard(
                            title: title,
                            subtitle: staleSubtitle(for: title)
                        )
                    }
                } accessibilityContent: {
                    ForEach(model.staleUpNext) { title in
                        UpNextAccessibilityRow(
                            title: title,
                            subtitle: staleSubtitle(for: title)
                        )
                    }
                }
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

                TodayResponsiveShelf {
                    ForEach(releases) { title in
                        NavigationLink(value: title) {
                            PosterShelfCard(title: title)
                                .frame(width: 144)
                        }
                        .buttonStyle(.plain)
                    }
                } accessibilityContent: {
                    ForEach(releases) { title in
                        NavigationLink(value: title) {
                            TodayAccessibilityShelfRow(
                                title: title,
                                detail: "\(title.displayYear) · \(title.kind.label) · \(title.runtimeMinutes) min"
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("today.shelf-item.\(title.id)")
                    }
                }
            }
        }
    }

    private func staleSubtitle(for title: MediaTitle) -> String {
        title.lastWatchedAt.map {
            "Last watched \($0.formatted(.relative(presentation: .named)))"
        } ?? "Ready when you are"
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                            Text("\(title.kind.label) · \(title.genres.prefix(2).joined(separator: " · ")) · \(title.runtimeMinutes) min")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.white)
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                            Text(progressSummary.label)
                                .font(.headline)
                                .foregroundStyle(.white)
                                .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.up-next-title")

                    ProgressView(value: progressSummary.fraction)
                        .tint(.white)
                        .accessibilityLabel("Viewing progress")
                        .accessibilityValue(progressSummary.label)
                        .accessibilityIdentifier("today.hero-progress")

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 10) {
                            heroActionButtons
                        }
                    } else {
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
        .accessibilityIdentifier("today.hero-mark-watched")

        QueueActionsMenu(
            title: title,
            includesProgressAction: false,
            displaysLabel: dynamicTypeSize.isAccessibilitySize
        )
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

private struct UpNextAccessibilityRow: View {
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

private struct QueueActionsMenu: View {
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

#Preview {
    TodayView(selectedTab: .constant(.today))
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
