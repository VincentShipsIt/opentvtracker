import CryptoKit
import XCTest
@testable import OpenTVTracker

final class AppAttestClientTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        TestURLProtocol.asyncHandler = nil
        super.tearDown()
    }

    func testRegistersThenSignsExactCatalogRequestAndPersistsCredentials() async throws {
        let service = MockAppAttestService(isSupported: true)
        let store = MemorySecureCredentialStore()
        TestURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            if path == "/v1/app-attest/challenge" {
                let body = try XCTUnwrap(TestURLProtocol.bodyData(for: request))
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

    func testConcurrentValidCredentialsSerializeFourCatalogRequestsAcrossClients() async throws {
        let service = MockAppAttestService(isSupported: true)
        let store = try Self.credentialStore(token: "valid-token", expiresAt: "2030-01-01T00:00:00Z")
        let server = AppAttestServerHarness(holdsSignedResponses: true)
        TestURLProtocol.asyncHandler = { request in
            try await server.response(for: request)
        }
        let session = TestURLProtocol.session()
        let clients = [
            Self.client(service: service, store: store, session: session),
            Self.client(service: service, store: store, session: session)
        ]

        let responses = try await Self.concurrentCatalogResponses(
            clients: clients,
            server: server,
            signedRequestCount: 4
        )
        let snapshot = await server.snapshot()

        XCTAssertEqual(responses.map(\.statusCode), [200, 200, 200, 200])
        XCTAssertEqual(snapshot.catalogRequests, 4)
        XCTAssertEqual(snapshot.maximumSignedRequestsInFlight, 1)
        XCTAssertTrue(snapshot.allCatalogRequestsWereSigned)
        XCTAssertEqual(snapshot.registrations, 0)
        XCTAssertEqual(snapshot.tokenRefreshes, 0)
        XCTAssertEqual(service.generateKeyCallCount, 0)
    }

    func testConcurrentFirstUseSharesOneRegistration() async throws {
        let service = MockAppAttestService(isSupported: true)
        let store = MemorySecureCredentialStore()
        let server = AppAttestServerHarness(holdsSignedResponses: true)
        TestURLProtocol.asyncHandler = { request in
            try await server.response(for: request)
        }
        let session = TestURLProtocol.session()
        let clients = [
            Self.client(service: service, store: store, session: session),
            Self.client(service: service, store: store, session: session)
        ]

        let responses = try await Self.concurrentCatalogResponses(
            clients: clients,
            server: server,
            signedRequestCount: 4
        )
        let snapshot = await server.snapshot()

        XCTAssertEqual(responses.map(\.statusCode), [200, 200, 200, 200])
        XCTAssertEqual(service.generateKeyCallCount, 1)
        XCTAssertEqual(service.attestationHashes.count, 1)
        XCTAssertEqual(snapshot.attestationChallenges, 1)
        XCTAssertEqual(snapshot.registrations, 1)
        XCTAssertEqual(snapshot.catalogRequests, 4)
        XCTAssertEqual(snapshot.maximumSignedRequestsInFlight, 1)
        XCTAssertTrue(snapshot.allCatalogRequestsWereSigned)
    }

    func testConcurrentExpiredCredentialsShareOneRefresh() async throws {
        let service = MockAppAttestService(isSupported: true)
        let store = try Self.credentialStore(token: "expired-token", expiresAt: "2020-01-01T00:00:00Z")
        let server = AppAttestServerHarness(holdsSignedResponses: true)
        TestURLProtocol.asyncHandler = { request in
            try await server.response(for: request)
        }
        let session = TestURLProtocol.session()
        let clients = [
            Self.client(service: service, store: store, session: session),
            Self.client(service: service, store: store, session: session)
        ]

        let responses = try await Self.concurrentCatalogResponses(
            clients: clients,
            server: server,
            signedRequestCount: 5
        )
        let snapshot = await server.snapshot()

        XCTAssertEqual(responses.map(\.statusCode), [200, 200, 200, 200])
        XCTAssertEqual(snapshot.tokenChallenges, 1)
        XCTAssertEqual(snapshot.tokenRefreshes, 1)
        XCTAssertEqual(snapshot.catalogRequests, 4)
        XCTAssertEqual(snapshot.maximumSignedRequestsInFlight, 1)
        XCTAssertTrue(snapshot.allCatalogRequestsWereSigned)
        XCTAssertEqual(service.generateKeyCallCount, 0)
    }

    func testCancellingFirstUseWaiterDoesNotCancelSharedWorkOrDeadlockQueue() async throws {
        let registrationGate = AsyncTestGate()
        let service = MockAppAttestService(
            isSupported: true,
            generateKeyGate: registrationGate
        )
        let store = MemorySecureCredentialStore()
        let server = AppAttestServerHarness(holdsSignedResponses: true)
        TestURLProtocol.asyncHandler = { request in
            try await server.response(for: request)
        }
        let session = TestURLProtocol.session()
        let clients = [
            Self.client(service: service, store: store, session: session),
            Self.client(service: service, store: store, session: session)
        ]
        let firstClient = clients[0]
        let firstRequest = Self.catalogRequest(index: 0)
        let first = Task {
            try await firstClient.data(for: firstRequest)
        }
        await service.waitUntilGenerateKeyCallCount(1)
        let survivingClient = clients[1]
        let survivingRequest = Self.catalogRequest(index: 1)
        let survivor = Task {
            try await survivingClient.data(for: survivingRequest)
        }

        first.cancel()
        await registrationGate.open()
        await Self.releaseSignedResponses(server, count: 2)

        do {
            _ = try await first.value
            XCTFail("Expected the cancelled waiter to observe cancellation")
        } catch is CancellationError {
            // The queue-owned credential work continues for the surviving waiter.
        }
        let (_, survivorResponse) = try await survivor.value
        let snapshot = await server.snapshot()

        XCTAssertEqual((survivorResponse as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(service.generateKeyCallCount, 1)
        XCTAssertEqual(snapshot.registrations, 1)
        XCTAssertEqual(snapshot.catalogRequests, 2)
        XCTAssertEqual(snapshot.maximumSignedRequestsInFlight, 1)
    }

    func testDevelopmentBypassRemainsDirect() async throws {
        let service = MockAppAttestService(isSupported: false)
        let store = MemorySecureCredentialStore()
        let server = AppAttestServerHarness()
        TestURLProtocol.asyncHandler = { request in
            try await server.response(for: request)
        }
        let client = AppAttestClient(
            baseURL: URL(string: "https://proxy.example/")!,
            session: TestURLProtocol.session(),
            appAttest: service,
            credentialStore: store,
            developmentToken: "development-token"
        )

        let (_, response) = try await client.data(for: Self.catalogRequest(index: 0))
        let snapshot = await server.snapshot()

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(snapshot.developmentTokens, ["development-token"])
        XCTAssertEqual(snapshot.maximumSignedRequestsInFlight, 0)
        XCTAssertEqual(service.generateKeyCallCount, 0)
        XCTAssertTrue(store.writtenAccounts.isEmpty)
    }

    func testExpiredTokenRetriesTheSameCatalogRequestOnce() async throws {
        let service = MockAppAttestService(isSupported: true)
        let store = MemorySecureCredentialStore()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let stale = try encoder.encode(
            DeviceCredentialsProbe(keyID: "secure-enclave-key", token: "stale-token", tokenExpiresAt: Date(timeIntervalSince1970: 1_900_000_000))
        )
        try store.set(stale, for: AppAttestClient.credentialsAccount)

        let catalogAttempts = RequestCounter()
        TestURLProtocol.handler = { request in
            let path = try XCTUnwrap(request.url?.path)
            if path == "/v1/app-attest/challenge" {
                let body = try XCTUnwrap(TestURLProtocol.bodyData(for: request))
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
                let purpose = try XCTUnwrap(json["purpose"])
                if purpose == "token" {
                    return try Self.jsonResponse(request, status: 201, body: [
                        "id": "token-id",
                        "challenge": "token-challenge",
                        "expiresAt": "2030-01-01T00:00:00Z"
                    ])
                }
                return try Self.jsonResponse(request, status: 201, body: [
                    "id": "request-id",
                    "challenge": "request-challenge",
                    "expiresAt": "2030-01-01T00:00:00Z"
                ])
            }
            if path == "/v1/app-attest/token" {
                return try Self.jsonResponse(request, status: 201, body: [
                    "token": "fresh-token",
                    "expiresAt": "2030-01-01T00:00:00Z"
                ])
            }
            XCTAssertEqual(path, "/v1/catalog/search")
            let attempt = catalogAttempts.increment()
            if attempt == 1 {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "AppAttest stale-token")
                return try Self.jsonResponse(request, status: 401, body: ["error": "expired"])
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "AppAttest fresh-token")
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

        let (_, response) = try await client.data(
            for: URLRequest(url: URL(string: "https://proxy.example/v1/catalog/search")!)
        )

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(catalogAttempts.value, 2)
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

    private static func client(
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

    private static func credentialStore(
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

    private static func concurrentCatalogResponses(
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

            await releaseSignedResponses(server, count: signedRequestCount)
            var responses: [HTTPURLResponse] = []
            for try await response in group {
                responses.append(response)
            }
            return responses
        }
    }

    private static func releaseSignedResponses(
        _ server: AppAttestServerHarness,
        count: Int
    ) async {
        for expectedCount in 1...count {
            await server.waitUntilSignedRequestCount(expectedCount)
            let snapshot = await server.snapshot()
            XCTAssertEqual(snapshot.signedRequestsInFlight, 1)
            XCTAssertEqual(snapshot.maximumSignedRequestsInFlight, 1)
            guard snapshot.signedRequestsInFlight == 1,
                  snapshot.maximumSignedRequestsInFlight == 1 else {
                await server.releaseAllSignedResponses()
                return
            }
            await server.releaseNextSignedResponse()
        }
    }

    private static func catalogRequest(index: Int) -> URLRequest {
        URLRequest(url: URL(string: "https://proxy.example/v1/catalog/search?q=\(index)")!)
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

private struct DeviceCredentialsProbe: Encodable {
    let keyID: String
    let token: String
    let tokenExpiresAt: Date
}

private final class RequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var value = 0

    func increment() -> Int {
        lock.withLock {
            value += 1
            return value
        }
    }
}

private actor AsyncTestGate {
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

private actor AppAttestServerHarness {
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

    func waitUntilSignedRequestCount(_ expectedCount: Int) async {
        while signedRequestCount < expectedCount {
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

private final class MockAppAttestService: AppAttestServicing, @unchecked Sendable {
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

    func waitUntilGenerateKeyCallCount(_ expectedCount: Int) async {
        while generateKeyCallCount < expectedCount {
            await Task.yield()
        }
    }
}
