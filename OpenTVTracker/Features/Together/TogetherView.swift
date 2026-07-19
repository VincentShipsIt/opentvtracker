import SwiftUI

struct TogetherView: View {
    @Environment(AppModel.self) private var model
    @State private var presentedSheet: TogetherSheet?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    LazyVStack(spacing: AppTheme.sectionSpacing) {
                        spaceHeader
                        sharedWatchlist
                        recentActivity
                        analyticsLink
                    }
                    .padding(.horizontal, AppTheme.horizontalPadding)
                    .padding(.bottom, 32)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Connect partner", systemImage: "person.badge.plus") {
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
            SectionHeading(
                title: "Our shows",
                subtitle: "\(model.sharedTitles.count) shared titles · progress follows seasons and episodes"
            )
            if model.sharedTitles.isEmpty {
                ContentUnavailableView(
                    "No shared shows yet",
                    systemImage: "person.2.badge.plus",
                    description: Text("Add a title to Our watchlist from its details page.")
                )
                .frame(minHeight: 180)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.sharedTitles) { title in
                        NavigationLink(value: title) {
                            MediaProgressRow(
                                title: title,
                                summary: model.togetherProgressSummary(for: title),
                                subtitle: sharedTitleSubtitle(for: title)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var analyticsLink: some View {
        NavigationLink {
            ViewingAnalyticsView(scope: .together)
        } label: {
            ViewingAnalyticsPreviewCard(
                summary: ViewingAnalyticsEngine.summarize(snapshot: model.snapshot, scope: .together)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("together.viewing-analytics")
    }

    private func sharedTitleSubtitle(for title: MediaTitle) -> String {
        if title.kind == .movie { return "Shared movie" }
        return title.state == .planned ? "Shared watchlist" : "Watching together"
    }

    @ViewBuilder
    private var recentActivity: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: "Recent activity", subtitle: "Spoiler-safe by default")
            if model.togetherActivity.isEmpty {
                ContentUnavailableView(
                    "Nothing watched together yet",
                    systemImage: "rectangle.stack.badge.plus",
                    description: Text("Your shared watch history will appear here as cards.")
                )
                .frame(minHeight: 220)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(model.togetherActivity) { activity in
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

struct PartnerInvitationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let space: SharedSpace
    private let sharingService: any PartnerSharingProviding = CloudKitPartnerSharingService()
    @State private var availability: PartnerSharingAvailability?
    @State private var invitationURL: URL?
    @State private var nearbyPairingRoute: NearbyPairingRoute?
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
                        Text("Connect someone to \(space.name)")
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

                    nearbyPairingActions

                    if model.sharedSpace.isCurrentUserShareOwner != false {
                        VStack(spacing: 10) {
                            Text("OR SEND A LINK")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            invitationAction
                        }
                    }

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
            .navigationTitle("Connect partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { availability = await sharingService.availability() }
            .sheet(item: $nearbyPairingRoute) { route in
                switch route {
                case .host(let invitationURL):
                    NearbyPartnerPairingView(
                        role: .host(
                            invitationURL: invitationURL,
                            displayName: currentMemberName,
                            spaceName: space.name
                        )
                    )
                case .join:
                    NearbyPartnerPairingView(role: .join)
                }
            }
        }
    }

    private var nearbyPairingActions: some View {
        VStack(spacing: 12) {
            if model.sharedSpace.isCurrentUserShareOwner != false,
               model.sharedSpace.resolvedMembershipState != .accepted {
                Button {
                    Task { await prepareNearbyHosting() }
                } label: {
                    if isWorking {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Label("Pair nearby", systemImage: "dot.radiowaves.left.and.right")
                            .frame(maxWidth: .infinity)
                    }
                }
                .adaptiveGlassButton(prominent: true)
                .disabled(isWorking || availability != .available)
                .accessibilityHint("Creates a secure code to connect a nearby partner's iPhone")
            }

            if !model.sharedSpace.isCloudSharingEnabled {
                Button("Join partner nearby", systemImage: "iphone.radiowaves.left.and.right") {
                    nearbyPairingRoute = .join
                }
                .frame(maxWidth: .infinity)
                .adaptiveGlassButton()
                .disabled(isWorking || availability != .available)
                .accessibilityHint("Finds a partner who is showing a nearby pairing code")
            }
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
        default: "Pair nearby without sending a link. OpenTV securely hands off the invitation, then iCloud keeps your shared space in sync."
        }
    }

    private var currentMemberName: String {
        model.sharedSpace.members.first(where: \.isCurrentUser)?.name ?? "Partner"
    }

    private func prepareNearbyHosting() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await sharingService.inviteURL(for: space.id)
            model.markPartnerShareCreated()
            await model.flushSharedState()
            invitationURL = url
            errorMessage = nil
            nearbyPairingRoute = .host(url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createInvitation() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await sharingService.inviteURL(for: space.id)
            model.markPartnerShareCreated()
            await model.flushSharedState()
            invitationURL = url
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
