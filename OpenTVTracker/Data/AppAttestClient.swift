import CryptoKit
import DeviceCheck
import Foundation

protocol AppAttestServicing: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data
}

struct SystemAppAttestService: AppAttestServicing, @unchecked Sendable {
    private let service = DCAppAttestService.shared

    var isSupported: Bool { service.isSupported }

    func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            service.generateKey { keyID, error in
                if let keyID {
                    continuation.resume(returning: keyID)
                } else {
                    continuation.resume(throwing: error ?? AppAttestClientError.registrationFailed)
                }
            }
        }
    }

    func attestKey(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            service.attestKey(keyID, clientDataHash: clientDataHash) { attestation, error in
                if let attestation {
                    continuation.resume(returning: attestation)
                } else {
                    continuation.resume(throwing: error ?? AppAttestClientError.registrationFailed)
                }
            }
        }
    }

    func generateAssertion(_ keyID: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            service.generateAssertion(keyID, clientDataHash: clientDataHash) { assertion, error in
                if let assertion {
                    continuation.resume(returning: assertion)
                } else {
                    continuation.resume(throwing: error ?? AppAttestClientError.assertionFailed)
                }
            }
        }
    }
}

actor AppAttestClient {
    static let credentialsAccount = "app-attest.device-credentials"

    private let baseURL: URL
    private let session: URLSession
    private let appAttest: any AppAttestServicing
    private let credentialStore: any SecureCredentialStoring
    private let developmentToken: String?
    private let now: @Sendable () -> Date

    init(
        baseURL: URL,
        session: URLSession = .shared,
        appAttest: any AppAttestServicing = SystemAppAttestService(),
        credentialStore: any SecureCredentialStoring = KeychainCredentialStore(),
        developmentToken: String? = AppServiceConfiguration.appAttestDevelopmentToken,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.baseURL = baseURL
        self.session = session
        self.appAttest = appAttest
        self.credentialStore = credentialStore
        self.developmentToken = developmentToken
        self.now = now
    }

    func data(for unsignedRequest: URLRequest) async throws -> (Data, URLResponse) {
        if let developmentToken {
            var request = unsignedRequest
            request.setValue(developmentToken, forHTTPHeaderField: "X-OpenTV-Development-Token")
            return try await session.data(for: request)
        }
        guard appAttest.isSupported else { throw AppAttestClientError.unsupportedDevice }
        var credentials = try await validCredentials()
        let challenge = try await requestChallenge(
            purpose: .request,
            keyID: credentials.keyID,
            token: credentials.token
        )
        var request = unsignedRequest
        let assertion = try await assertion(
            for: request,
            challenge: challenge.challenge,
            keyID: credentials.keyID
        )
        request.setValue("AppAttest \(credentials.token)", forHTTPHeaderField: "Authorization")
        request.setValue(credentials.keyID, forHTTPHeaderField: "X-App-Attest-Key-ID")
        request.setValue(challenge.id, forHTTPHeaderField: "X-App-Attest-Challenge-ID")
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Attest-Assertion")
        let result = try await session.data(for: request)
        if let response = result.1 as? HTTPURLResponse, response.statusCode == 401 {
            credentials.tokenExpiresAt = .distantPast
            try save(credentials)
        }
        return result
    }

    private func validCredentials() async throws -> DeviceCredentials {
        if var credentials = try loadCredentials() {
            if credentials.tokenExpiresAt > now().addingTimeInterval(30) { return credentials }
            credentials = try await refreshToken(for: credentials)
            try save(credentials)
            return credentials
        }
        let credentials = try await registerDevice()
        try save(credentials)
        return credentials
    }

    private func registerDevice() async throws -> DeviceCredentials {
        let challenge = try await requestChallenge(purpose: .attestation, keyID: nil, token: nil)
        let keyID = try await appAttest.generateKey()
        do {
            let clientDataHash = Data(SHA256.hash(data: Data(challenge.challenge.utf8)))
            let attestation = try await appAttest.attestKey(keyID, clientDataHash: clientDataHash)
            let body = RegistrationRequest(
                challengeID: challenge.id,
                keyID: keyID,
                attestation: attestation.base64EncodedString()
            )
            let token: DeviceToken = try await post("v1/app-attest/register", body: body)
            return DeviceCredentials(keyID: keyID, token: token.token, tokenExpiresAt: token.expiresAt)
        } catch {
            try? credentialStore.remove(account: Self.credentialsAccount)
            throw error
        }
    }

    private func refreshToken(for credentials: DeviceCredentials) async throws -> DeviceCredentials {
        let challenge = try await requestChallenge(purpose: .token, keyID: credentials.keyID, token: nil)
        let body = EmptyRequest()
        let bodyData = try JSONEncoder().encode(body)
        var request = URLRequest(url: baseURL.appending(path: "v1/app-attest/token"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        let assertion = try await assertion(
            for: request,
            challenge: challenge.challenge,
            keyID: credentials.keyID
        )
        request.setValue(credentials.keyID, forHTTPHeaderField: "X-App-Attest-Key-ID")
        request.setValue(challenge.id, forHTTPHeaderField: "X-App-Attest-Challenge-ID")
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Attest-Assertion")
        let token: DeviceToken = try await send(request)
        return DeviceCredentials(keyID: credentials.keyID, token: token.token, tokenExpiresAt: token.expiresAt)
    }

    private func requestChallenge(
        purpose: ChallengePurpose,
        keyID: String?,
        token: String?
    ) async throws -> AppAttestChallenge {
        var request = URLRequest(url: baseURL.appending(path: "v1/app-attest/challenge"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { request.setValue("AppAttest \(token)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONEncoder().encode(ChallengeRequest(purpose: purpose, keyID: keyID))
        return try await send(request)
    }

    private func assertion(for request: URLRequest, challenge: String, keyID: String) async throws -> Data {
        let payload = try canonicalPayload(for: request, challenge: challenge)
        let clientDataHash = Data(SHA256.hash(data: Data(payload.utf8)))
        return try await appAttest.generateAssertion(keyID, clientDataHash: clientDataHash)
    }

    private func canonicalPayload(for request: URLRequest, challenge: String) throws -> String {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw AppAttestClientError.invalidRequest
        }
        let target = components.percentEncodedPath
            + (components.percentEncodedQuery.map { "?\($0)" } ?? "")
        let bodyHash = Data(SHA256.hash(data: request.httpBody ?? Data())).base64URLEncodedString()
        return [
            "opentv-app-attest-v1",
            challenge,
            request.httpMethod?.uppercased() ?? "GET",
            target,
            bodyHash
        ].joined(separator: "\n")
    }

    private func post<Body: Encodable, Response: Decodable>(_ path: String, body: Body) async throws -> Response {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request)
    }

    private func send<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw AppAttestClientError.serverRejected
        }
        return try JSONDecoder.openTV.decode(Response.self, from: data)
    }

    private func loadCredentials() throws -> DeviceCredentials? {
        guard let data = try credentialStore.data(for: Self.credentialsAccount) else { return nil }
        return try JSONDecoder.openTV.decode(DeviceCredentials.self, from: data)
    }

    private func save(_ credentials: DeviceCredentials) throws {
        try credentialStore.set(try JSONEncoder.openTV.encode(credentials), for: Self.credentialsAccount)
    }
}

private enum ChallengePurpose: String, Encodable {
    case attestation
    case token
    case request
}

private struct ChallengeRequest: Encodable {
    let purpose: ChallengePurpose
    let keyID: String?
}

private struct RegistrationRequest: Encodable {
    let challengeID: String
    let keyID: String
    let attestation: String
}

private struct EmptyRequest: Encodable {}

private struct AppAttestChallenge: Decodable {
    let id: String
    let challenge: String
    let expiresAt: Date
}

private struct DeviceToken: Decodable {
    let token: String
    let expiresAt: Date
}

private struct DeviceCredentials: Codable {
    let keyID: String
    var token: String
    var tokenExpiresAt: Date
}

enum AppAttestClientError: LocalizedError {
    case unsupportedDevice
    case registrationFailed
    case assertionFailed
    case invalidRequest
    case serverRejected

    var errorDescription: String? {
        switch self {
        case .unsupportedDevice:
            "This device cannot use the official catalog service. OpenTV will use its public catalog fallback."
        case .registrationFailed, .assertionFailed, .serverRejected:
            "The official catalog could not verify this app installation. OpenTV will use its public catalog fallback."
        case .invalidRequest:
            "OpenTV could not secure this catalog request."
        }
    }
}

private extension JSONEncoder {
    static var openTV: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
