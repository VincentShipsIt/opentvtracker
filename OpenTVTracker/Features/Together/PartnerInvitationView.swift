import SwiftUI

struct PartnerInvitationView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    let space: SharedSpace
    let sharingService: any PartnerSharingProviding
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
            .task { await refreshAvailability() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshAvailability() }
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

    private func requestInvitation() async -> URL? {
        isWorking = true
        defer { isWorking = false }
        do {
            let url = try await sharingService.inviteURL(for: space.id)
            model.markPartnerShareCreated()
            await model.flushSharedState()
            invitationURL = url
            errorMessage = nil
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func prepareNearbyHosting() async {
        guard let url = await requestInvitation() else { return }
        nearbyPairingRoute = .host(url)
    }

    private func createInvitation() async {
        _ = await requestInvitation()
    }

    private func refreshAvailability() async {
        availability = await sharingService.availability()
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
