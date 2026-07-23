import SwiftUI

struct PartnerSetupHero: View {
    let phase: TogetherConnectionPhase
    let availability: PartnerSharingAvailability?
    let space: SharedSpace
    @Binding var presentedSheet: TogetherSheet?

    var body: some View {
        GlassSurface(tint: .pink) {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: heroSymbol)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 8) {
                    Text(heroTitle)
                        .font(.largeTitle.weight(.bold))
                    Text(heroDescription)
                        .foregroundStyle(.secondary)
                }

                Label(connectionMessage, systemImage: connectionSymbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(connectionColor)
                    .accessibilityIdentifier("together.connection-status")

                VStack(alignment: .leading, spacing: 12) {
                    Label("Invitation-only", systemImage: "person.crop.circle.badge.checkmark")
                    Label("No OpenTV password", systemImage: "key.slash")
                    Label("Separate from your personal library", systemImage: "rectangle.on.rectangle.slash")
                    Label("Private iCloud synchronization", systemImage: "lock.icloud")
                }
                .font(.subheadline)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Privacy and trust")

                Button {
                    presentedSheet = .invite
                } label: {
                    Label(actionTitle, systemImage: actionSymbol)
                        .frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .adaptiveGlassButton(prominent: true)
                .accessibilityIdentifier("together.invite-partner")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
    }

    private var heroTitle: String {
        switch phase {
        case .unconnected: "Watch together, privately"
        case .waitingForPartner: "Your invitation is ready"
        case .revoked: "This shared space was revoked"
        case .expired: "This invitation expired"
        case .left: "You left the shared space"
        case .connected: space.name
        }
    }

    private var heroDescription: String {
        switch phase {
        case .unconnected:
            "Connect one partner, then coordinate a shared watchlist and progress without creating another account."
        case .waitingForPartner:
            "OpenTV is waiting for your partner to accept. You can reopen the invitation or pair nearby."
        case .revoked:
            "Shared data is no longer available on this device. Start a new private invitation when you are ready."
        case .expired:
            "Create a fresh invitation or join your partner nearby to reconnect this device."
        case .left:
            "Your personal library is unchanged. Join another invitation when you want to watch together again."
        case .connected:
            "Your private shared watch space."
        }
    }

    private var heroSymbol: String {
        switch phase {
        case .waitingForPartner: "paperplane.fill"
        case .revoked, .expired: "person.2.slash"
        case .left: "rectangle.portrait.and.arrow.right"
        case .unconnected, .connected: "person.2.fill"
        }
    }

    private var connectionMessage: String {
        switch availability {
        case .iCloudAccountRequired:
            "Sign in to iCloud to use private partner sharing"
        case .notConfigured:
            "Private sharing is unavailable in this build"
        case .available:
            phase == .waitingForPartner ? "Waiting for your partner" : "Ready for private iCloud sharing"
        case nil:
            "Checking private iCloud sharing…"
        }
    }

    private var connectionSymbol: String {
        switch availability {
        case .available: "lock.icloud.fill"
        case .iCloudAccountRequired: "person.crop.circle.badge.exclamationmark"
        case .notConfigured: "exclamationmark.icloud"
        case nil: "icloud"
        }
    }

    private var connectionColor: Color {
        switch availability {
        case .available: .green
        case .iCloudAccountRequired, .notConfigured: .orange
        case nil: .secondary
        }
    }

    private var actionTitle: String {
        switch phase {
        case .unconnected: space.isCurrentUserShareOwner == false ? "Join a partner" : "Connect a partner"
        case .waitingForPartner: "Manage invitation"
        case .revoked, .expired: space.isCurrentUserShareOwner == false ? "Join another space" : "Create a new invitation"
        case .left: "Join another space"
        case .connected: "Manage sharing"
        }
    }

    private var actionSymbol: String {
        switch phase {
        case .waitingForPartner: "paperplane"
        case .left: "iphone.radiowaves.left.and.right"
        case .unconnected, .revoked, .expired, .connected: "person.badge.plus"
        }
    }
}

struct TogetherSpaceHeader: View {
    let space: SharedSpace
    let availability: PartnerSharingAvailability?
    @Binding var presentedSheet: TogetherSheet?

    var body: some View {
        GlassSurface(tint: .pink) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(space.name)
                            .font(.largeTitle.weight(.bold))
                        Text("One private space. Your pace or ours.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TogetherMemberStack(members: space.members)
                }

                Label(syncStatus.title, systemImage: syncStatus.symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(syncStatus.color)
                    .accessibilityIdentifier("together.connection-status")

                Label(roleLabel, systemImage: space.isCurrentUserShareOwner == false ? "person.2" : "crown")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button {
                    presentedSheet = .invite
                } label: {
                    Label("Manage private sharing", systemImage: "person.2.badge.gearshape")
                        .frame(maxWidth: .infinity)
                }
                .adaptiveGlassButton()
                .accessibilityIdentifier("together.manage-sharing")
            }
            .padding(18)
        }
    }

    private var roleLabel: String {
        space.isCurrentUserShareOwner == false ? "Shared with you" : "You manage this private space"
    }

    private var syncStatus: SharingStatusStyle {
        switch availability {
        case .available:
            SharingStatusStyle(title: "Synced privately with iCloud", symbol: "lock.icloud.fill", color: .green)
        case .iCloudAccountRequired:
            SharingStatusStyle(
                title: "Sign in to iCloud to resume shared updates",
                symbol: "person.crop.circle.badge.exclamationmark",
                color: .orange
            )
        case .notConfigured:
            SharingStatusStyle(
                title: "Private sharing is unavailable in this build",
                symbol: "exclamationmark.icloud",
                color: .orange
            )
        case nil:
            SharingStatusStyle(title: "Checking private iCloud sync…", symbol: "icloud", color: .secondary)
        }
    }
}

private struct SharingStatusStyle {
    let title: String
    let symbol: String
    let color: Color
}

private struct TogetherMemberStack: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption2) private var avatarSize: CGFloat = 38
    let members: [SpaceMember]

    var body: some View {
        HStack(spacing: dynamicTypeSize.isAccessibilitySize ? 6 : -8) {
            ForEach(members) { member in
                Text(AppAccessibility.displayedInitials(member.initials))
                    .font(.caption2.weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: avatarSize, height: avatarSize)
                    .background(Color.accentColor.gradient, in: Circle())
                    .foregroundStyle(.white)
                    .overlay { Circle().stroke(.background, lineWidth: 2) }
                    .accessibilityLabel(member.name)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Members")
    }
}
