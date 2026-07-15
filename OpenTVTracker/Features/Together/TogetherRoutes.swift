import Foundation

enum TogetherSheet: String, Identifiable {
    case invite

    var id: String { rawValue }
}

enum NearbyPairingRoute: Identifiable {
    case host(URL)
    case join

    var id: String {
        switch self {
        case .host(let invitationURL): "host-\(invitationURL.absoluteString)"
        case .join: "join"
        }
    }
}
