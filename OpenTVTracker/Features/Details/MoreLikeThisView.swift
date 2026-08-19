import SwiftUI

struct MoreLikeThisView: View {
    @Environment(AppModel.self) private var model
    let sourceTitleID: MediaTitle.ID
    @State private var showsServiceManager = false

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let sourceTitle {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        MoreLikeThisContextCard(title: sourceTitle)

                        if matches.isEmpty {
                            emptyState
                        } else {
                            MoreLikeThisGrid(
                                matches: matches,
                                selectedProviderIDs: model.selectedProviderIDs
                            )
                        }
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, 12)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Title unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle("More Like This")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: MediaTitle.self) { title in
            MediaDetailView(titleID: title.id)
        }
        .sheet(isPresented: $showsServiceManager) {
            ServiceManagerView()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if model.selectedProviderIDs.isEmpty {
            ContentUnavailableView {
                Label("Choose a streaming service", systemImage: "play.tv")
            } description: {
                Text("More Like This looks for similar titles on the services you already subscribe to.")
            } actions: {
                Button("Choose services", systemImage: "slider.horizontal.3") {
                    showsServiceManager = true
                }
                .adaptiveGlassButton(prominent: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 42)
            .accessibilityIdentifier("more-like-this.empty")
        } else {
            ContentUnavailableView(
                "No similar titles",
                systemImage: "sparkles.rectangle.stack",
                description: Text("Nothing on your selected services is a close match for this title.")
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 42)
            .accessibilityIdentifier("more-like-this.empty")
        }
    }

    private var sourceTitle: MediaTitle? {
        model.mediaTitle(withID: sourceTitleID)
    }

    private var matches: [SimilarTitleMatch] {
        model.moreLikeThis(sourceTitleID)
    }
}

private struct MoreLikeThisContextCard: View {
    let title: MediaTitle

    var body: some View {
        GlassSurface(tint: Color(hex: title.palette.primaryHex)) {
            HStack(spacing: 14) {
                PosterArtwork(title: title, cornerRadius: 10)
                    .frame(width: 72, height: 104)

                VStack(alignment: .leading, spacing: 7) {
                    Label("Because you liked", systemImage: "sparkles")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tint)
                    Text(title.title)
                        .font(.title2.weight(.black))
                        .lineLimit(2)
                    Text("Genre, mood, format, and runtime—not generic popularity.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(14)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MoreLikeThisGrid: View {
    let matches: [SimilarTitleMatch]
    let selectedProviderIDs: Set<StreamingProvider.ID>

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Your closest matches",
                subtitle: "Available on your selected services"
            )

            AdaptiveGrid(rowSpacing: 20, columnSpacing: 14) {
                ForEach(matches) { match in
                    NavigationLink(value: match.title) {
                        SimilarTitleCard(
                            match: match,
                            selectedProviderIDs: selectedProviderIDs
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct SimilarTitleCard: View {
    let match: SimilarTitleMatch
    let selectedProviderIDs: Set<StreamingProvider.ID>

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterArtwork(title: match.title)
                .aspectRatio(AppTheme.posterAspectRatio, contentMode: .fit)
                .overlay(alignment: .topLeading) {
                    if let provider {
                        ProviderBadge(provider: provider, compact: true)
                            .padding(8)
                    }
                }

            Text(match.title.title)
                .font(.headline)
                .lineLimit(1)
            Text(match.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            RatingLabel(rating: match.title.rating)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Opens details for this recommendation")
    }

    private var accessibilityLabel: String {
        let providerName = provider?.name ?? "your services"
        let rating = match.title.rating.formatted(.number.precision(.fractionLength(1)))
        return "\(match.title.title), rated \(rating), on \(providerName). \(match.reason)."
    }

    private var provider: StreamingProvider? {
        match.title.providers.first { selectedProviderIDs.contains($0.id) }
    }
}

#Preview {
    NavigationStack {
        MoreLikeThisView(sourceTitleID: "severance")
            .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
            .environment(\.allowsRemoteArtwork, false)
    }
}
