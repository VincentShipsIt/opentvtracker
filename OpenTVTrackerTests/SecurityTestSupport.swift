import Foundation
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
