import AppIntents
import VoiceDoShared

// MARK: - StartVoiceCaptureIntent

/// The App Intent fired when the user taps the mic button on the widget.
///
/// `openAppWhenRun = true` is required because `SFSpeechRecognizer` needs the
/// microphone entitlement, which is not available in widget extensions.
/// The app opens and immediately presents `VoiceCaptureView` via the deep-link URL scheme.
struct StartVoiceCaptureIntent: AppIntent {

    static var title: LocalizedStringResource = "Capture Voice Note"
    static var description = IntentDescription(
        "Open VoiceDo and immediately start a voice recording.",
        categoryName: "Capture"
    )
    static var openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        // The app receives this via `onOpenURL` registered in VoiceDoApp.
        // Opening the app with the capture URL triggers VoiceCaptureView immediately.
        return .result()
    }
}
