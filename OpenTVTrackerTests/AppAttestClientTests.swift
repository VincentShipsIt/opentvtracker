import CryptoKit
import XCTest
@testable import OpenTVTracker

final class AppAttestClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        TestURLProtocol.asyncHandler = nil
        super.tearDown()
    }

}

extension AppAttestClientTests {
    func assertRecordedHashes(_ service: MockAppAttestService) {
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

    static func client(
        service: MockAppAttestService,
        store: MemorySecureCredentialStore,
        session: URLSession
    ) -> AppAttestClient {
        AppAttestClient(
            baseURL: URL(string: "https://proxy.example/")!,
            session: session,
            appAttest: service,
            credentialStore: store,
            developmentToken: nil,
            now: { Date(timeIntervalSince1970: 1_800_000_000) }
        )
    }

    static func clients(
        service: MockAppAttestService,
        store: MemorySecureCredentialStore
    ) -> [AppAttestClient] {
        let session = TestURLProtocol.session()
        return [
            client(service: service, store: store, session: session),
            client(service: service, store: store, session: session)
        ]
    }

    static func credentialStore(
        token: String,
        expiresAt: String
    ) throws -> MemorySecureCredentialStore {
        let store = MemorySecureCredentialStore()
        let expiresAt = try XCTUnwrap(ISO8601DateFormatter().date(from: expiresAt))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(
            DeviceCredentialsProbe(
                keyID: "secure-enclave-key",
                token: token,
                tokenExpiresAt: expiresAt
            )
        )
        try store.set(data, for: AppAttestClient.credentialsAccount)
        return store
    }

    static func concurrentCatalogResponses(
        clients: [AppAttestClient],
        server: AppAttestServerHarness,
        signedRequestCount: Int
    ) async throws -> [HTTPURLResponse] {
        try await withThrowingTaskGroup(
            of: HTTPURLResponse.self,
            returning: [HTTPURLResponse].self
        ) { group in
            for index in 0..<4 {
                let client = clients[index % clients.count]
                let request = catalogRequest(index: index)
                group.addTask {
                    let (_, response) = try await client.data(for: request)
                    guard let response = response as? HTTPURLResponse else {
                        throw URLError(.badServerResponse)
                    }
                    return response
                }
            }

            try await releaseSignedResponses(server, count: signedRequestCount)
            var responses: [HTTPURLResponse] = []
            for try await response in group {
                responses.append(response)
            }
            return responses
        }
    }

    static func releaseSignedResponses(
        _ server: AppAttestServerHarness,
        count: Int
    ) async throws {
        do {
            for expectedCount in 1...count {
                try await server.waitUntilSignedRequestCount(expectedCount)
                let snapshot = await server.snapshot()
                guard snapshot.signedRequestsInFlight == 1,
                      snapshot.maximumSignedRequestsInFlight == 1 else {
                    throw AppAttestTestHarnessError.overlappingSignedRequests(
                        inFlight: snapshot.signedRequestsInFlight,
                        maximum: snapshot.maximumSignedRequestsInFlight
                    )
                }
                await server.releaseNextSignedResponse()
            }
        } catch {
            await server.releaseAllSignedResponses()
            throw error
        }
        await server.releaseAllSignedResponses()
    }

    static func catalogRequest(index: Int) -> URLRequest {
        URLRequest(url: URL(string: "https://proxy.example/v1/catalog/search?q=\(index)")!)
    }

    static func jsonResponse(
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

private enum AppAttestTestHarnessError: Error {
    case timedOut(waitingFor: String)
    case overlappingSignedRequests(inFlight: Int, maximum: Int)
}

actor AsyncTestGate {
    private var isOpen = false

    func wait() async throws {
        while !isOpen {
            try Task.checkCancellation()
            await Task.yield()
        }
    }

    func open() {
        isOpen = true
    }
}

actor AppAttestServerHarness {
    struct Snapshot: Sendable {
        let attestationChallenges: Int
        let tokenChallenges: Int
        let registrations: Int
        let tokenRefreshes: Int
        let catalogRequests: Int
        let signedRequestsInFlight: Int
        let maximumSignedRequestsInFlight: Int
        let allCatalogRequestsWereSigned: Bool
        let developmentTokens: [String]
    }

    private var holdsSignedResponses: Bool
    private var attestationChallenges = 0
    private var tokenChallenges = 0
    private var requestChallenges = 0
    private var registrations = 0
    private var tokenRefreshes = 0
    private var catalogRequests = 0
    private var signedRequestCount = 0
    private var signedRequestsInFlight = 0
    private var maximumSignedRequestsInFlight = 0
    private var allCatalogRequestsWereSigned = true
    private var developmentTokens: [String] = []
    private var signedResponseWaiters: [CheckedContinuation<Void, Never>] = []

    init(holdsSignedResponses: Bool = false) {
        self.holdsSignedResponses = holdsSignedResponses
    }

    func response(for request: URLRequest) async throws -> (HTTPURLResponse, Data) {
        let path = try XCTUnwrap(request.url?.path)
        if path == "/v1/app-attest/challenge" {
            return try challengeResponse(for: request)
        }
        if path == "/v1/app-attest/register" {
            registrations += 1
            return try jsonResponse(request, status: 201, body: [
                "token": "registered-token",
                "expiresAt": "2030-01-01T00:00:00Z"
            ])
        }
        if path == "/v1/app-attest/token" {
            tokenRefreshes += 1
            return try await delayedSignedResponse(request, status: 201, body: [
                "token": "refreshed-token",
                "expiresAt": "2030-01-01T00:00:00Z"
            ])
        }
        guard path.hasPrefix("/v1/catalog/") else {
            throw URLError(.unsupportedURL)
        }

        catalogRequests += 1
        if let developmentToken = request.value(forHTTPHeaderField: "X-OpenTV-Development-Token") {
            developmentTokens.append(developmentToken)
        } else {
            allCatalogRequestsWereSigned = allCatalogRequestsWereSigned
                && request.value(forHTTPHeaderField: "X-App-Attest-Key-ID") == "secure-enclave-key"
                && request.value(forHTTPHeaderField: "X-App-Attest-Challenge-ID") != nil
                && request.value(forHTTPHeaderField: "X-App-Attest-Assertion") != nil
        }
        return try await delayedSignedResponse(request, status: 200, body: ["results": []])
    }

    private func challengeResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let body = try XCTUnwrap(TestURLProtocol.bodyData(for: request))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
        let purpose = try XCTUnwrap(json["purpose"])
        let sequence: Int
        switch purpose {
        case "attestation":
            attestationChallenges += 1
            sequence = attestationChallenges
        case "token":
            tokenChallenges += 1
            sequence = tokenChallenges
        case "request":
            requestChallenges += 1
            sequence = requestChallenges
        default:
            throw URLError(.badServerResponse)
        }
        return try jsonResponse(request, status: 201, body: [
            "id": "\(purpose)-id-\(sequence)",
            "challenge": "\(purpose)-challenge-\(sequence)",
            "expiresAt": "2030-01-01T00:00:00Z"
        ])
    }

    func snapshot() -> Snapshot {
        Snapshot(
            attestationChallenges: attestationChallenges,
            tokenChallenges: tokenChallenges,
            registrations: registrations,
            tokenRefreshes: tokenRefreshes,
            catalogRequests: catalogRequests,
            signedRequestsInFlight: signedRequestsInFlight,
            maximumSignedRequestsInFlight: maximumSignedRequestsInFlight,
            allCatalogRequestsWereSigned: allCatalogRequestsWereSigned,
            developmentTokens: developmentTokens
        )
    }

    func waitUntilSignedRequestCount(_ expectedCount: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while signedRequestCount < expectedCount {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw AppAttestTestHarnessError.timedOut(
                    waitingFor: "signed request \(expectedCount)"
                )
            }
            await Task.yield()
        }
    }

    func releaseNextSignedResponse() {
        guard !signedResponseWaiters.isEmpty else { return }
        signedResponseWaiters.removeFirst().resume()
    }

    func releaseAllSignedResponses() {
        holdsSignedResponses = false
        let waiters = signedResponseWaiters
        signedResponseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func delayedSignedResponse(
        _ request: URLRequest,
        status: Int,
        body: [String: Any]
    ) async throws -> (HTTPURLResponse, Data) {
        if request.value(forHTTPHeaderField: "X-App-Attest-Assertion") != nil {
            signedRequestCount += 1
            signedRequestsInFlight += 1
            maximumSignedRequestsInFlight = max(
                maximumSignedRequestsInFlight,
                signedRequestsInFlight
            )
            defer { signedRequestsInFlight -= 1 }
            if holdsSignedResponses {
                await withCheckedContinuation { continuation in
                    signedResponseWaiters.append(continuation)
                }
            }
        }
        return try jsonResponse(request, status: status, body: body)
    }

    private func jsonResponse(
        _ request: URLRequest,
        status: Int,
        body: [String: Any]
    ) throws -> (HTTPURLResponse, Data) {
        (
            HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!,
            try JSONSerialization.data(withJSONObject: body)
        )
    }
}

final class MockAppAttestService: AppAttestServicing, @unchecked Sendable {
    let isSupported: Bool
    private let lock = NSLock()
    private let generateKeyGate: AsyncTestGate?
    private var recordedAttestationHashes: [Data] = []
    private var recordedAssertionHashes: [Data] = []
    private var recordedGenerateKeyCallCount = 0

    var attestationHashes: [Data] {
        lock.withLock { recordedAttestationHashes }
    }

    var assertionHashes: [Data] {
        lock.withLock { recordedAssertionHashes }
    }

    var generateKeyCallCount: Int {
        lock.withLock { recordedGenerateKeyCallCount }
    }

    init(
        isSupported: Bool,
        generateKeyGate: AsyncTestGate? = nil
    ) {
        self.isSupported = isSupported
        self.generateKeyGate = generateKeyGate
    }

    func generateKey() async throws -> String {
        lock.withLock { recordedGenerateKeyCallCount += 1 }
        if let generateKeyGate {
            try await generateKeyGate.wait()
        }
        return "secure-enclave-key"
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        lock.withLock { recordedAttestationHashes.append(clientDataHash) }
        return Data("attestation-object".utf8)
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        lock.withLock { recordedAssertionHashes.append(clientDataHash) }
        return Data("assertion-object".utf8)
    }

    func waitUntilGenerateKeyCallCount(_ expectedCount: Int) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(5))
        while generateKeyCallCount < expectedCount {
            try Task.checkCancellation()
            guard clock.now < deadline else {
                throw AppAttestTestHarnessError.timedOut(
                    waitingFor: "generateKey call \(expectedCount)"
                )
            }
            await Task.yield()
        }
    }
}
