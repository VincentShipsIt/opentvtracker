import CryptoKit
import Foundation
import XCTest
@testable import OpenTVTracker

final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?
    nonisolated(unsafe) static var asyncHandler: (@Sendable (URLRequest) async throws -> (HTTPURLResponse, Data))?

    private var loadingTask: Task<Void, Never>?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        if let asyncHandler = Self.asyncHandler {
            let owner = UncheckedWeakReference(self)
            let request = request
            loadingTask = Task { [owner, request] in
                guard let owner = owner.value else { return }
                do {
                    let (response, data) = try await asyncHandler(request)
                    guard !Task.isCancelled else { return }
                    owner.client?.urlProtocol(owner, didReceive: response, cacheStoragePolicy: .notAllowed)
                    owner.client?.urlProtocol(owner, didLoad: data)
                    owner.client?.urlProtocolDidFinishLoading(owner)
                } catch {
                    guard !Task.isCancelled else { return }
                    owner.client?.urlProtocol(owner, didFailWithError: error)
                }
            }
            return
        }
        do {
            guard let handler = Self.handler else { throw URLError(.unsupportedURL) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    static func bodyData(for request: URLRequest) throws -> Data? {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return nil }

        stream.open()
        defer { stream.close() }

        var body = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 { break }
            body.append(contentsOf: buffer.prefix(count))
        }
        return body
    }
}

private final class UncheckedWeakReference<Value: AnyObject>: @unchecked Sendable {
    weak var value: Value?

    init(_ value: Value) {
        self.value = value
    }
}

final class MemorySecureCredentialStore: SecureCredentialStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var values: [String: Data] = [:]
    private(set) var writtenAccounts: [String] = []

    func data(for account: String) throws -> Data? {
        lock.withLock { values[account] }
    }

    func set(_ data: Data, for account: String) throws {
        lock.withLock {
            values[account] = data
            writtenAccounts.append(account)
        }
    }

    func remove(account: String) throws {
        _ = lock.withLock { values.removeValue(forKey: account) }
    }
}

extension AppAttestClientTests {
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

    func testConcurrentValidCredentialsSerializeFourCatalogRequestsAcrossClients() async throws {
        let service = MockAppAttestService(isSupported: true)
        let store = try Self.credentialStore(token: "valid-token", expiresAt: "2030-01-01T00:00:00Z")
        let server = AppAttestServerHarness(holdsSignedResponses: true)
        TestURLProtocol.asyncHandler = { request in
            try await server.response(for: request)
        }
        let clients = Self.clients(service: service, store: store)

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
        let clients = Self.clients(service: service, store: store)

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
        let clients = Self.clients(service: service, store: store)

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
        let clients = Self.clients(service: service, store: store)
        let firstClient = clients[0]
        let firstRequest = Self.catalogRequest(index: 0)
        let first = Task {
            try await firstClient.data(for: firstRequest)
        }
        try await service.waitUntilGenerateKeyCallCount(1)
        let survivingClient = clients[1]
        let survivingRequest = Self.catalogRequest(index: 1)
        let survivor = Task {
            try await survivingClient.data(for: survivingRequest)
        }

        first.cancel()
        await registrationGate.open()
        try await Self.releaseSignedResponses(server, count: 2)

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
        let store = try Self.credentialStore(
            token: "stale-token",
            expiresAt: "2030-03-17T17:46:40Z"
        )

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

        let client = Self.client(service: service, store: store, session: TestURLProtocol.session())

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
}

struct DeviceCredentialsProbe: Encodable {
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
