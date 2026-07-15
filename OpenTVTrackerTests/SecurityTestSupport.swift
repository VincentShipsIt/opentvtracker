import Foundation
@testable import OpenTVTracker

final class TestURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
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

    override func stopLoading() {}

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        return URLSession(configuration: configuration)
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
