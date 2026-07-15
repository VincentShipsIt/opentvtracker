import CryptoKit
import Foundation
import Network
import Observation

struct NearbyPartner: Identifiable, Hashable, Sendable {
    let result: NWBrowser.Result

    var id: NWEndpoint { result.endpoint }

    var name: String {
        guard case let .service(name, _, _, _) = result.endpoint else {
            return "Nearby iPhone"
        }
        return name
    }
}

enum NearbyPartnerPairingState: Equatable {
    case idle
    case starting
    case advertising
    case browsing
    case connecting(String)
    case transferring
    case completed
    case failed(String)
}

@MainActor
@Observable
final class NearbyPartnerPairingService {
    static let serviceType = "_opentv-pair._tcp"

    private(set) var state: NearbyPartnerPairingState = .idle
    private(set) var passcode = ""
    private(set) var partners: [NearbyPartner] = []
    private(set) var receivedInvitationURL: URL?

    private let queue = DispatchQueue(label: "dev.shipshit.opentvtracker.nearby-pairing")
    private var listener: NWListener?
    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var invitationURL: URL?

    func startHosting(invitationURL: URL, displayName: String) {
        stop()
        do {
            _ = try NearbyPartnerInvitationCodec.encode(invitationURL: invitationURL)
            let passcode = String(format: "%06d", Int.random(in: 0...999_999))
            let listener = try NWListener(using: .nearbyPartnerPairing(passcode: passcode))
            listener.newConnectionLimit = 1
            listener.service = NWListener.Service(
                name: NearbyPartnerPairingSupport.advertisedName(from: displayName),
                type: Self.serviceType
            )
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor [weak self] in
                    self?.handleListenerState(state)
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                Task { @MainActor [weak self] in
                    self?.accept(connection)
                }
            }

            self.invitationURL = invitationURL
            self.passcode = passcode
            self.listener = listener
            state = .starting
            listener.start(queue: queue)
        } catch {
            fail(error.localizedDescription)
        }
    }

    func startBrowsing() {
        stop()
        let parameters = NWParameters()
        parameters.includePeerToPeer = true
        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: parameters
        )
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor [weak self] in
                self?.handleBrowserState(state)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.partners = results
                    .map(NearbyPartner.init(result:))
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }
        }

        self.browser = browser
        state = .starting
        browser.start(queue: queue)
    }

    func connect(to partner: NearbyPartner, passcode: String) {
        let normalizedPasscode = passcode.filter(\.isNumber)
        guard normalizedPasscode.count == 6 else {
            state = .failed(NearbyPartnerPairingError.invalidPasscode.localizedDescription)
            return
        }

        browser?.cancel()
        browser = nil
        let connection = NWConnection(
            to: partner.result.endpoint,
            using: .nearbyPartnerPairing(passcode: normalizedPasscode)
        )
        self.connection = connection
        state = .connecting(partner.name)
        connection.stateUpdateHandler = { [weak self, weak connection] connectionState in
            guard let connection else { return }
            Task { @MainActor [weak self] in
                self?.handleJoiningConnectionState(connectionState, connection: connection)
            }
        }
        connection.start(queue: queue)
    }

    func stop() {
        listener?.cancel()
        browser?.cancel()
        connection?.cancel()
        listener = nil
        browser = nil
        connection = nil
        invitationURL = nil
        passcode = ""
        partners = []
        receivedInvitationURL = nil
        state = .idle
    }

    func invitationCouldNotOpen() {
        fail("OpenTV could not open the private invitation. Ask your partner to try pairing again.")
    }

    private func handleListenerState(_ listenerState: NWListener.State) {
        switch listenerState {
        case .ready:
            state = .advertising
        case .failed:
            fail(NearbyPartnerPairingSupport.localNetworkMessage)
        case .cancelled:
            break
        case .setup, .waiting:
            state = .starting
        @unknown default:
            state = .starting
        }
    }

    private func handleBrowserState(_ browserState: NWBrowser.State) {
        switch browserState {
        case .ready:
            state = .browsing
        case .failed:
            fail(NearbyPartnerPairingSupport.localNetworkMessage)
        case .cancelled:
            break
        case .setup, .waiting:
            state = .starting
        @unknown default:
            state = .starting
        }
    }

    private func accept(_ incomingConnection: NWConnection) {
        guard connection == nil else {
            incomingConnection.cancel()
            return
        }

        connection = incomingConnection
        incomingConnection.stateUpdateHandler = { [weak self, weak incomingConnection] connectionState in
            guard let incomingConnection else { return }
            Task { @MainActor [weak self] in
                self?.handleHostingConnectionState(connectionState, connection: incomingConnection)
            }
        }
        incomingConnection.start(queue: queue)
    }

    private func handleHostingConnectionState(
        _ connectionState: NWConnection.State,
        connection: NWConnection
    ) {
        switch connectionState {
        case .ready:
            sendInvitation(over: connection)
        case .failed:
            self.connection = nil
            state = .advertising
        case .cancelled:
            self.connection = nil
        default:
            break
        }
    }

    private func handleJoiningConnectionState(
        _ connectionState: NWConnection.State,
        connection: NWConnection
    ) {
        switch connectionState {
        case .ready:
            state = .transferring
            receiveInvitation(over: connection, accumulated: Data())
        case .failed:
            fail("The phones could not pair. Check the six-digit code and try again.")
        case .cancelled:
            break
        default:
            break
        }
    }

    private func sendInvitation(over connection: NWConnection) {
        guard let invitationURL else {
            fail(NearbyPartnerPairingError.invalidInvitation.localizedDescription)
            return
        }

        do {
            let payload = try NearbyPartnerInvitationCodec.encode(invitationURL: invitationURL)
            state = .transferring
            connection.send(
                content: payload,
                contentContext: .finalMessage,
                isComplete: true,
                completion: .contentProcessed { [weak self] error in
                    Task { @MainActor [weak self] in
                        if let error {
                            self?.fail("The invitation could not be sent: \(error.localizedDescription)")
                        } else {
                            self?.state = .completed
                            self?.listener?.cancel()
                            self?.listener = nil
                        }
                    }
                }
            )
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func receiveInvitation(over connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1_024) { [weak self] content, _, isComplete, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                var buffer = accumulated
                if let content {
                    buffer.append(content)
                }
                guard buffer.count <= NearbyPartnerInvitationCodec.maximumPayloadSize else {
                    fail(NearbyPartnerPairingError.payloadTooLarge.localizedDescription)
                    return
                }

                if let terminator = buffer.firstIndex(of: 0x0A) {
                    do {
                        let payload = Data(buffer[...terminator])
                        receivedInvitationURL = try NearbyPartnerInvitationCodec.decode(payload)
                        state = .completed
                        connection.cancel()
                    } catch {
                        fail(error.localizedDescription)
                    }
                    return
                }

                if let error {
                    fail("The nearby invitation was interrupted: \(error.localizedDescription)")
                } else if isComplete {
                    fail(NearbyPartnerPairingError.invalidInvitation.localizedDescription)
                } else {
                    receiveInvitation(over: connection, accumulated: buffer)
                }
            }
        }
    }

    private func fail(_ message: String) {
        listener?.cancel()
        browser?.cancel()
        connection?.cancel()
        listener = nil
        browser = nil
        connection = nil
        state = .failed(message)
    }

}

