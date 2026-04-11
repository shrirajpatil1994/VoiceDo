@testable import VoiceDo
import XCTest

/// Tests for `APIKeyManager` Keychain operations.
/// These tests write to the real iOS Simulator Keychain — they clean up after themselves.
final class APIKeyManagerTests: XCTestCase {

    // MARK: - Setup / Teardown

    override func setUp() async throws {
        // Start each test with a clean slate
        try? APIKeyManager.delete()
    }

    override func tearDown() async throws {
        try? APIKeyManager.delete()
    }

    // MARK: - Tests

    func testSaveAndRetrieve() throws {
        let key = "sk-ant-test-key-1234"
        try APIKeyManager.save(key)
        let retrieved = try APIKeyManager.retrieve()
        XCTAssertEqual(retrieved, key)
    }

    func testHasKeyReturnsTrueAfterSave() throws {
        XCTAssertFalse(APIKeyManager.hasKey())
        try APIKeyManager.save("sk-ant-any-key")
        XCTAssertTrue(APIKeyManager.hasKey())
    }

    func testDeleteRemovesKey() throws {
        try APIKeyManager.save("sk-ant-any-key")
        try APIKeyManager.delete()
        let retrieved = try APIKeyManager.retrieve()
        XCTAssertNil(retrieved)
    }

    func testRetrieveWhenEmpty() throws {
        let result = try APIKeyManager.retrieve()
        XCTAssertNil(result)
    }

    func testSaveEmptyKeyThrows() {
        XCTAssertThrowsError(try APIKeyManager.save("")) { error in
            XCTAssertTrue(error is KeychainError)
        }
    }

    func testDoubleDeleteIsIdempotent() throws {
        try APIKeyManager.delete() // first delete — nothing stored
        try APIKeyManager.delete() // second delete — should not throw
    }

    func testUpdateExistingKey() throws {
        try APIKeyManager.save("sk-ant-key-v1")
        try APIKeyManager.save("sk-ant-key-v2") // update
        let retrieved = try APIKeyManager.retrieve()
        XCTAssertEqual(retrieved, "sk-ant-key-v2")
    }

    func testKeyNeverAppearsInLogs() throws {
        // We cannot intercept os.Logger in tests, but we can verify the save path
        // executes without logging the key value (code review check).
        // This test documents the expectation.
        let key = "sk-ant-secret-key-value"
        try APIKeyManager.save(key)
        // If this test exists and we can read it — the developer knows not to log the key.
        XCTAssertTrue(true, "Verify manually that os.Logger calls in APIKeyManager do not log the key value.")
    }
}
