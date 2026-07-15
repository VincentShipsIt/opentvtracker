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
                        analyticsLink
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
                    .accessibilityIdentifier("together.invite-partner")
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
                    model.sharedSpace.isCloudSharingEnabled ? "Synced privately with iCloud" : "Private on this iPhone · invite to sync",
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

    private var analyticsLink: some View {
        NavigationLink {
            ViewingAnalyticsView(initialScope: .together)
        } label: {
            GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .pink) {
                HStack(spacing: 14) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.pink)
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Our viewing stats")
                            .font(.headline)
                        Text("Hours, genres, movies and episodes together")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding(16)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("together.viewing-analytics")
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
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let space: SharedSpace
    private let sharingService: any PartnerSharingProviding = CloudKitPartnerSharingService()
    @State private var availability: PartnerSharingAvailability?
    @State private var invitationURL: URL?
    @State private var isWorking = false
    @State private var errorMessage: String?

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
                        Text(invitationDescription)
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

                    invitationAction

                    if model.sharedSpace.isCurrentUserShareOwner == true,
                       model.sharedSpace.isCloudSharingEnabled {
                        Button("Revoke shared space", role: .destructive) {
                            Task { await revokeInvitation() }
                        }
                        .disabled(isWorking)
                    }

                    if model.sharedSpace.isCurrentUserShareOwner == false,
                       model.sharedSpace.resolvedMembershipState == .accepted {
                        Button("Leave shared space", role: .destructive) {
                            Task { await leaveSpace() }
                        }
                        .disabled(isWorking)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }
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
            .task { availability = await sharingService.availability() }
        }
    }

    @ViewBuilder
    private var invitationAction: some View {
        if let invitationURL {
            ShareLink(item: invitationURL, subject: Text("Join \(space.name) on OpenTV")) {
                Label("Send private invitation", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity)
            }
            .adaptiveGlassButton(prominent: true)
        } else {
            Button {
                Task { await createInvitation() }
            } label: {
                if isWorking {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label(actionTitle, systemImage: "person.badge.plus")
                        .frame(maxWidth: .infinity)
                }
            }
            .adaptiveGlassButton(prominent: true)
            .disabled(isWorking || availability != .available)
        }
    }

    private var actionTitle: String {
        switch availability {
        case .available: "Create private invitation"
        case .iCloudAccountRequired: "Sign in to iCloud first"
        case .notConfigured: "Configure the iCloud container"
        case nil: "Checking iCloud…"
        }
    }

    private var invitationDescription: String {
        switch availability {
        case .iCloudAccountRequired: "Open Settings and sign in to iCloud, then return here. Your personal library stays local."
        case .notConfigured: "Select your Apple Developer team and enable the OpenTV CloudKit container for this app target."
        default: "Create an invitation-only iCloud space for your shared watchlist and watched-together activity."
        }
    }

    private func createInvitation() async {
        isWorking = true
        defer { isWorking = false }
        do {
            invitationURL = try await sharingService.inviteURL(for: space.id)
            model.markPartnerShareCreated()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func revokeInvitation() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await sharingService.revoke(spaceID: space.id)
            invitationURL = nil
            model.setSharedMembershipState(.revoked)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leaveSpace() async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await sharingService.leave(space: model.sharedSpace)
            model.setSharedMembershipState(.left)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    TogetherView()
        .environment(AppModel(store: MemoryLibraryStore(), seed: .sample))
        .environment(\.allowsRemoteArtwork, false)
}
