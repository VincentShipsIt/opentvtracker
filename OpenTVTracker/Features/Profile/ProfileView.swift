import SwiftUI

struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var showsSettings = false

    var body: some View {
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

private struct ProfileHeader: View {
    let member: SpaceMember

    var body: some View {
        GlassSurface(tint: .indigo) {
            HStack(spacing: 18) {
                Text(member.initials)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 72, height: 72)
                    .background(Color.indigo.gradient, in: Circle())
                    .accessibilityHidden(true)

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
                Spacer(minLength: 0)
            }
            .padding(18)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProfileView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
}
