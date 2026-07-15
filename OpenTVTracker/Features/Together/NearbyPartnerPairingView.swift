import SwiftUI

enum NearbyPartnerPairingRole {
    case host(invitationURL: URL, displayName: String, spaceName: String)
    case join
}

struct NearbyPartnerPairingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var pairing = NearbyPartnerPairingService()
    @State private var selectedPartner: NearbyPartner?
    @State private var enteredPasscode = ""
    @State private var hasOpenedInvitation = false

    let role: NearbyPartnerPairingRole

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackdrop()

                ScrollView {
                    VStack(spacing: 24) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 54))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)

                        switch role {
                        case .host(_, _, let spaceName):
                            hostingContent(spaceName: spaceName)
                        case .join:
                            joiningContent
                        }
                    }
                    .padding(AppTheme.horizontalPadding)
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Pair nearby")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { start() }
            .onDisappear { pairing.stop() }
            .onChange(of: pairing.receivedInvitationURL) { _, invitationURL in
                guard let invitationURL, !hasOpenedInvitation else { return }
                hasOpenedInvitation = true
                openURL(invitationURL) { accepted in
                    if !accepted {
                        pairing.invitationCouldNotOpen()
                    }
                }
            }
        }
    }

    private func hostingContent(spaceName: String) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Connect to \(spaceName)")
                    .font(.title2.weight(.bold))
                Text("On your partner's iPhone, open Together, tap Connect partner, then Join nearby.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .pink) {
                VStack(spacing: 10) {
                    Text("PAIRING CODE")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(formattedPasscode)
                        .font(.system(.largeTitle, design: .monospaced, weight: .bold))
                        .textSelection(.enabled)
                        .accessibilityLabel("Pairing code \(pairing.passcode)")
                    Text("This code protects the private invitation and expires when you close this screen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }

            pairingStatus
        }
    }

    @ViewBuilder
    private var joiningContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Join your partner")
                    .font(.title2.weight(.bold))
                Text("Keep both iPhones nearby with OpenTV open. Choose your partner's phone below.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let selectedPartner {
                passcodeEntry(for: selectedPartner)
            } else {
                partnerList
            }

            pairingStatus
        }
    }

    @ViewBuilder
    private var partnerList: some View {
        if pairing.partners.isEmpty {
            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Looking for your partner's iPhone…")
                        .font(.headline)
                    Text("If no phone appears, check that Pair nearby is open on the other iPhone.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(20)
            }
        } else {
            GlassSurface(cornerRadius: AppTheme.compactRadius) {
                VStack(spacing: 0) {
                    ForEach(pairing.partners) { partner in
                        Button {
                            selectedPartner = partner
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "iphone.radiowaves.left.and.right")
                                    .font(.title2)
                                    .foregroundStyle(Color.accentColor)
                                Text(partner.name)
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.bold))
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(16)
                            .contentShape(.rect)
                        }
                        .buttonStyle(.plain)

                        if partner.id != pairing.partners.last?.id {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
            }
        }
    }

    private func passcodeEntry(for partner: NearbyPartner) -> some View {
        GlassSurface(cornerRadius: AppTheme.compactRadius, tint: .pink) {
            VStack(alignment: .leading, spacing: 16) {
                Label(partner.name, systemImage: "iphone.radiowaves.left.and.right")
                    .font(.headline)

                TextField("Six-digit code", text: $enteredPasscode)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
                    .font(.system(.title2, design: .monospaced, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .padding(12)
                    .background(.quaternary, in: .rect(cornerRadius: 12))
                    .accessibilityHint("Enter the code shown on your partner's iPhone")
                    .onChange(of: enteredPasscode) { _, newValue in
                        enteredPasscode = String(newValue.filter(\.isNumber).prefix(6))
                    }

                Button("Connect phones", systemImage: "link") {
                    pairing.connect(to: partner, passcode: enteredPasscode)
                }
                .frame(maxWidth: .infinity)
                .adaptiveGlassButton(prominent: true)
                .disabled(enteredPasscode.count != 6 || isConnecting)

                Button("Choose another iPhone") {
                    selectedPartner = nil
                    enteredPasscode = ""
                    pairing.startBrowsing()
                }
                .frame(maxWidth: .infinity)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private var pairingStatus: some View {
        switch pairing.state {
        case .idle, .starting:
            Label("Starting secure nearby pairing…", systemImage: "lock")
                .foregroundStyle(.secondary)
        case .advertising:
            Label("Waiting for your partner", systemImage: "antenna.radiowaves.left.and.right")
                .foregroundStyle(.secondary)
        case .browsing:
            Label("Searching nearby", systemImage: "magnifyingglass")
                .foregroundStyle(.secondary)
        case .connecting(let name):
            Label("Connecting to \(name)…", systemImage: "link")
                .foregroundStyle(.secondary)
        case .transferring:
            Label("Sending private invitation…", systemImage: "lock.shield")
                .foregroundStyle(.secondary)
        case .completed:
            Label(completionMessage, systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
                .sensoryFeedback(.success, trigger: pairing.state)
        case .failed(let message):
            VStack(spacing: 12) {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                Button("Try again") { retry() }
            }
        }
    }

    private var formattedPasscode: String {
        pairing.passcode.map(String.init).joined(separator: " ")
    }

    private var isConnecting: Bool {
        switch pairing.state {
        case .connecting, .transferring:
            true
        default:
            false
        }
    }

    private var completionMessage: String {
        switch role {
        case .host: "Invitation sent"
        case .join: "Opening private invitation…"
        }
    }

    private func start() {
        switch role {
        case .host(let invitationURL, let displayName, _):
            pairing.startHosting(invitationURL: invitationURL, displayName: displayName)
        case .join:
            pairing.startBrowsing()
        }
    }

    private func retry() {
        enteredPasscode = ""
        selectedPartner = nil
        hasOpenedInvitation = false
        start()
    }
}

#Preview("Host nearby pairing") {
    NearbyPartnerPairingView(
        role: .host(
            invitationURL: URL(string: "https://www.icloud.com/share/example")!,
            displayName: "Vincent",
            spaceName: "Our space"
        )
    )
}
