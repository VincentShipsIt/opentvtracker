import CryptoKit
import Foundation
import Security

protocol SecureCredentialStoring: Sendable {
    func data(for account: String) throws -> Data?
    func set(_ data: Data, for account: String) throws
    func remove(account: String) throws
}

struct KeychainCredentialStore: SecureCredentialStoring {
    private let service: String

    init(service: String = "dev.shipshit.opentvtracker.credentials") {
        self.service = service
    }

    func data(for account: String) throws -> Data? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw SecureCredentialError.keychain(status)
        }
        return data
    }

    func set(_ data: Data, for account: String) throws {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecureCredentialError.keychain(status) }
    }

    func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw SecureCredentialError.keychain(status)
        }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false
        ]
    }
}

enum SecureCredentialError: Error {
    case keychain(OSStatus)
}

struct OpenRouterAuthorizationRequest: Sendable {
    let authorizationURL: URL
    let callbackHost: String
    let callbackPath: String
    fileprivate let verifier: String
}

enum OpenRouterPKCE {
    static func generateVerifier(randomBytes: () throws -> Data = secureRandomBytes) throws -> String {
        try randomBytes().base64URLEncodedString()
    }

    static func challenge(for verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncodedString()
    }

    static func secureRandomBytes() throws -> Data {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw OpenRouterOAuthError.randomnessUnavailable
        }
        return Data(bytes)
    }
}

actor OpenRouterOAuthClient {
    static let apiKeyAccount = "openrouter.user-api-key"

    private let callbackURL: URL
    private let credentials: any SecureCredentialStoring
    private let session: URLSession

    init(
        callbackURL: URL,
        credentials: any SecureCredentialStoring = KeychainCredentialStore(),
        session: URLSession = .shared
    ) {
        self.callbackURL = callbackURL
        self.credentials = credentials
        self.session = session
    }

    func authorizationRequest() throws -> OpenRouterAuthorizationRequest {
        guard callbackURL.scheme == "https",
              let callbackHost = callbackURL.host,
              callbackURL.query == nil,
              callbackURL.fragment == nil else {
            throw OpenRouterOAuthError.invalidConfiguration
        }
        let verifier = try OpenRouterPKCE.generateVerifier()
        guard var components = URLComponents(string: "https://openrouter.ai/auth") else {
            throw OpenRouterOAuthError.invalidConfiguration
        }
        components.queryItems = [
            URLQueryItem(name: "callback_url", value: callbackURL.absoluteString),
            URLQueryItem(name: "code_challenge", value: OpenRouterPKCE.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256")
        ]
        guard let authorizationURL = components.url else { throw OpenRouterOAuthError.invalidConfiguration }
        return OpenRouterAuthorizationRequest(
            authorizationURL: authorizationURL,
            callbackHost: callbackHost,
            callbackPath: callbackURL.path,
            verifier: verifier
        )
    }

    func complete(_ callback: URL, authorization: OpenRouterAuthorizationRequest) async throws {
        guard callback.scheme == "https",
              callback.host == authorization.callbackHost,
              callback.path == authorization.callbackPath,
              let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value,
              !code.isEmpty else {
            throw OpenRouterOAuthError.invalidCallback
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/auth/keys")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(OpenRouterCodeExchange(
            code: code,
            codeVerifier: authorization.verifier,
            codeChallengeMethod: "S256"
        ))
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
            throw OpenRouterOAuthError.exchangeFailed
        }
        let key = try JSONDecoder().decode(OpenRouterCodeExchangeResponse.self, from: data).key
        guard key.hasPrefix("sk-or-") else { throw OpenRouterOAuthError.exchangeFailed }
        try credentials.set(Data(key.utf8), for: Self.apiKeyAccount)
    }

    func isAuthorized() -> Bool {
        (try? apiKey()) != nil
    }

    func disconnect() throws {
        try credentials.remove(account: Self.apiKeyAccount)
    }

    func apiKey() throws -> String? {
        guard let data = try credentials.data(for: Self.apiKeyAccount),
              let key = String(data: data, encoding: .utf8),
              key.hasPrefix("sk-or-") else { return nil }
        return key
    }
}

private struct OpenRouterCodeExchange: Encodable {
    let code: String
    let codeVerifier: String
    let codeChallengeMethod: String

    enum CodingKeys: String, CodingKey {
        case code
        case codeVerifier = "code_verifier"
        case codeChallengeMethod = "code_challenge_method"
    }
}

private struct OpenRouterCodeExchangeResponse: Decodable {
    let key: String
}

enum OpenRouterOAuthError: LocalizedError {
    case invalidConfiguration
    case invalidCallback
    case exchangeFailed
    case randomnessUnavailable

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration: "OpenRouter OAuth is not configured for this build."
        case .invalidCallback: "OpenRouter returned an invalid authorization callback."
        case .exchangeFailed: "OpenRouter authorization could not be completed."
        case .randomnessUnavailable: "A secure authorization code could not be created."
        }
    }
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
