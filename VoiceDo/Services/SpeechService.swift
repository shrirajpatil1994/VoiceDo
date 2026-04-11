import AVFoundation
import Foundation
import Network
import os.log
import Speech
import VoiceDoShared

// MARK: - TranscriptionPartial

/// A streaming partial result from the transcription engine.
public struct TranscriptionPartial: Sendable {
    /// The current best-guess transcript (grows as user speaks).
    public let text: String
    /// Whether this is the final result (speech ended).
    public let isFinal: Bool
}

// MARK: - SpeechError

enum SpeechError: Error, LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case audioEngineFailure(Error)
    case noSpeechDetected
    case recognitionFailed(Error)
    case sessionAlreadyActive
    case recordingTimeLimitReached

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or speech recognition permission was denied. Please enable it in Settings."
        case .recognizerUnavailable:
            return "Speech recognition is not available right now. Check your device language settings."
        case .audioEngineFailure(let err):
            return "Audio engine error: \(err.localizedDescription)"
        case .noSpeechDetected:
            return "No speech was detected. Please try again."
        case .recognitionFailed(let err):
            return "Speech recognition failed: \(err.localizedDescription)"
        case .sessionAlreadyActive:
            return "A recording session is already active."
        case .recordingTimeLimitReached:
            return "Maximum recording time reached (\(Int(AppConstants.maxRecordingSeconds))s)."
        }
    }
}

// MARK: - TranscriptionService Protocol

/// Abstraction over the speech recognition engine.
/// Implemented by `SFSpeechTranscriptionService` (V1).
/// Swap for `WhisperTranscriptionService` in V2 without changing callers.
protocol TranscriptionService: Actor {
    /// Request microphone + speech recognition permissions.
    /// Throws `SpeechError.permissionDenied` if denied.
    func requestPermission() async throws

    /// Begin a transcription session and stream partial results.
    /// Returns an `AsyncThrowingStream` that yields `TranscriptionPartial` values.
    /// The stream ends when `endSession()` or `cancelSession()` is called,
    /// or when the time limit is reached.
    func startSession() -> AsyncThrowingStream<TranscriptionPartial, Error>

    /// Stop the recording and return the final transcript string.
    /// Safe to call even if `startSession()` was never called.
    func endSession() async throws -> String

    /// Cancel the session without returning a result.
    func cancelSession() async
}

// MARK: - NetworkMonitor

/// Lightweight wrapper around NWPathMonitor.
/// Shared instance — cheap to query.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.shrirajpatil.voicedo.network", qos: .utility)
    private var currentPath: NWPath

    var isConnected: Bool { currentPath.status == .satisfied }

    private init() {
        currentPath = monitor.currentPath
        monitor.pathUpdateHandler = { [weak self] path in
            self?.currentPath = path
        }
        monitor.start(queue: queue)
    }
}

// MARK: - SFSpeechTranscriptionService

