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
                            memberName: currentMember.name,
                            onOpenProfile: { presentedSheet = .profile }
                        )

                        if let first = model.upNext.first {
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
                ToolbarItem(placement: .topBarTrailing) {
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
                case .profile:
                    ProfileView()
                case .services:
                    ServiceManagerView()
                }
            }
        }
    }

    @ViewBuilder
    private var remainingQueue: some View {
        let remaining = Array(model.upNext.dropFirst())
        if !remaining.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Also up next", subtitle: "Small commitments, ready when you are")
                    .padding(.horizontal, AppTheme.horizontalPadding)

                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(remaining) { title in
                            NavigationLink(value: title) {
                                MediaProgressPosterCard(
                                    title: title,
                                    summary: model.progressSummary(for: title),
                                    subtitle: title.nextReleaseDescription
                                )
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

    private var currentMember: SpaceMember {
        model.sharedSpace.members.first(where: \.isCurrentUser)
            ?? SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: true)
    }
}

private enum TodaySheet: Hashable, Identifiable {
    case profile
    case services

    var id: Self { self }
}

private struct TodayHeader: View {
    let memberName: String
    let onOpenProfile: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting)
                    .font(.largeTitle.weight(.bold))
                Text(.now, format: .dateTime.weekday(.wide).month(.wide).day())
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(action: onOpenProfile) {
                Label("Open profile", systemImage: "person.crop.circle.fill")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 34))
            }
            .accessibilityHint("Opens your private profile and settings")
            .accessibilityIdentifier("today.profile")
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
        .padding(.top, 12)
    }

    private var greeting: String {
        let name = memberName == "You" ? nil : memberName
        let prefix: String
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: prefix = "Good morning"
        case 12..<18: prefix = "Good afternoon"
        default: prefix = "Good evening"
        }
        return name.map { "\(prefix), \($0)" } ?? prefix
    }
}

private struct TodayRecommendationCard: View {
    let title: MediaTitle
    let onAdd: () -> Void
    let onOpenDiscover: () -> Void

    var body: some View {
        GlassSurface(tint: .indigo) {
            VStack(alignment: .leading, spacing: 14) {
                Label("A pick for tonight", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundStyle(.indigo)

                NavigationLink(value: title) {
                    HStack(spacing: 14) {
                        PosterArtwork(title: title, cornerRadius: 10)
                            .frame(width: 72, height: 108)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title.title)
                                .font(.title2.weight(.bold))
                                .foregroundStyle(.primary)
                            Text(title.recommendationReason ?? "A strong match on one of your selected services.")
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                    }
                }
                .buttonStyle(.plain)

                HStack {
                    Button("Add to watchlist", systemImage: "plus") {
                        onAdd()
                    }
                    .adaptiveGlassButton(prominent: true)

                    Button("Explore Discover", systemImage: "magnifyingglass") {
                        onOpenDiscover()
                    }
                    .adaptiveGlassButton()
                }
            }
            .padding(18)
        }
        .accessibilityIdentifier("today.recommendation")
    }
}

private struct TodayRecoveryCard: View {
    let hasSelectedServices: Bool
    let catalogError: String?
    let onManageServices: () -> Void
    let onOpenDiscover: () -> Void

    var body: some View {
        GlassSurface(tint: .orange) {
            VStack(spacing: 14) {
                ContentUnavailableView(
                    title,
                    systemImage: "sparkles.tv",
                    description: Text(description)
                )

                HStack {
                    Button("Manage services", systemImage: "slider.horizontal.3", action: onManageServices)
                        .adaptiveGlassButton(prominent: !hasSelectedServices)
                    Button("Open Discover", systemImage: "magnifyingglass", action: onOpenDiscover)
                        .adaptiveGlassButton(prominent: hasSelectedServices)
                }
            }
            .padding(.vertical, 20)
        }
    }

    private var title: String {
        if !hasSelectedServices { return "Choose your streaming services" }
        if catalogError != nil { return "Catalog temporarily unavailable" }
        return "Find something for tonight"
    }

    private var description: String {
        if !hasSelectedServices {
            return "Add subscriptions you already have, then OpenTV can explain recommendations that are available to you."
        }
        if catalogError != nil {
            return "Your local library still works. Retry in Discover or choose something already saved."
        }
        return "Search the catalog or add a recommendation to build your Up Next queue."
    }
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

#Preview {
    TodayView(selectedTab: .constant(.today))
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
