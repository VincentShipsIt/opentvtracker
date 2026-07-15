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

                        NavigationLink {
                            ViewingAnalyticsView(scope: .personal)
                        } label: {
                            ViewingAnalyticsPreviewCard(summary: personalSummary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.viewing-analytics")

                        ProfileLibrarySummary(
                            watchlistCount: model.titles(in: .planned).count,
                            watchingCount: model.titles(in: .watching).count,
                            completedCount: model.titles(in: .completed).count
                        )
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.top, 10)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Profile")
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
        }
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

private struct ProfileLibrarySummary: View {
    let watchlistCount: Int
    let watchingCount: Int
    let completedCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "My library", subtitle: "Your personal lists at a glance")
            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                HStack(spacing: 0) {
                    ProfileCount(value: watchlistCount, label: "Watchlist")
                    Divider().frame(height: 42)
                    ProfileCount(value: watchingCount, label: "Watching")
                    Divider().frame(height: 42)
                    ProfileCount(value: completedCount, label: "Completed")
                }
                .padding(.vertical, 18)
            }
        }
    }
}

private struct ProfileCount: View {
    let value: Int
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value, format: .number)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    ProfileView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
}
