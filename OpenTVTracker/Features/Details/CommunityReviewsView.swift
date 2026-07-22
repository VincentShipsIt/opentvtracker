import SwiftUI

struct CommunityReviewsRoute: Hashable {
    let titleID: MediaTitle.ID
}

struct CommunityReviewsView: View {
    @Environment(AppModel.self) private var model
    let titleID: MediaTitle.ID
    @State private var pagination = CommunityReviewPagination()
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AmbientBackdrop()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if pagination.reviews.isEmpty {
                        emptyState
                    } else {
                        ForEach(pagination.reviews) { review in
                            ReviewCard(review: review)
                        }

                        paginationAction
                    }

                    sourceAttribution
                }
                .padding(.horizontal, AppTheme.horizontalPadding)
                .padding(.top, 12)
                .padding(.bottom, 36)
            }
        }
        .navigationTitle("Community reviews")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CommunityReview.self) {
            CommunityReviewDetailView(review: $0)
        }
        .task(id: titleID) {
            guard pagination.loadedPages.isEmpty else { return }
            await loadNextPage()
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if isLoading {
            ProgressView("Loading reviews…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Reviews unavailable", systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try again") {
                    Task { await loadNextPage() }
                }
                .adaptiveGlassButton(prominent: true)
            }
        } else {
            ContentUnavailableView(
                "No community reviews yet",
                systemImage: "text.bubble",
                description: Text("TMDB has not published any reviews for this title.")
            )
        }
    }

    @ViewBuilder
    private var paginationAction: some View {
        if let errorMessage {
            GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    Label("More reviews could not be loaded", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                    Text(errorMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Try again") {
                        Task { await loadNextPage() }
                    }
                    .adaptiveGlassButton()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
            }
        } else if pagination.nextPage != nil {
            Button {
                Task { await loadNextPage() }
            } label: {
                Group {
                    if isLoading {
                        ProgressView()
                    } else {
                        Label("Load more reviews", systemImage: "arrow.down.circle")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .adaptiveGlassButton()
            .disabled(isLoading)
        }
    }

    @ViewBuilder
    private var sourceAttribution: some View {
        if let title, let sourceURL = SourceLinks.catalog(for: title) {
            Link(destination: sourceURL) {
                Label("Reviews provided by TMDB", systemImage: "arrow.up.right.square")
            }
            .font(.footnote.weight(.semibold))
            .accessibilityHint("Opens this title on TMDB")
        }
    }

    private var title: MediaTitle? {
        model.mediaTitle(withID: titleID)
    }

    private func loadNextPage() async {
        guard !isLoading, let title, let requestedPage = pagination.nextPage else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await model.catalogService.reviews(
                kind: title.kind,
                catalogID: title.catalogID,
                page: requestedPage
            )
            try pagination.apply(response, requestedPage: requestedPage)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
