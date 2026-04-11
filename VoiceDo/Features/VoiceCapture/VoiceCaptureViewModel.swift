import Foundation
import SwiftUI
import VoiceDoShared

// MARK: - VoiceDoError

enum VoiceDoError: Error, LocalizedError, Identifiable {
    case speech(SpeechError)
    case parse(ParseError)
    case persistence(Error)
    case notification(Error)
    case generic(String)

    var id: String { localizedDescription }

    var errorDescription: String? {
        switch self {
        case .speech(let err): return err.localizedDescription
        case .parse(let err): return err.localizedDescription
        case .persistence(let err): return "Storage error: \(err.localizedDescription)"
        case .notification(let err): return "Notification error: \(err.localizedDescription)"
        case .generic(let msg): return msg
        }
    }
}

// MARK: - VoiceCaptureViewModel

@MainActor
@Observable
final class VoiceCaptureViewModel {

    // MARK: - State Machine

    enum State: Equatable {
        case idle
        case permissionNeeded
        case recording
        case processing
        case refining
        case done
    }

    // MARK: - Published State

    var state: State = .idle
    var liveTranscript: String = ""
    var parsedResult: ParsedIntent?
    var error: VoiceDoError?

    // MARK: - Private

    private let speechService: SFSpeechTranscriptionService = SFSpeechTranscriptionService()
    private let intentParser: IntentParserService = IntentParserService()
    private var streamTask: Task<Void, Never>?

    // MARK: - Permission

    func requestPermissions() async {
        do {
            try await speechService.requestPermission()
            state = .idle
        } catch {
            state = .permissionNeeded
            self.error = .speech(error as? SpeechError ?? .permissionDenied)
        }
    }

    // MARK: - Record Button Tap

    func handleRecordButtonTap() async {
        switch state {
        case .idle:
            await startRecording()
        case .recording:
            await stopAndParse()
        default:
            break
        }
    }

    // MARK: - One-touch recording (called from DashboardView gesture)

    /// Start recording immediately (press-and-hold gesture began).
    func startCapture() async {
        guard state == .idle else { return }
        await startRecording()
    }

    /// Stop recording and parse (press released, or send tapped when locked).
    func stopCapture() async {
        guard state == .recording else { return }
        await stopAndParse()
    }

    // MARK: - Recording

    private func startRecording() async {
        state = .recording
        liveTranscript = ""

        let stream = await speechService.startSession()
        streamTask = Task {
            do {
                for try await partial in stream {
                    liveTranscript = partial.text
                    if partial.isFinal {
                        await stopAndParse()
                        break
                    }
                }
            } catch {
                self.error = .speech(error as? SpeechError ?? .recognitionFailed(error))
                state = .idle
            }
        }
    }

    private func stopAndParse() async {
        streamTask?.cancel()
        streamTask = nil

        do {
            let finalTranscript = try await speechService.endSession()
            liveTranscript = finalTranscript
            await parseTranscript(finalTranscript)
        } catch let err as SpeechError {
            error = .speech(err)
            state = .idle
        } catch {
            self.error = .generic(error.localizedDescription)
            state = .idle
        }
    }

    // MARK: - Parsing

    private func parseTranscript(_ transcript: String) async {
        state = .processing

        // Determine if Claude will be called (to show "refining" UI)
        let hasKey = APIKeyManager.hasKey()
        if hasKey {
            // Small delay to let UI settle before showing refining state
            try? await Task.sleep(for: .milliseconds(300))
            state = .refining
        }

        do {
            let intent = try await intentParser.parse(transcript: transcript)
            parsedResult = intent
            state = .done
        } catch let err as ParseError {
            error = .parse(err)
            state = .idle
        } catch {
            self.error = .generic(error.localizedDescription)
            state = .idle
        }
    }

    // MARK: - Cancel (from dismiss button)

    func cancelSession() async {
        await speechService.cancelSession()
        resetToIdle()
    }

    // MARK: - Reset

    func resetToIdle() {
        state = .idle
        liveTranscript = ""
        parsedResult = nil
        error = nil
        streamTask?.cancel()
        streamTask = nil
    }
}

// MARK: - ParsedIntent: Identifiable (for sheet binding)
// @retroactive explicitly acknowledges this is a cross-module conformance.

extension ParsedIntent: @retroactive Identifiable {
    public var id: String { title + (detectedDueDate?.description ?? "") }
}
