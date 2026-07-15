import SwiftUI

struct MediaDetailView: View {
    @Environment(AppModel.self) private var model
    let titleID: MediaTitle.ID
    @State private var presentedTrailer: TrailerPresentation?
    @State private var showsTrackingEditor = false
    @State private var showsSharedNoteEditor = false

    var body: some View {
        ZStack {
            AmbientBackdrop()

            if let title {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: AppTheme.sectionSpacing) {
                        hero(title)
                        actions(title)
                        story(title)
                        MediaRatingSummary(title: title)
                        availability(title)
                        MediaEpisodeSection(title: title)
                        if title.kind == .movie {
                            TitleCinemaAvailability(title: title)
                        }
                        community(title)
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 36)
                }
            } else {
                ContentUnavailableView("Title unavailable", systemImage: "questionmark.folder")
            }
        }
        .navigationTitle(title?.title ?? "Details")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: titleID) {
            await model.refreshCatalogDetails(for: titleID)
        }
        .sheet(item: $presentedTrailer) { trailer in
            TrailerPlayerView(trailer: trailer)
        }
        .sheet(isPresented: $showsTrackingEditor) {
            if let title {
                TrackingEditorView(title: title)
            }
        }
        .sheet(isPresented: $showsSharedNoteEditor) {
            if let title { SharedNoteEditorView(title: title) }
        }
        .navigationDestination(for: MoreLikeThisRoute.self) { route in
            MoreLikeThisView(sourceTitleID: route.sourceTitleID)
        }
    }

    private var title: MediaTitle? {
        model.mediaTitle(withID: titleID)
    }

    private func hero(_ title: MediaTitle) -> some View {
        ZStack(alignment: .bottomLeading) {
            BackdropArtwork(title: title)
                .frame(maxWidth: .infinity)
                .frame(height: 300)

            LinearGradient(
                colors: [.clear, .black.opacity(0.28), .black.opacity(0.92)],
                startPoint: .top,
                endPoint: .bottom
            )
            .clipShape(.rect(cornerRadius: AppTheme.cardRadius))

            HStack(alignment: .bottom, spacing: 14) {
                PosterArtwork(title: title, cornerRadius: 12)
                    .frame(width: 104, height: 154)

                VStack(alignment: .leading, spacing: 8) {
                    if let provider = title.providers.first {
                        ProviderBadge(provider: provider)
                    }
                    Text(title.title)
                        .font(.title.weight(.black))
                        .foregroundStyle(.white)
                    Text("\(title.year) · \(title.kind.label) · \(title.runtimeMinutes) min")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.78))
                    HStack {
                        RatingLabel(rating: title.rating)
                        if let progress = title.progress {
                            Text(progress.label)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
        }
        .padding(.top, 12)
        .accessibilityElement(children: .contain)
    }

    private func actions(_ title: MediaTitle) -> some View {
        VStack(spacing: 10) {
            if let trailerURL = title.trailerURL {
                Button {
                    presentedTrailer = TrailerPresentation(title: title.title, url: trailerURL)
                } label: {
                    Label("Watch trailer", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .adaptiveGlassButton(prominent: true)
            }

            Button {
                model.markNextWatched(title.id)
            } label: {
                Label(
                    title.state == .completed ? "Watched" : title.kind == .movie ? "Mark watched" : "Mark next watched",
                    systemImage: "checkmark.circle.fill"
                )
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .adaptiveGlassButton(prominent: title.trailerURL == nil)
            .disabled(title.state == .completed)

            watchlistActions(title)

            recommendationAndTrackingActions(title)

            if model.isShared(title.id) {
                sharedActions(title)
            }
        }
    }

    private func watchlistActions(_ title: MediaTitle) -> some View {
        HStack(spacing: 10) {
            Button {
                model.toggleWatchlist(title.id)
            } label: {
                Label(
                    "My watchlist",
                    systemImage: title.isOnPersonalWatchlist ? "bookmark.fill" : "bookmark"
                )
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
            .accessibilityValue(title.isOnPersonalWatchlist ? "Added" : "Not added")
            .accessibilityHint("Adds or removes this title without changing your viewing progress")

            Button {
                model.toggleTogether(title.id)
            } label: {
                Label(
                    "Our watchlist",
                    systemImage: model.isShared(title.id) ? "person.2.fill" : "person.2"
                )
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
            .accessibilityValue(model.isShared(title.id) ? "Added" : "Not added")
            .accessibilityHint("Adds or removes this title from the watchlist you share")
        }
    }

    private func sharedActions(_ title: MediaTitle) -> some View {
        HStack(spacing: 10) {
            Button("Watched together", systemImage: "person.2.fill") {
                model.markWatchedTogether(title.id)
            }
            .adaptiveGlassButton()

            Button("Shared note", systemImage: "note.text.badge.plus") {
                showsSharedNoteEditor = true
            }
            .adaptiveGlassButton()
        }
    }

    private func recommendationAndTrackingActions(_ title: MediaTitle) -> some View {
        VStack(spacing: 10) {
            NavigationLink(value: MoreLikeThisRoute(sourceTitleID: title.id)) {
                Label("More like this", systemImage: "sparkles")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .adaptiveGlassButton()
            .accessibilityHint("Finds similar unwatched titles on your selected streaming services")

            Button {
                showsTrackingEditor = true
            } label: {
                Label("Edit tracking", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton()
        }
    }

    private func story(_ title: MediaTitle) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "The story")
            Text(title.synopsis)
                .font(.body)
                .lineSpacing(4)
        }
    }

    @ViewBuilder
    private func availability(_ title: MediaTitle) -> some View {
        if !title.providers.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Where to watch", subtitle: "Availability varies by region · data by JustWatch")
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(title.providers) { provider in
                            ProviderBadge(provider: provider)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    @ViewBuilder
    private func community(_ title: MediaTitle) -> some View {
        if !title.reviews.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Community notes", subtitle: "Spoilers stay hidden unless you ask")
                ForEach(title.reviews) { review in
                    ReviewCard(review: review)
                }

                HStack {
                    if let tmdbURL = SourceLinks.tmdb(kind: title.kind, catalogID: title.catalogID) {
                        Link("Open on TMDB", destination: tmdbURL)
                    }
                    Spacer()
                    if let imdbURL = SourceLinks.imdbSearch(title: title.title, year: title.year) {
                        Link("Find on IMDb", destination: imdbURL)
                    }
                }
                .font(.footnote.weight(.semibold))
            }
        }
    }
}

private struct SharedNoteEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let title: MediaTitle
    @State private var text = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Note for both of you") {
                    TextEditor(text: $text)
                        .frame(minHeight: 140)
                        .accessibilityLabel("Shared note about \(title.title)")
                }
                Section {
                    Text("This note enters the invitation-only partner space. Personal tracking notes remain local.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Shared note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        model.addSharedNote(text, titleID: title.id)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct ReviewCard: View {
    let review: CommunityReview
    @State private var revealsSpoiler = false

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(review.author)
                        .font(.headline)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(review.source)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        if let rating = review.rating {
                            RatingLabel(rating: rating)
                        }
                    }
                }

                if review.containsSpoilers && !revealsSpoiler {
                    Button("Reveal spoiler", systemImage: "eye.slash") {
                        revealsSpoiler = true
                    }
                    .adaptiveGlassButton()
                } else {
                    Text(review.excerpt)
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

enum SourceLinks {
    static func tmdb(kind: MediaKind, catalogID: Int) -> URL? {
        let path = kind == .movie ? "movie" : "tv"
        return URL(string: "https://www.themoviedb.org/\(path)/\(catalogID)")
    }

    static func imdbSearch(title: String, year: Int) -> URL? {
        var components = URLComponents(string: "https://www.imdb.com/find/")
        components?.queryItems = [URLQueryItem(name: "q", value: "\(title) \(year)")]
        return components?.url
    }
}

#Preview {
    NavigationStack {
        MediaDetailView(titleID: "severance")
            .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
            .environment(\.allowsRemoteArtwork, false)
    }
}
