import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var surpriseOffset = 0
    @State private var presentedSheet: DiscoverSheet?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        if searchText.isEmpty {
                            DiscoverCategoryRail(sections: categorySections)
                            CinemaDiscoveryCard()
                                .padding(.horizontal, AppTheme.horizontalPadding)
                            featuredRecommendation
                            recommendationShelf
                            providerShelves
                            discoverySkill
                        } else {
                            searchResults
                        }
                    }
                    .containerRelativeFrame(.horizontal)
                    .padding(.bottom, 36)
                }
            }
            .navigationTitle("Discover")
            .searchable(text: $searchText, prompt: "Shows, movies, genres")
            .task(id: searchText) {
                await model.searchCatalog(text: searchText)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Manage services", systemImage: "slider.horizontal.3") {
                        presentedSheet = .services
                    }
                    .accessibilityIdentifier("discover.manage-services")
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
            .navigationDestination(for: DiscoverCategory.self) { category in
                DiscoverCategoryShelfView(category: category)
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .categories:
                    DiscoveryCategoryPickerView()
                case .services:
                    ServiceManagerView()
                case .aiRanking:
                    AIRankingSettingsView()
                case .trailer(let trailer):
                    TrailerPlayerView(trailer: trailer)
                }
            }
        }
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
                Text("Browse illustrated categories, each led by the newest title available on services you already have.")
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Browse categories", systemImage: "square.grid.2x2.fill") {
                        presentedSheet = .categories
                    }
                    .adaptiveGlassButton(prominent: true)

                    Button("Surprise me", systemImage: "dice") {
                        let count = max(model.recommendations.count, 1)
                        surpriseOffset = (surpriseOffset + 1) % count
                    }
                    .adaptiveGlassButton()
                }

                Button("AI ranking settings", systemImage: "brain.head.profile") {
                    presentedSheet = .aiRanking
                }
                .adaptiveGlassButton()
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
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
                if model.isSearchingCatalog {
                    ProgressView("Searching the catalog…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else if let error = model.catalogSearchError {
                    ContentUnavailableView(
                        "Catalog unavailable",
                        systemImage: "wifi.exclamationmark",
                        description: Text(error)
                    )
                } else {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                }
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
                        .task {
                            if title.id == filteredTitles.last?.id {
                                await model.loadMoreCatalogResults(text: searchText)
                            }
                        }
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
                        ? "Use Manage Services to add Netflix, Prime Video, Apple TV+, or another subscription."
                        : "Add another service you already subscribe to or browse a different category."
                )
            )
            .padding(.vertical, 20)
        }
    }

    private var rotatedRecommendations: [MediaTitle] {
        let titles = model.recommendations
        guard !titles.isEmpty else { return [] }
        let offset = surpriseOffset % titles.count
        return Array(titles[offset...]) + Array(titles[..<offset])
    }

    private var filteredTitles: [MediaTitle] {
        let candidates = model.catalogSearchResults.isEmpty ? model.titlesOnSelectedProviders : model.catalogSearchResults
        return candidates.filter { title in
            model.isAvailableOnSelectedProviders(title)
                && (
            title.title.localizedStandardContains(searchText)
                || title.genres.contains(where: { $0.localizedStandardContains(searchText) })
                )
        }
    }

    private func titles(for provider: StreamingProvider) -> [MediaTitle] {
        model.titles.filter { title in
            title.providers.contains(where: { $0.id == provider.id })
        }
    }

    private var categorySections: [DiscoverCategorySection] {
        DiscoverCategorySection.available(in: model.titlesOnSelectedProviders)
    }

    private func presentTrailer(for title: MediaTitle) {
        guard let url = title.trailerURL else { return }
        presentedSheet = .trailer(TrailerPresentation(title: title.title, url: url))
    }
}

#Preview {
    DiscoverView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
