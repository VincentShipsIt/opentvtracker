import CryptoKit
import XCTest
@testable import OpenTVTracker

final class OpenRouterOAuthTests: XCTestCase {
    override func tearDown() {
        TestURLProtocol.handler = nil
        super.tearDown()
    }

    func testPKCEUsesS256AndURLSafeEncoding() throws {
        let verifier = try OpenRouterPKCE.generateVerifier {
            Data((0..<32).map(UInt8.init))
        }

        XCTAssertFalse(verifier.contains("="))
        XCTAssertFalse(verifier.contains("+"))
        XCTAssertFalse(verifier.contains("/"))
        XCTAssertEqual(OpenRouterPKCE.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"),
                       "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testOAuthExchangesCodeAndWritesOnlyTheUserKeyToCredentialBoundary() async throws {
        let store = MemorySecureCredentialStore()
        let session = TestURLProtocol.session()
        TestURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://openrouter.ai/api/v1/auth/keys")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try XCTUnwrap(request.httpBody)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: String])
            XCTAssertEqual(json["code"], "authorization-code")
            XCTAssertEqual(json["code_challenge_method"], "S256")
            XCTAssertNotNil(json["code_verifier"])
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(#"{"key":"sk-or-v1-user-controlled"}"#.utf8)
            )
        }
        let client = OpenRouterOAuthClient(
            callbackURL: URL(string: "https://shipshit.dev/opentv/openrouter/callback")!,
            credentials: store,
            session: session
        )
        let authorization = try await client.authorizationRequest()
        let callback = URL(string: "https://shipshit.dev/opentv/openrouter/callback?code=authorization-code")!

        try await client.complete(callback, authorization: authorization)

        let isAuthorized = await client.isAuthorized()
        XCTAssertTrue(isAuthorized)
        XCTAssertEqual(store.writtenAccounts, [OpenRouterOAuthClient.apiKeyAccount])
        XCTAssertEqual(try await client.apiKey(), "sk-or-v1-user-controlled")
    }

    func testOAuthRejectsCallbackFromAnotherHostBeforeExchange() async throws {
        let client = OpenRouterOAuthClient(
            callbackURL: URL(string: "https://shipshit.dev/opentv/openrouter/callback")!,
            credentials: MemorySecureCredentialStore(),
            session: TestURLProtocol.session()
        )
        let authorization = try await client.authorizationRequest()

        await XCTAssertThrowsErrorAsync {
            try await client.complete(
                URL(string: "https://attacker.example/opentv/openrouter/callback?code=stolen")!,
                authorization: authorization
            )
        }
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
