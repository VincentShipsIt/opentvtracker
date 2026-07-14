import SwiftUI

struct MoreLikeThisRoute: Hashable {
    let sourceTitleID: MediaTitle.ID
}

struct MoreLikeThisView: View {
    @Environment(AppModel.self) private var model
    let sourceTitleID: MediaTitle.ID

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let sourceTitle {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        MoreLikeThisContextCard(title: sourceTitle)

                        if matches.isEmpty {
                            ContentUnavailableView(
                                "No matches on your services",
                                systemImage: "sparkles.rectangle.stack",
                                description: Text("Add another streaming service in Discover to widen the search.")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 42)
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
    }

    private var sourceTitle: MediaTitle? {
        model.titles.first(where: { $0.id == sourceTitleID })
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
                        .foregroundStyle(Color.accentColor)
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

    private let columns = [
        GridItem(.flexible(), spacing: 14),
        GridItem(.flexible(), spacing: 14)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(
                title: "Your closest matches",
                subtitle: "Available on your selected services"
            )

            LazyVGrid(columns: columns, spacing: 20) {
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
                .aspectRatio(0.68, contentMode: .fit)
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
        return "\(match.title.title), rated \(match.title.rating, format: .number.precision(.fractionLength(1))), on \(providerName). \(match.reason)."
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
