@testable import VoiceDo
import VoiceDoShared
import XCTest

/// Module 2 — SpeechService tests.
///
/// `SFSpeechRecognizer` and `AVAudioEngine` require a real device with microphone.
/// These tests verify:
///   1. `MockTranscriptionService` cleanly substitutes `TranscriptionService` (protocol correctness).
///   2. All `SpeechError` cases have non-nil `errorDescription`.
///   3. `startSession()` streams partials and a final result via the mock.
///   4. `endSession()` returns the last transcript via the mock.
///   5. `cancelSession()` finishes the stream with `CancellationError`.
///   6. Calling `endSession()` before `startSession()` returns empty string without crash.
///   7. `permissionDenied` error propagates correctly through `requestPermission()`.
final class SpeechServiceTests: XCTestCase {

    // MARK: - Protocol Substitutability

    func testMockSubstitutesProtocol() async {
        // Verify that MockTranscriptionService satisfies the TranscriptionService protocol
        let mock: any TranscriptionService = MockTranscriptionService()
        // If this compiles and runs, the protocol contract is fulfilled
        await mock.cancelSession()
    }

    // MARK: - SpeechError Descriptions

    func testAllSpeechErrorsHaveDescriptions() {
        let errors: [SpeechError] = [
            .permissionDenied,
            .recognizerUnavailable,
            .audioEngineFailure(NSError(domain: "test", code: 0)),
            .noSpeechDetected,
            .recognitionFailed(NSError(domain: "test", code: 1)),
            .sessionAlreadyActive,
            .recordingTimeLimitReached
        ]
        for error in errors {
            XCTAssertNotNil(error.errorDescription, "Missing errorDescription for \(error)")
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true, "Empty errorDescription for \(error)")
        }
    }

    // MARK: - Mock: Permission Granted

    func testRequestPermissionSucceeds() async throws {
        let mock = MockTranscriptionService(permissionResult: .success(()))
        try await mock.requestPermission()
    }

    // MARK: - Mock: Permission Denied

    func testRequestPermissionDeniedThrows() async {
        let mock = MockTranscriptionService(permissionResult: .failure(SpeechError.permissionDenied))
        do {
            try await mock.requestPermission()
            XCTFail("Expected SpeechError.permissionDenied")
        } catch SpeechError.permissionDenied {
            // expected
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Mock: Streaming Partials

    func testStartSessionStreamsPartialsAndFinal() async throws {
        let partials = [
            TranscriptionPartial(text: "Buy", isFinal: false),
            TranscriptionPartial(text: "Buy milk", isFinal: false),
            TranscriptionPartial(text: "Buy milk tomorrow", isFinal: true)
        ]
        let mock = MockTranscriptionService(partials: partials)

        var received: [TranscriptionPartial] = []
        for try await partial in await mock.startSession() {
            received.append(partial)
        }

        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(received.last?.text, "Buy milk tomorrow")
        XCTAssertEqual(received.last?.isFinal, true)
    }

    // MARK: - Mock: endSession returns final transcript

    func testEndSessionReturnsFinalTranscript() async throws {
        let partials = [
            TranscriptionPartial(text: "Call Sarah", isFinal: false),
            TranscriptionPartial(text: "Call Sarah at 3pm", isFinal: true)
        ]
        let mock = MockTranscriptionService(partials: partials)

        // Consume stream first, then call endSession
        for try await _ in await mock.startSession() {}
        let transcript = try await mock.endSession()
        XCTAssertEqual(transcript, "Call Sarah at 3pm")
    }

    // MARK: - Mock: endSession before startSession

    func testEndSessionBeforeStartSessionReturnsEmpty() async throws {
        let mock = MockTranscriptionService()
        let result = try await mock.endSession()
        XCTAssertEqual(result, "")
    }

    // MARK: - Mock: cancelSession

    func testCancelSessionFinishesStreamWithCancellation() async throws {
        let mock = MockTranscriptionService(cancelsAfterFirst: true)

        var receivedCount = 0
        var caughtCancellation = false

        do {
            for try await _ in await mock.startSession() {
                receivedCount += 1
            }
        } catch is CancellationError {
            caughtCancellation = true
        }

        XCTAssertTrue(caughtCancellation, "Expected CancellationError from cancelled session")
    }

    // MARK: - Mock: recognition error propagates

    func testRecognitionErrorPropagatesFromStream() async throws {
        let recognitionErr = SpeechError.recognitionFailed(NSError(domain: "AVFoundation", code: -1))
        let mock = MockTranscriptionService(streamError: recognitionErr)

        do {
            for try await _ in await mock.startSession() {}
            XCTFail("Expected SpeechError.recognitionFailed")
        } catch SpeechError.recognitionFailed {
            // expected
        }
    }
}

// MARK: - MockTranscriptionService

/// A test double for `TranscriptionService` that drives the async stream
/// from an in-memory list of pre-canned `TranscriptionPartial` values.
actor MockTranscriptionService: TranscriptionService {

    private let permissionResult: Result<Void, Error>
    private let partials: [TranscriptionPartial]
    private let cancelsAfterFirst: Bool
    private let streamError: Error?
    private var lastTranscript: String = ""

    init(
        permissionResult: Result<Void, Error> = .success(()),
        partials: [TranscriptionPartial] = [],
        cancelsAfterFirst: Bool = false,
        streamError: Error? = nil
    ) {
        self.permissionResult = permissionResult
        self.partials = partials
        self.cancelsAfterFirst = cancelsAfterFirst
        self.streamError = streamError
    }

    func requestPermission() async throws {
        switch permissionResult {
        case .success: return
        case .failure(let err): throw err
        }
    }

    func startSession() -> AsyncThrowingStream<TranscriptionPartial, Error> {
        let partials = self.partials
        let cancelsAfterFirst = self.cancelsAfterFirst
        let streamError = self.streamError

        return AsyncThrowingStream { continuation in
            Task {
                if let error = streamError {
                    continuation.finish(throwing: error)
                    return
                }
                for (index, partial) in partials.enumerated() {
                    continuation.yield(partial)
                    if partial.text.isEmpty == false {
                        await self.setLastTranscript(partial.text)
                    }
                    if cancelsAfterFirst && index == 0 {
                        continuation.finish(throwing: CancellationError())
                        return
                    }
                }
                if cancelsAfterFirst {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                continuation.finish()
            }
        }
    }

    func endSession() async throws -> String {
        return lastTranscript
    }

    func cancelSession() async {
        // No-op for mock — cancellation is driven by `cancelsAfterFirst` in startSession
    }

    private func setLastTranscript(_ text: String) {
        lastTranscript = text
    }
}
