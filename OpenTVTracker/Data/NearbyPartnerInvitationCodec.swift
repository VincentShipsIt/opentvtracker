import Foundation

enum NearbyPartnerPairingError: LocalizedError {
    case invalidInvitation
    case invalidPasscode
    case payloadTooLarge

    var errorDescription: String? {
        switch self {
        case .invalidInvitation:
            "The nearby phone did not send a valid OpenTV invitation."
        case .invalidPasscode:
            "Enter the six-digit code shown on your partner's iPhone."
        case .payloadTooLarge:
            "The nearby invitation was larger than OpenTV allows."
        }
    }
}

enum NearbyPartnerInvitationCodec {
    static let maximumPayloadSize = 4_096

    private struct Payload: Codable {
        let version: Int
        let invitationURL: URL
    }

    static func encode(invitationURL: URL) throws -> Data {
        guard isCloudKitInvitation(invitationURL) else {
            throw NearbyPartnerPairingError.invalidInvitation
        }

        var data = try JSONEncoder().encode(Payload(version: 1, invitationURL: invitationURL))
        data.append(0x0A)
        guard data.count <= maximumPayloadSize else {
            throw NearbyPartnerPairingError.payloadTooLarge
        }
        return data
    }

    static func decode(_ data: Data) throws -> URL {
        guard data.count <= maximumPayloadSize,
              data.last == 0x0A else {
            throw NearbyPartnerPairingError.invalidInvitation
        }

        let payload = try JSONDecoder().decode(Payload.self, from: Data(data.dropLast()))
        guard payload.version == 1,
              isCloudKitInvitation(payload.invitationURL) else {
            throw NearbyPartnerPairingError.invalidInvitation
        }
        return payload.invitationURL
    }

    private static func isCloudKitInvitation(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == "icloud.com" || host.hasSuffix(".icloud.com") else {
            return false
        }
        return url.path.hasPrefix("/share/")
    }
}
