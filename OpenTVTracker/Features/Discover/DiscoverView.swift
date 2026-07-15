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
                        CatalogSearchBar(
                            searchText: $searchText,
                            presentedSheet: $presentedSheet
                        )

                        if searchText.isEmpty {
                            featuredRecommendation
                            DiscoverCategoryCarousel(sections: categorySections)
                            CinemaDiscoveryCard()
                                .padding(.horizontal, AppTheme.horizontalPadding)
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
            .task(id: searchText) {
                await model.searchCatalog(text: searchText)
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
                title: "Catalog results",
                subtitle: "\(filteredTitles.count) matches · service availability shown separately"
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
                        CatalogSearchCard(result: title)
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
        model.catalogSearchResults.filter { title in
            title.title.localizedStandardContains(searchText)
                || title.genres.contains(where: { $0.localizedStandardContains(searchText) })
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

private struct CatalogSearchBar: View {
    @Binding var searchText: String
    @Binding var presentedSheet: DiscoverSheet?
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("Shows, movies, genres", text: $searchText)
                .focused($isSearchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .accessibilityLabel("Search the full catalog")

            if !searchText.isEmpty {
                Button("Clear search", systemImage: "xmark.circle.fill") {
                    searchText = ""
                }
                .labelStyle(.iconOnly)
                .foregroundStyle(.secondary)
            }

            Divider()
                .frame(height: 24)

            Button("Manage services", systemImage: "slider.horizontal.3") {
                presentedSheet = .services
            }
            .labelStyle(.iconOnly)
            .frame(width: 44, height: 44)
            .foregroundStyle(Color.accentColor)
            .accessibilityHint("Filters recommendations and availability, not catalog search")
            .accessibilityIdentifier("discover.manage-services")
        }
        .padding(.leading, 14)
        .padding(.trailing, 7)
        .frame(minHeight: 50)
        .background(Color(.secondarySystemBackground), in: Capsule())
        .overlay { Capsule().strokeBorder(.primary.opacity(0.08)) }
        .padding(.horizontal, AppTheme.horizontalPadding)
    }
}

private struct CatalogSearchCard: View {
    @Environment(AppModel.self) private var model
    let result: MediaTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            NavigationLink(value: title) {
                PosterShelfCard(title: title)
            }
            .buttonStyle(.plain)

            Label(availabilityLabel, systemImage: availabilitySymbol)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(availabilityColor)
                .lineLimit(1)

            if title.state == .completed {
                Label("Watched", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Already watched")
            } else {
                Button("Mark watched", systemImage: "checkmark.circle") {
                    model.markWatched(title.id)
                }
                .font(.caption.weight(.semibold))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHint("Adds this title to your viewing history and recommendation profile")
            }
        }
    }

    private var title: MediaTitle {
        model.mediaTitle(withID: result.id) ?? result
    }

    private var selectedProviders: [StreamingProvider] {
        title.providers.filter { model.selectedProviderIDs.contains($0.id) }
    }

    private var availabilityLabel: String {
        if let provider = selectedProviders.first { return "On \(provider.name)" }
        if !title.providers.isEmpty { return "On other services" }
        return "Availability unknown"
    }

    private var availabilitySymbol: String {
        if !selectedProviders.isEmpty { return "checkmark.circle.fill" }
        if !title.providers.isEmpty { return "play.tv" }
        return "questionmark.circle"
    }

    private var availabilityColor: Color {
        selectedProviders.isEmpty ? .secondary : .green
    }
}

#Preview {
    DiscoverView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
