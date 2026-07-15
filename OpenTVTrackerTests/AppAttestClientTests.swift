import CryptoKit
import XCTest
@testable import OpenTVTracker

final class AppAttestClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testRegistersThenSignsExactCatalogRequestAndPersistsCredentials() async throws {
        let service = MockAppAttestService(isSupported: true)
        let store = MemorySecureCredentialStore()
        TestURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            if path == "/v1/app-attest/challenge" {
                let body = try XCTUnwrap(request.httpBody)
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                let purpose = try XCTUnwrap(json["purpose"])
                let challenge = purpose == "attestation" ? "registration-challenge" : "request-challenge"
                let identifier = purpose == "attestation" ? "registration-id" : "request-id"
                if purpose == "request" {
                    XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "AppAttest short-lived-token")
                }
                return try Self.jsonResponse(request, status: 201, body: [
                    "id": identifier,
                    "challenge": challenge,
                    "expiresAt": "2030-01-01T00:00:00Z"
                ])
            }
            if path == "/v1/app-attest/register" {
                return try Self.jsonResponse(request, status: 201, body: [
                    "token": "short-lived-token",
                    "expiresAt": "2030-01-01T00:00:00Z"
                ])
            }
            XCTAssertEqual(path, "/v1/catalog/search")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Attest-Key-ID"), "secure-enclave-key")
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-App-Attest-Challenge-ID"), "request-id")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "X-App-Attest-Assertion"))
            return try Self.jsonResponse(request, status: 200, body: ["results": []])
        }
        let client = AppAttestClient(
            baseURL: URL(string: "https://proxy.example/")!,
            session: TestURLProtocol.session(),
            appAttest: service,
            credentialStore: store,
            developmentToken: nil,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
        let requestURL = URL(string: "https://proxy.example/v1/catalog/search?q=Drama&page=1&region=MT")!

        let (_, response) = try await client.data(for: URLRequest(url: requestURL))

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(store.writtenAccounts, [AppAttestClient.credentialsAccount])
        XCTAssertEqual(service.attestationHashes, [Data(SHA256.hash(data: Data("registration-challenge".utf8)))])
        assertRecordedHashes(service)
    }

    private func assertRecordedHashes(_ service: MockAppAttestService) {
        let emptyBodyHash = Data(SHA256.hash(data: Data())).base64URLEncodedString()
        let payload = [
            "opentv-app-attest-v1",
            "request-challenge",
            "GET",
            "/v1/catalog/search?q=Drama&page=1&region=MT",
            emptyBodyHash
        ].joined(separator: "\n")
        XCTAssertEqual(service.assertionHashes, [Data(SHA256.hash(data: Data(payload.utf8)))])
    }

    func testUnsupportedDeviceFailsGracefullyWithoutCallingHostedProxy() async {
        let service = MockAppAttestService(isSupported: false)
        let client = AppAttestClient(
            baseURL: URL(string: "https://proxy.example/")!,
            session: TestURLProtocol.session(),
            appAttest: service,
            credentialStore: MemorySecureCredentialStore(),
            developmentToken: nil
        )

        do {
            _ = try await client.data(for: URLRequest(url: URL(string: "https://proxy.example/v1/catalog/search")!))
            XCTFail("Expected unsupported device error")
        } catch let error as AppAttestClientError {
            guard case .unsupportedDevice = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private static func jsonResponse(
        _ request: URLRequest,
        status: Int,
        body: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [
                "Content-Type": "application/json"
            ])!,
            try JSONSerialization.data(withJSONObject: body)
        )
    }
}

final class MockAppAttestService: AppAttestServicing, @unchecked Sendable {
    let isSupported: Bool
    private let lock = NSLock()
    private(set) var attestationHashes: [Data] = []
    private(set) var assertionHashes: [Data] = []

    init(isSupported: Bool) {
        self.isSupported = isSupported
    }

    func generateKey() async throws -> String { "secure-enclave-key" }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        lock.withLock { attestationHashes.append(clientDataHash) }
        return Data("attestation-object".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        lock.withLock { assertionHashes.append(clientDataHash) }
        return Data("assertion-object".utf8)
    }
}
