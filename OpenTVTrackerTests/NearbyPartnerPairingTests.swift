import Foundation
import XCTest
@testable import OpenTVTracker

final class NearbyPartnerPairingTests: XCTestCase {
    func testInvitationRoundTripsThroughNearbyPayload() throws {
        let invitationURL = try XCTUnwrap(URL(string: "https://www.icloud.com/share/example-token"))

        let payload = try NearbyPartnerInvitationCodec.encode(invitationURL: invitationURL)
        let decodedURL = try NearbyPartnerInvitationCodec.decode(payload)

        XCTAssertEqual(decodedURL, invitationURL)
        XCTAssertEqual(payload.last, 0x0A)
    }

    func testEncodingRejectsNonCloudKitURL() throws {
        let untrustedURL = try XCTUnwrap(URL(string: "https://example.com/share/token"))

        XCTAssertThrowsError(
            try NearbyPartnerInvitationCodec.encode(invitationURL: untrustedURL)
        )
    }

    func testDecodingRejectsPayloadWithoutTerminator() throws {
        let payload = Data(
            #"{"version":1,"invitationURL":"https:\/\/www.icloud.com\/share\/token"}"#.utf8
        )

        XCTAssertThrowsError(try NearbyPartnerInvitationCodec.decode(payload))
    }

    func testDecodingRejectsUnsupportedPayloadVersion() throws {
        var payload = Data(
            #"{"version":2,"invitationURL":"https:\/\/www.icloud.com\/share\/token"}"#.utf8
        )
        payload.append(0x0A)

        XCTAssertThrowsError(try NearbyPartnerInvitationCodec.decode(payload))
    }
}
