import SwiftUI

struct TogetherView: View {
    @Environment(AppModel.self) private var model
    @State private var presentedSheet: TogetherSheet?

    private let columns = [GridItem(.adaptive(minimum: 142), spacing: 14)]

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        spaceHeader
                        sharedWatchlist
                        recentActivity
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("Together")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Invite partner", systemImage: "person.badge.plus") {
                        presentedSheet = .invite
                    }
                }
            }
            .sheet(item: $presentedSheet) { sheet in
                switch sheet {
                case .invite:
                    PartnerInvitationView(space: model.sharedSpace)
                }
            }
            .navigationDestination(for: MediaTitle.self) { title in
                MediaDetailView(titleID: title.id)
            }
        }
    }

    private var spaceHeader: some View {
        GlassSurface(tint: .pink) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(model.sharedSpace.name)
                            .font(.largeTitle.weight(.bold))
                        Text("One private space. Your pace or ours.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    memberStack
                }

                Label(
                    model.sharedSpace.isCloudSharingEnabled ? "Synced privately with iCloud" : "Local preview · iCloud sharing next",
                    systemImage: model.sharedSpace.isCloudSharingEnabled ? "icloud.fill" : "iphone"
                )
                .font(.footnote.weight(.semibold))
                .foregroundStyle(model.sharedSpace.isCloudSharingEnabled ? Color.green : Color.secondary)
            }
            .padding(18)
        }
        .padding(.top, 10)
    }

    private var memberStack: some View {
        HStack(spacing: -8) {
            ForEach(model.sharedSpace.members) { member in
                Text(member.initials)
                    .font(.caption2.weight(.bold))
                    .frame(width: 38, height: 38)
                    .background(Color.accentColor.gradient, in: Circle())
                    .foregroundStyle(.white)
                    .overlay { Circle().stroke(.background, lineWidth: 2) }
                    .accessibilityLabel(member.name)
            }
        }
    }

    private var sharedWatchlist: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Our watchlist", subtitle: "\(model.sharedTitles.count) titles you both can move forward")
            LazyVGrid(columns: columns, spacing: 14) {
                ForEach(model.sharedTitles) { title in
                    NavigationLink(value: title) {
                        SharedPosterCard(title: title)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Recent activity", subtitle: "Spoiler-safe by default")
            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                VStack(spacing: 0) {
                    ForEach(model.sharedSpace.activity) { activity in
                        ActivityRow(activity: activity, space: model.sharedSpace)
                        if activity.id != model.sharedSpace.activity.last?.id {
                            Divider().padding(.leading, 48)
                        }
                    }
                }
                .padding(.vertical, 6)
            }
        }
    }
}

private struct SharedPosterCard: View {
    let title: MediaTitle

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PosterArtwork(title: title)
                .aspectRatio(0.70, contentMode: .fit)
            Text(title.title)
                .font(.headline)
                .lineLimit(1)
            Text(title.progressLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private enum TogetherSheet: String, Identifiable {
    case invite
    var id: String { rawValue }
}

private struct PartnerInvitationView: View {
    @Environment(\.dismiss) private var dismiss
    let space: SharedSpace

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()
                VStack(spacing: 24) {
                    Image(systemName: "person.2.badge.gearshape.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("Invite someone to \(space.name)")
                            .font(.title2.weight(.bold))
                        Text("This screen is the production boundary for a private CloudKit share. It stays unavailable until the container, acceptance flow, and revocation behavior are configured together.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }

                    GlassSurface(cornerRadius: AppTheme.compactRadius) {
                        VStack(alignment: .leading, spacing: 12) {
                            Label("No OpenTV password", systemImage: "checkmark.circle")
                            Label("Invitation-only iCloud share", systemImage: "lock.shield")
                            Label("Separate from your personal library", systemImage: "rectangle.on.rectangle.slash")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }

                    Button("CloudKit setup required") { }
                        .adaptiveGlassButton(prominent: true)
                        .disabled(true)
                }
                .padding(AppTheme.horizontalPadding)
            }
            .navigationTitle("Partner invitation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    TogetherView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