/// V1 implementation using `SFSpeechRecognizer` + `AVAudioEngine`.
/// - Online mode (default when network available): server-based recognition — more accurate,
///   handles pauses and longer utterances better.
/// - Offline mode (no network): `requiresOnDeviceRecognition = true`.
/// - Accumulates text across silence gaps — session does NOT stop on mid-utterance pauses.
/// - Automatically routes to connected headphone mic (wired or Bluetooth HFP).
actor SFSpeechTranscriptionService: TranscriptionService {

    // MARK: - Private State

    private let logger = Logger(subsystem: AppConstants.logSubsystem, category: "SpeechService")

    private lazy var speechRecognizer: SFSpeechRecognizer = {
        guard let recognizer = SFSpeechRecognizer(locale: Locale.current)
                ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")) else {
            fatalError("SFSpeechRecognizer unavailable for current and en-US locale")
        }
        return recognizer
    }()

    private var audioEngine: AVAudioEngine = AVAudioEngine()
    private var recognitionTask: SFSpeechRecognitionTask?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var streamContinuation: AsyncThrowingStream<TranscriptionPartial, Error>.Continuation?

    /// All text from completed recognition segments (accumulated across pauses).
    private var confirmedText: String = ""
    /// Best partial from the current in-flight segment.
    private var currentSegmentBest: String = ""
    /// True once `endSession()` has been called — next `isFinal` truly closes the stream.
    private var sessionEnding: Bool = false
    private var isSessionActive: Bool = false
    private var timeLimitTask: Task<Void, Never>?

    // MARK: - Permission

    func requestPermission() async throws {
        // Speech recognition permission
        let speechStatus = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
        guard speechStatus == .authorized else {
            logger.error("Speech recognition permission denied: \(speechStatus.rawValue)")
            throw SpeechError.permissionDenied
        }

        // Microphone permission (iOS 17+)
        let micGranted = await AVAudioApplication.requestRecordPermission()
        guard micGranted else {
            logger.error("Microphone permission denied")
            throw SpeechError.permissionDenied
        }

        logger.info("Speech + microphone permissions granted")
    }

    // MARK: - Session

    func startSession() -> AsyncThrowingStream<TranscriptionPartial, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try self.beginRecording(continuation: continuation)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private func beginRecording(
        continuation: AsyncThrowingStream<TranscriptionPartial, Error>.Continuation
    ) throws {
        guard !isSessionActive else {
            throw SpeechError.sessionAlreadyActive
        }

        guard speechRecognizer.isAvailable else {
            throw SpeechError.recognizerUnavailable
        }

        // Configure audio session.
        // .playAndRecord is required for .allowBluetoothHFP to work.
        // iOS automatically picks the highest-priority input:
        //   wired headset mic > Bluetooth HFP mic > built-in mic.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(
                .playAndRecord,
                mode: .measurement,
                options: [.duckOthers, .allowBluetoothHFP]
            )
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            throw SpeechError.audioEngineFailure(error)
        }

        self.streamContinuation = continuation
        self.confirmedText = ""
        self.currentSegmentBest = ""
        self.sessionEnding = false
        self.isSessionActive = true

        // Create the initial recognition request.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = !NetworkMonitor.shared.isConnected
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // Install tap on the STOPPED engine — this MUST happen before prepare()/start().
        // Installing a tap after the engine is running can trigger an uncaught NSException.
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0) // no-op on first call; safe on subsequent calls
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        // Now prepare and start the engine.
        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            throw SpeechError.audioEngineFailure(error)
        }

        // Start the recognition task.
        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { await self.handleRecognitionResult(result: result, error: error) }
        }

        // Auto-stop after time limit
        timeLimitTask = Task {
            try? await Task.sleep(for: .seconds(AppConstants.maxRecordingSeconds))
            guard !Task.isCancelled else { return }
            await self.handleTimeLimitReached()
        }

        logger.info("Recording session started (online: \(NetworkMonitor.shared.isConnected))")
    }

    // MARK: - Recognition Segment (pause-restart only)

    /// Restart recognition after a mid-session pause — the audio engine stays running.
    /// Swaps the tap so the new request receives audio. Never calls prepare()/start().
    private func startRecognitionSegment() {
        recognitionTask?.cancel()
        recognitionTask = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = !NetworkMonitor.shared.isConnected
        request.shouldReportPartialResults = true
        recognitionRequest = request

        // Remove old tap, install new one capturing the new request directly.
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            request.append(buffer)
        }

        recognitionTask = speechRecognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { await self.handleRecognitionResult(result: result, error: error) }
        }
    }

    // MARK: - Result Handling

    private func handleRecognitionResult(
        result: SFSpeechRecognitionResult?,
        error: Error?
    ) {
        if let result {
            let segmentText = result.bestTranscription.formattedString
            currentSegmentBest = segmentText

            // Build display text: all confirmed segments + current in-flight segment.
            let displayText = confirmedText.isEmpty
                ? segmentText
                : confirmedText + " " + segmentText

            streamContinuation?.yield(TranscriptionPartial(text: displayText, isFinal: false))

            if result.isFinal {
                // Commit this segment to the confirmed buffer.
                confirmedText = displayText
                currentSegmentBest = ""

                if sessionEnding {
                    // endSession() was called — close the stream for real.
                    stopRecordingCleanly()
                    streamContinuation?.finish()
                    streamContinuation = nil
                    logger.info("Session ended cleanly. Final transcript: \(self.confirmedText.count) chars")
                } else {
                    // Mid-session pause — keep audio engine running, restart recognition segment.
                    logger.debug("Pause detected — restarting recognition segment. Confirmed so far: \(self.confirmedText.count) chars")
                    startRecognitionSegment()
                }
            }
        }

        if let error {
            // Ignore "no speech" errors between segments — they are normal on pauses.
            let nsError = error as NSError
            let isSilenceError = nsError.domain == "kAFAssistantErrorDomain" && nsError.code == 1110
            if isSilenceError && !sessionEnding {
                logger.debug("Silence timeout on segment — restarting")
                startRecognitionSegment()
                return
            }

            let speechErr = SpeechError.recognitionFailed(error)
            logger.error("Recognition error: \(error.localizedDescription)")
            stopRecordingCleanly()
            streamContinuation?.finish(throwing: speechErr)
            streamContinuation = nil
        }
    }

    private func handleTimeLimitReached() {
        logger.info("Recording time limit reached — auto-stopping")
        sessionEnding = true
        recognitionRequest?.endAudio()
        timeLimitTask = nil
    }

    // MARK: - End / Cancel

    func endSession() async throws -> String {
        guard isSessionActive else {
            // Return whatever we have accumulated so far.
            let result = confirmedText.isEmpty ? currentSegmentBest : confirmedText
            return result
        }

        sessionEnding = true
        recognitionRequest?.endAudio()

        // Give the recognition task a moment to deliver its final result.
        try? await Task.sleep(for: .milliseconds(600))

        // If it hasn't finished naturally, clean up now.
        if isSessionActive {
            stopRecordingCleanly()
        }

        let result = confirmedText.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.isEmpty {
            throw SpeechError.noSpeechDetected
        }
        logger.info("Session ended via endSession(). Final transcript: \(result.count) chars")
        return result
    }

    func cancelSession() async {
        guard isSessionActive else { return }
        logger.info("Session cancelled")
        stopRecordingCleanly()
        streamContinuation?.finish(throwing: CancellationError())
        streamContinuation = nil
    }

    // MARK: - Cleanup

    private func stopRecordingCleanly() {
        timeLimitTask?.cancel()
        timeLimitTask = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil

        // Always remove the tap — safe even if none is installed.
        // Do this before stopping the engine.
        audioEngine.inputNode.removeTap(onBus: 0)
        if audioEngine.isRunning {
            audioEngine.stop()
        }

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        isSessionActive = false
    }
}
