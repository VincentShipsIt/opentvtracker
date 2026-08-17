import SwiftUI

struct PartnerInvitationRequestGate {
    private(set) var isRunning = false

    mutating func begin() -> Bool {
        guard !isRunning else { return false }
        isRunning = true
        return true
    }

    mutating func finish() {
        isRunning = false
    }
}

struct PartnerInvitationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let space: SharedSpace
    let sharingService: any PartnerSharingProviding
    @State private var availability: PartnerSharingAvailability?
    @State private var invitationLinks: [PartnerInvitationLink] = []
    @State private var nearbyPairingRoute: NearbyPairingRoute?
    @State private var requestGate = PartnerInvitationRequestGate()
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()
                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "person.2.badge.gearshape.fill")
                            .font(.system(size: 54))
                            .foregroundStyle(.tint)
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
                                invitationLinksList
                                invitationAction
                            }
                        }

                        if model.sharedSpace.isCurrentUserShareOwner == true,
                           model.sharedSpace.isCloudSharingEnabled {
                            Button("Revoke shared space", role: .destructive) {
                                beginRevokingInvitation()
                            }
                            .disabled(isWorking)
                        }

                        if model.sharedSpace.isCurrentUserShareOwner == false,
                           model.sharedSpace.resolvedMembershipState == .accepted {
                            Button("Leave shared space", role: .destructive) {
                                beginLeavingSpace()
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
                    .padding(.vertical, 8)
                }
            }
            // This sheet is presented from its own environment root, so without this the
            // backdrop falls back to the personal hue while every control on it is tinted
            // for the shared space.
            .environment(\.appSpaceMode, .shared)
            .navigationTitle("Connect partner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                await refreshAvailability()
                await refreshInvitationLinks()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task {
                    await refreshAvailability()
                    await refreshInvitationLinks()
                }
            }
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
        // A sheet inherits the environment of whatever presented it, and this one is
        // presented from onboarding as well as from the shared space. It belongs to the
        // shared space either way, so it declares that tint rather than inheriting a
        // personal one.
        .tint(AppSpaceMode.shared.accent)
    }

    private var nearbyPairingActions: some View {
        VStack(spacing: 12) {
            if model.sharedSpace.isCurrentUserShareOwner != false,
               model.sharedSpace.resolvedMembershipState != .accepted {
                Button {
                    beginNearbyHosting()
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
                .accessibilityHint("Creates a fresh private invitation and a secure code to connect a nearby partner's iPhone")
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
    private var invitationLinksList: some View {
        if !invitationLinks.isEmpty {
            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(invitationLinks.enumerated()), id: \.element.id) { index, link in
                        HStack(alignment: .center, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(index == 0 ? "Latest invitation" : "Private invitation")
                                    .font(.subheadline.weight(.semibold))
                                Text(link.createdAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            ShareLink(
                                item: link.url,
                                subject: Text("Join \(space.name) on OpenTV")
                            ) {
                                Label("Send again", systemImage: "square.and.arrow.up")
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("together.invitation-link")
                    }
                }
                .padding(16)
            }
            .accessibilityIdentifier("together.invitation-links")
        }
    }

    @ViewBuilder
    private var invitationAction: some View {
        Button {
            beginCreatingInvitation()
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

    private var actionTitle: String {
        switch availability {
        case .available:
            invitationLinks.isEmpty ? "Create private invitation" : "Create another invitation"
        case .iCloudAccountRequired: "Sign in to iCloud first"
        case .notConfigured: "Configure the iCloud container"
        case nil: "Checking iCloud…"
        }
    }

    private var invitationDescription: String {
        switch availability {
        case .iCloudAccountRequired:
            "Open Settings and sign in to iCloud, then return here. Your personal library stays local."
        case .notConfigured:
            "Select your Apple Developer team and enable the OpenTV CloudKit container for this app target."
        default:
            "Pair nearby without sending a link. OpenTV securely hands off the invitation, then iCloud keeps your shared space in sync."
        }
    }

    private var currentMemberName: String {
        model.sharedSpace.members.first(where: \.isCurrentUser)?.name ?? "Partner"
    }

    private var isWorking: Bool {
        requestGate.isRunning
    }

    private func beginNearbyHosting() {
        guard requestGate.begin() else { return }
        Task { await prepareNearbyHosting() }
    }

    private func beginCreatingInvitation() {
        guard requestGate.begin() else { return }
        Task { await createInvitation() }
    }

    private func beginRevokingInvitation() {
        guard requestGate.begin() else { return }
        Task { await revokeInvitation() }
    }

    private func beginLeavingSpace() {
        guard requestGate.begin() else { return }
        Task { await leaveSpace() }
    }

    private func requestInvitation() async -> URL? {
        defer { requestGate.finish() }
        do {
            let url = try await sharingService.inviteURL(for: space.id)
            model.markPartnerShareCreated()
            await model.flushSharedState()
            errorMessage = nil
            await refreshInvitationLinks()
            return url
        } catch {
            errorMessage = error.localizedDescription
            await refreshInvitationLinks()
            return nil
        }
    }

    private func prepareNearbyHosting() async {
        // CloudKit one-time invitation URLs are spent after the first open.
        // Nearby join has to receive a freshly minted URL every pairing attempt.
        guard let url = await requestInvitation() else { return }
        nearbyPairingRoute = .host(url)
    }

    private func createInvitation() async {
        _ = await requestInvitation()
    }

    private func refreshAvailability() async {
        availability = await sharingService.availability()
    }

    private func refreshInvitationLinks() async {
        do {
            invitationLinks = try await sharingService.invitationLinks(for: space.id)
        } catch {
            return
        }
    }

    private func revokeInvitation() async {
        defer { requestGate.finish() }
        do {
            try await sharingService.revoke(spaceID: space.id)
            invitationLinks = []
            model.setSharedMembershipState(.revoked)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func leaveSpace() async {
        defer { requestGate.finish() }
        do {
            try await sharingService.leave(space: model.sharedSpace)
            model.setSharedMembershipState(.left)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
