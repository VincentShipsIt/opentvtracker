import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        greeting

                        if let first = model.upNext.first {
                            UpNextHero(title: first)
                        } else {
                            caughtUp
                        }

                        remainingQueue
                        partnerActivity
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 32)
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Good evening")
                .font(.largeTitle.weight(.bold))
            Text("Here is the shortest path back into your stories.")
                .font(.body)
                .foregroundStyle(.secondary)

            if let persistenceError = model.persistenceError {
                Label(persistenceError, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 12)
        .accessibilityElement(children: .combine)
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
                ForEach(remaining) { title in
                    NavigationLink(value: title) {
                        CompactQueueRow(title: title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private var partnerActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Together", subtitle: model.sharedSpace.name)
            if model.sharedSpace.activity.isEmpty {
                ContentUnavailableView(
                    "No shared activity yet",
                    systemImage: "person.2",
                    description: Text("Share a title or mark something watched together.")
                )
                .frame(minHeight: 180)
            } else {
                VStack(spacing: 12) {
                    ForEach(model.sharedSpace.activity.prefix(3)) { activity in
                        ActivityCard(
                            activity: activity,
                            space: model.sharedSpace,
                            title: model.mediaTitle(for: activity)
                        )
                    }
                }
            }
        }
    }
}

private struct UpNextHero: View {
    @Environment(AppModel.self) private var model
    let title: MediaTitle
    @State private var progressTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Up next", subtitle: title.nextReleaseDescription)

            GlassSurface(tint: Color(hex: title.palette.primaryHex)) {
                VStack(alignment: .leading, spacing: 16) {
                    NavigationLink(value: title) {
                        HStack(spacing: 16) {
                            PosterArtwork(title: title)
                                .frame(width: 112, height: 164)

                            VStack(alignment: .leading, spacing: 9) {
                                Text(title.title)
                                    .font(.title2.weight(.bold))
                                    .foregroundStyle(.primary)
                                Text(title.progressLabel)
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                RatingLabel(rating: title.rating)
                                Text("\(title.runtimeMinutes) min")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)

                    if let progress = title.progress {
                        ProgressView(value: progress.fraction)
                            .tint(.accentColor)
                            .accessibilityLabel("Season progress")
                            .accessibilityValue("Episode \(progress.episode) of \(progress.totalEpisodes)")
                    }

                    Button {
                        model.markNextWatched(title.id)
                        progressTrigger += 1
                    } label: {
                        Label("Mark next episode watched", systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .adaptiveGlassButton(prominent: true)
                    .sensoryFeedback(.success, trigger: progressTrigger)
                }
                .padding(18)
            }
        }
    }
}

private struct CompactQueueRow: View {
    let title: MediaTitle

    var body: some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius) {
            HStack(spacing: 12) {
                PosterArtwork(title: title, cornerRadius: 10)
                    .frame(width: 64, height: 84)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title.title)
                        .font(.headline)
                    Text(title.nextReleaseDescription ?? title.progressLabel)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ProgressView(value: title.progress?.fraction ?? 0)
                        .tint(.accentColor)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(10)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    TodayView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
