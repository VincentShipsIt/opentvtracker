import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var searchText = ""
    @State private var surpriseOffset = 0
    @State private var presentedSheet: DiscoverSheet?
    @State private var presentsAssistant = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        if trimmedSearchText.isEmpty {
                            serviceManagerControl
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
            .navigationTitle("Discover")
            .navigationBarTitleDisplayMode(.large)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Shows, movies, genres"
            )
            .task(id: searchText) {
                await model.searchCatalog(text: searchText)
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
            .navigationDestination(for: DiscoverCategory.self) { category in
                DiscoverCategoryShelfView(category: category)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Ask OpenTV", systemImage: "sparkles") {
                        presentsAssistant = true
                    }
                    .accessibilityHint("Opens personalized viewing suggestions")
                    .accessibilityIdentifier("discover.ask-opentv")
                }
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
            .fullScreenCover(isPresented: $presentsAssistant) {
                DiscoveryAssistantView()
            }
        }
    }

    private var serviceManagerControl: some View {
        ServiceManagerControl {
            presentedSheet = .services
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
                subtitle: searchStatus
            )

            if model.catalogSearchResults.isEmpty {
                if let error = model.catalogSearchError, !model.isSearchingCatalog {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "Catalog unavailable",
                            systemImage: "wifi.exclamationmark",
                            description: Text(error)
                        )

                        Button("Try again", systemImage: "arrow.clockwise") {
                            Task { await model.searchCatalog(text: searchText) }
                        }
                        .adaptiveGlassButton(prominent: true)
                    }
                } else if model.isSearchingCatalog {
                    ProgressView("Searching for “\(trimmedSearchText)”…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    ContentUnavailableView.search(text: trimmedSearchText)
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
                    ForEach(model.catalogSearchResults) { title in
                        CatalogSearchCard(result: title)
                            .task {
                                if title.id == model.catalogSearchResults.last?.id {
                                    await model.loadMoreCatalogResults(text: searchText)
                                }
                            }
                    }
                }

                if model.isSearchingCatalog {
                    ProgressView("Loading more results…")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else if let error = model.catalogSearchError {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "Catalog unavailable",
                            systemImage: "wifi.exclamationmark",
                            description: Text(error)
                        )

                        Button("Try again", systemImage: "arrow.clockwise") {
                            Task { await model.loadMoreCatalogResults(text: searchText) }
                        }
                        .adaptiveGlassButton(prominent: true)
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

}

private extension DiscoverView {
    var rotatedRecommendations: [MediaTitle] {
        let titles = model.recommendations
        guard !titles.isEmpty else { return [] }
        let offset = surpriseOffset % titles.count
        return Array(titles[offset...]) + Array(titles[..<offset])
    }

    var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var searchStatus: String {
        if model.isSearchingCatalog {
            return "Searching for “\(trimmedSearchText)”…"
        }
        if model.catalogSearchError != nil {
            return "Search for “\(trimmedSearchText)” failed"
        }
        return "\(model.catalogSearchResults.count) matches for “\(trimmedSearchText)” · availability shown separately"
    }

    func titles(for provider: StreamingProvider) -> [MediaTitle] {
        model.titles.filter { title in
            title.providers.contains(where: { $0.id == provider.id })
        }
    }

    var categorySections: [DiscoverCategorySection] {
        DiscoverCategorySection.available(in: model.titlesOnSelectedProviders)
    }

    func presentTrailer(for title: MediaTitle) {
        guard let sourceURL = title.trailerURL,
              let trailer = TrailerPresentation(title: title.title, sourceURL: sourceURL) else {
            return
        }
        presentedSheet = .trailer(trailer)
    }
}

private struct ServiceManagerControl: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                HStack(spacing: 12) {
                    Image(systemName: "play.tv.fill")
                        .font(.title3)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.14), in: Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Manage streaming services")
                            .font(.headline)
                        Text("Personalize recommendations and highlight availability")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, AppTheme.horizontalPadding)
        .accessibilityHint("Changes recommendations and availability labels, not catalog search results")
        .accessibilityIdentifier("discover.manage-services")
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

            if title.state.isCurrentViewingComplete {
                Label(title.state == .completed ? "Watched" : "Caught up", systemImage: title.state.symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(title.state == .completed ? "Already watched" : "Currently caught up")
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
