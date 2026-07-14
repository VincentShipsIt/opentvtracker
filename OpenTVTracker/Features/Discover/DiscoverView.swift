import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var surpriseOffset = 0
    @State private var presentedSheet: DiscoverSheet?
    @State private var mediaFilter: DiscoverMediaFilter = .all

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        serviceFilters

                        if searchText.isEmpty {
                            featuredRecommendation
                            recommendationShelf
                            providerShelves
                            discoverySkill
                        } else {
                            searchResults
                        }
                    }
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $searchText, prompt: "Shows, movies, genres")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Manage services", systemImage: "slider.horizontal.3") {
                        presentedSheet = .services
                    }
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .prompt:
                    DiscoveryPromptView()
                case .services:
                    ServiceManagerView()
                case .trailer(let trailer):
                    TrailerPlayerView(trailer: trailer)
                }
            }
        }
    }

    private var serviceFilters: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "Your streaming shelf",
                subtitle: "Only show titles included with services you pay for"
            )
            .padding(.horizontal, AppTheme.horizontalPadding)

            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(StreamingProvider.supportedSubscriptions) { provider in
                        ServiceFilterChip(provider: provider)
                    }
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)

            HStack(spacing: 8) {
                ForEach(DiscoverMediaFilter.allCases) { filter in
                    Button {
                        mediaFilter = filter
                    } label: {
                        Label(filter.label, systemImage: filter.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .tint(mediaFilter == filter ? .accentColor : .secondary)
                    .accessibilityAddTraits(mediaFilter == filter ? .isSelected : [])
                }
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
            .sensoryFeedback(.selection, trigger: mediaFilter)
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private var featuredRecommendation: some View {
        if let title = rotatedRecommendations.first {
            FeaturedMediaCard(title: title) {
                presentTrailer(for: title)
            }
            .padding(.horizontal, AppTheme.horizontalPadding)
        } else {
            noServiceMatches
                .padding(.horizontal, AppTheme.horizontalPadding)
        }
    }

    @ViewBuilder
    private var recommendationShelf: some View {
        let recommendations = Array(rotatedRecommendations.dropFirst())
        if !recommendations.isEmpty {
            MediaShelf(
                title: "Made for tonight",
                subtitle: "Strong matches on your subscriptions",
                titles: recommendations
            )
        }
    }

    @ViewBuilder
    private var providerShelves: some View {
        ForEach(model.selectedProviders) { provider in
            let titles = titles(for: provider)
            if !titles.isEmpty {
                MediaShelf(
                    title: "On \(provider.name)",
                    subtitle: "Included in your selected services",
                    titles: titles
                )
            }
        }
    }

    private var discoverySkill: some View {
        GlassSurface(tint: .indigo) {
            VStack(alignment: .leading, spacing: 14) {
                Label("Still can't decide?", systemImage: "wand.and.stars")
                    .font(.title2.weight(.bold))
                Text("Add mood and time. OpenTV will pick from services you already have and explain the choice.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Choose tonight", systemImage: "sparkles") {
                        presentedSheet = .prompt
                    }
                    .adaptiveGlassButton(prominent: true)

                    Button("Surprise me", systemImage: "dice") {
                        let count = max(model.recommendations.filter(matchesMediaFilter).count, 1)
                        surpriseOffset = (surpriseOffset + 1) % count
                    }
                    .adaptiveGlassButton()
                }
            }
            .padding(18)
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Results on your services",
                subtitle: "\(filteredTitles.count) matches across \(model.selectedProviders.count) subscriptions"
            )

            if filteredTitles.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 14),
                        GridItem(.flexible(), spacing: 14)
                    ],
                    spacing: 18
                ) {
                    ForEach(filteredTitles) { title in
                        NavigationLink(value: title) {
                            PosterShelfCard(title: title)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
    }

    private var noServiceMatches: some View {
        GlassSurface(tint: .orange) {
            ContentUnavailableView(
                model.selectedProviderIDs.isEmpty ? "Pick a streaming service" : "Nothing matches yet",
                systemImage: "play.tv",
                description: Text(
                    model.selectedProviderIDs.isEmpty
                        ? "Select Netflix, Prime Video, Apple TV+, or another service above."
                        : "Try another mood or add a service you already subscribe to."
                )
            )
            .padding(.vertical, 20)
        }
    }

    private var rotatedRecommendations: [MediaTitle] {
        let titles = model.recommendations.filter(matchesMediaFilter)
        guard !titles.isEmpty else { return [] }
        let offset = surpriseOffset % titles.count
        return Array(titles[offset...]) + Array(titles[..<offset])
    }

    private var filteredTitles: [MediaTitle] {
        model.titlesOnSelectedProviders.filter { title in
            matchesMediaFilter(title)
                && (
                    title.title.localizedStandardContains(searchText)
                        || title.genres.contains(where: { $0.localizedStandardContains(searchText) })
                )
        }
    }

    private func titles(for provider: StreamingProvider) -> [MediaTitle] {
        model.titles.filter { title in
            matchesMediaFilter(title)
                && title.providers.contains(where: { $0.id == provider.id })
        }
    }

    private func matchesMediaFilter(_ title: MediaTitle) -> Bool {
        switch mediaFilter {
        case .all: true
        case .series: title.kind == .series
        case .movies: title.kind == .movie
        }
    }

    private func presentTrailer(for title: MediaTitle) {
        guard let url = title.trailerURL else { return }
        presentedSheet = .trailer(TrailerPresentation(title: title.title, url: url))
    }
}

private enum DiscoverMediaFilter: String, CaseIterable, Identifiable {
    case all
    case series
    case movies

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: "All"
        case .series: "Shows"
        case .movies: "Movies"
        }
    }

    var symbol: String {
        switch self {
        case .all: "rectangle.grid.2x2"
        case .series: "tv"
        case .movies: "film"
        }
    }
}

#Preview {
    DiscoverView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
