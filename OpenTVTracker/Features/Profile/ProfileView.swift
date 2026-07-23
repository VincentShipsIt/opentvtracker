import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var showsSettings = false

    var body: some View {
        let diaryRecords = model.diaryRecords
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        ProfileHeader(member: currentMember)

                        if !model.recentlyWatchedTitles.isEmpty {
                            titleSection(
                                title: "Recently watched",
                                subtitle: "Your latest activity, newest first",
                                titles: Array(model.recentlyWatchedTitles.prefix(6))
                            )
                        }

                        titleSection(
                            title: "Continue watching",
                            subtitle: "Your active series and episode progress",
                            titles: model.watchingTitlesByRecency
                        )

                        titleSection(
                            title: "Caught up",
                            subtitle: "Continuing series with no released episodes left",
                            titles: model.caughtUpTitlesByRecency
                        )

                        titleSection(
                            title: "Finished",
                            subtitle: "Completed titles, newest activity first",
                            titles: model.completedTitlesByRecency
                        )

                        titleSection(
                            title: "Watchlist",
                            subtitle: "Saved for later",
                            titles: model.watchlistTitlesByRecency
                        )

                        NavigationLink {
                            ViewingDiaryView()
                        } label: {
                            ViewingDiaryPreviewCard(
                                entryCount: diaryRecords.count,
                                latestDate: diaryRecords.first?.entry.watchedAt
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.viewing-diary")

                        NavigationLink {
                            ViewingAnalyticsView(scope: .personal)
                        } label: {
                            ViewingAnalyticsPreviewCard(summary: personalSummary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.viewing-analytics")
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape.fill") {
                        showsSettings = true
                    }
                    .accessibilityHint("Opens streaming region, subscriptions, and privacy settings")
                }
            }
            .sheet(isPresented: $showsSettings) {
                AppSettingsView()
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
        }
    }

    @ViewBuilder
    private func titleSection(
        title: String,
        subtitle: String,
        titles: [MediaTitle]
    ) -> some View {
        if !titles.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: title, subtitle: subtitle)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(titles) { mediaTitle in
                            NavigationLink(value: mediaTitle) {
                                MediaProgressPosterCard(
                                    title: mediaTitle,
                                    summary: model.progressSummary(for: mediaTitle),
                                    subtitle: profileSubtitle(for: mediaTitle)
                                )
                                .frame(width: 144)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func profileSubtitle(for title: MediaTitle) -> String {
        if let lastWatchedAt = title.lastWatchedAt {
            return "Watched \(lastWatchedAt.formatted(.relative(presentation: .named)))"
        }
        return "\(title.year) · \(title.kind.label)"
    }

    private var currentMember: SpaceMember {
        model.sharedSpace.members.first(where: \.isCurrentUser)
            ?? SpaceMember(id: "local-user", name: "You", initials: "YOU", isCurrentUser: true)
    }

    private var personalSummary: ViewingAnalyticsSummary {
        ViewingAnalyticsEngine.summarize(snapshot: model.snapshot, scope: .personal)
    }
}

private struct ViewingDiaryPreviewCard: View {
    let entryCount: Int
    let latestDate: Date?

    var body: some View {
        GlassSurface(tint: .purple) {
            HStack(spacing: 16) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title)
                    .foregroundStyle(.purple)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Viewing diary")
                        .font(.headline)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(16)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        guard entryCount > 0 else { return "Dates, ratings, notes, and rewatches" }
        guard let latestDate else { return "\(entryCount) private entries" }
        return "\(entryCount) entries · Latest \(latestDate.formatted(.relative(presentation: .named)))"
    }
}

private struct ProfileHeader: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 72
    let member: SpaceMember

    var body: some View {
        GlassSurface(tint: .indigo) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        avatar
                        metadata
                    }
                } else {
                    HStack(spacing: 18) {
                        avatar
                        metadata
                    }
                }
            }
            .padding(18)
        }
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        Text(AppAccessibility.displayedInitials(member.initials))
            .font(.title2.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .foregroundStyle(.white)
            .frame(width: avatarSize, height: avatarSize)
            .background(Color.indigo.gradient, in: Circle())
            .accessibilityHidden(true)
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(member.name)
                .font(.title2.weight(.bold))
            Text("Your private viewing profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Label("Personal history", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.indigo)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ProfileView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
}
