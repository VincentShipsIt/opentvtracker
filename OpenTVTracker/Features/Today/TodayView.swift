import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @State private var presentsAssistant = false

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        if let first = model.upNext.first {
                            UpNextHero(title: first)
                        } else {
                            caughtUp
                                .padding(.horizontal, AppTheme.horizontalPadding)
                        }

                        remainingQueue
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
        }
    }

    private var caughtUp: some View {
        GlassSurface(tint: .green) {
            ContentUnavailableView(
                "You are caught up",
                systemImage: "checkmark.seal.fill",
                description: Text("Pick something from Discover or your watchlist.")
            )
            .padding(.vertical, 20)
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
    private var partnerActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Together", subtitle: model.sharedSpace.name)
            if model.togetherActivity.isEmpty {
                ContentUnavailableView(
                    "No shared activity yet",
                    systemImage: "person.2",
                    description: Text("Share a title or mark something watched together.")
                )
                .frame(minHeight: 180)
            } else {
                VStack(spacing: 12) {
                    ForEach(model.togetherActivity.prefix(3)) { activity in
                        ActivityCard(
                            activity: activity,
                            space: model.sharedSpace,
                            title: model.mediaTitle(for: activity)
                        )
                    }
                }
            }
        }
        .padding(.horizontal, AppTheme.horizontalPadding)
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
    TodayView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
