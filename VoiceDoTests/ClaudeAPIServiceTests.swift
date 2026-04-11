@testable import VoiceDo
import VoiceDoShared
import XCTest

/// Tests for `ClaudeAPIService` using a mock `URLSession`.
/// These tests never make real network calls.
final class ClaudeAPIServiceTests: XCTestCase {

    // MARK: - Helpers

    private func makeService(
        responseData: Data,
        statusCode: Int = 200
    ) -> ClaudeAPIService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        MockURLProtocol.responseData = responseData
        MockURLProtocol.statusCode = statusCode
        let session = URLSession(configuration: config)
        return ClaudeAPIService(session: session)
    }

    private func validClaudeJSON(
        intent: String = "todo",
        title: String = "Test title",
        confidence: Double = 0.9
    ) -> Data {
        // Build the inner intent JSON as a dictionary to avoid overly long lines
        let innerFields: [String: Any] = [
            "intent": intent, "title": title,
            "notes": NSNull(), "due_date": NSNull(), "task_type": NSNull(),
            "platform_hint": NSNull(), "recipient_hint": NSNull(),
            "message_subject": NSNull(), "message_body": NSNull(),
            "confidence": confidence
        ]
        guard let innerData = try? JSONSerialization.data(withJSONObject: innerFields),
              let innerString = String(data: innerData, encoding: .utf8) else { return Data() }
        let outer: [String: Any] = ["content": [["type": "text", "text": innerString]]]
        return (try? JSONSerialization.data(withJSONObject: outer)) ?? Data()
    }

    // MARK: - Tests

    func testMissingAPIKeyThrows() async throws {
        try? APIKeyManager.delete()
        let service = ClaudeAPIService()
        do {
            _ = try await service.refineIntent(
                transcript: "Buy milk",
                offlineTitle: "Buy milk",
                offlineIntent: "todo"
            )
            XCTFail("Expected ClaudeAPIError.missingAPIKey")
        } catch ClaudeAPIError.missingAPIKey {
            // expected
        }
    }

    func testSuccessfulResponseDecodes() async throws {
        try APIKeyManager.save("sk-ant-fake-key-for-tests")
        defer { try? APIKeyManager.delete() }

        let service = makeService(responseData: validClaudeJSON(intent: "todo", title: "Buy milk", confidence: 0.95))
        let result = try await service.refineIntent(
            transcript: "Buy milk",
            offlineTitle: "Buy milk",
            offlineIntent: "todo"
        )

        XCTAssertEqual(result.intent, "todo")
        XCTAssertEqual(result.title, "Buy milk")
        XCTAssertEqual(result.confidence, 0.95, accuracy: 0.01)
    }

    func testHTTP401ThrowsHTTPError() async throws {
        try APIKeyManager.save("sk-ant-bad-key")
        defer { try? APIKeyManager.delete() }

        let errorData = Data(#"{"error": {"type": "authentication_error"}}"#.utf8)
        let service = makeService(responseData: errorData, statusCode: 401)

        do {
            _ = try await service.refineIntent(
                transcript: "Any text",
                offlineTitle: "Any text",
                offlineIntent: "todo"
            )
            XCTFail("Expected ClaudeAPIError.httpError")
        } catch ClaudeAPIError.httpError(let code, _) {
            XCTAssertEqual(code, 401)
        }
    }

    func testMalformedJSONThrowsDecodingError() async throws {
        try APIKeyManager.save("sk-ant-fake-key-for-tests")
        defer { try? APIKeyManager.delete() }

        let badData = Data(#"{"content": [{"type": "text", "text": "not valid json at all"}]}"#.utf8)
        let service = makeService(responseData: badData)

        do {
            _ = try await service.refineIntent(
                transcript: "Any text",
                offlineTitle: "Any",
                offlineIntent: "todo"
            )
            XCTFail("Expected ClaudeAPIError.decodingError")
        } catch ClaudeAPIError.decodingError {
            // expected
        }
    }

    /// Timeout test: a stalled URLProtocol means the TaskGroup timeout fires first
    /// and `ClaudeAPIError.timeout` is thrown.
    func testTimeoutThrowsTimeoutError() async throws {
        try APIKeyManager.save("sk-ant-fake-key-for-tests")
        defer { try? APIKeyManager.delete() }

        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StalledURLProtocol.self]
        let session = URLSession(configuration: config)
        let service = ClaudeAPIService(session: session, timeoutOverride: 0.1)

        do {
            _ = try await service.refineIntent(
                transcript: "Any text",
                offlineTitle: "Any",
                offlineIntent: "todo"
            )
            XCTFail("Expected ClaudeAPIError.timeout")
        } catch ClaudeAPIError.timeout {
            // expected
        }
    }

    /// Verifies IntentParserService falls back to offline result when Claude times out.
    func testIntentParserFallsBackOnClaudeTimeout() async throws {
        try APIKeyManager.save("sk-ant-fake-key-for-tests")
        defer { try? APIKeyManager.delete() }

        // Use a low-confidence transcript so Claude would normally be called,
        // but feed a stalled session so the timeout fires.
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StalledURLProtocol.self]
        let session = URLSession(configuration: config)

        let offlineParser = OfflineIntentParser()
        let offlineResult = offlineParser.parse(transcript: "Something")

        let claudeService = ClaudeAPIService(session: session, timeoutOverride: 0.1)
        let parserService = IntentParserService(claudeService: claudeService)

        // Should not throw — Claude failure must be swallowed
        let result = try await parserService.parse(transcript: "Something")

        // Falls back to offline result
        XCTAssertEqual(result.type, offlineResult.type)
        XCTAssertFalse(result.title.isEmpty)
    }
}

// MARK: - StalledURLProtocol

/// A URLProtocol that never responds — used to trigger timeout paths.
final class StalledURLProtocol: URLProtocol {
    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        // Intentionally do nothing — stall forever so the task group timeout fires
    }
    override func stopLoading() {}
}

// MARK: - MockURLProtocol

final class MockURLProtocol: URLProtocol {
    static var responseData: Data = Data()
    static var statusCode: Int = 200

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(
                  url: url,
                  statusCode: Self.statusCode,
                  httpVersion: nil,
                  headerFields: ["Content-Type": "application/json"]
              ) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