private enum NearbyPartnerPairingSupport {
    static let localNetworkMessage =
        "Nearby pairing is unavailable. Allow OpenTV to access the Local Network in Settings, then try again."

    static func advertisedName(from displayName: String) -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "OpenTV partner" : "OpenTV · \(trimmed)"
        return String(name.prefix(40))
    }

}

private extension NWParameters {
    static func nearbyPartnerPairing(passcode: String) -> NWParameters {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 2

        let parameters = NWParameters(
            tls: nearbyPartnerTLSOptions(passcode: passcode),
            tcp: tcpOptions
        )
        parameters.includePeerToPeer = true
        parameters.acceptLocalOnly = true
        return parameters
    }

    static func nearbyPartnerTLSOptions(passcode: String) -> NWProtocolTLS.Options {
        let tlsOptions = NWProtocolTLS.Options()
        let key = SymmetricKey(data: Data(passcode.utf8))
        let authenticationCode = HMAC<SHA256>.authenticationCode(
            for: Data("OpenTVNearbyPairing/v1".utf8),
            using: key
        )
        let keyData = authenticationCode.withUnsafeBytes { DispatchData(bytes: $0) }
        let identityData = Data("OpenTVNearbyPairing".utf8).withUnsafeBytes { DispatchData(bytes: $0) }

        sec_protocol_options_add_pre_shared_key(
            tlsOptions.securityProtocolOptions,
            keyData as __DispatchData,
            identityData as __DispatchData
        )
        sec_protocol_options_append_tls_ciphersuite(
            tlsOptions.securityProtocolOptions,
            tls_ciphersuite_t(rawValue: TLS_PSK_WITH_AES_128_GCM_SHA256)!
        )
        return tlsOptions
    }
}
