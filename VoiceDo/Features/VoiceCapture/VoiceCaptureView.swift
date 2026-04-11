import SwiftUI
import VoiceDoShared

/// The voice recording sheet — presented from widget tap or dashboard mic button.
struct VoiceCaptureView: View {

    let persistence: PersistenceService
    let notificationService: NotificationService
    let onDismiss: () -> Void

    @State private var viewModel = VoiceCaptureViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Color.vdBackground.ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Mic indicator
                    MicIndicator(state: viewModel.state)
                        .padding(.bottom, 40)

                    // Live transcript box
                    TranscriptView(
                        transcript: viewModel.liveTranscript,
                        state: viewModel.state
                    )
                    .padding(.horizontal, 28)

                    Spacer()

                    // Primary action
                    Button {
                        Task { await viewModel.handleRecordButtonTap() }
                    } label: {
                        Text(recordButtonLabel)
                            .vdPrimaryButton()
                    }
                    .disabled(viewModel.state == .processing
                        || viewModel.state == .refining
                        || viewModel.state == .done)
                    .opacity(viewModel.state == .processing || viewModel.state == .refining ? 0.5 : 1)
                    .padding(.horizontal, 28)
                    .padding(.bottom, 12)
                    .accessibilityLabel(recordButtonLabel)
                }
            }
            .navigationTitle("New Capture")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        Task { await viewModel.cancelSession() }
                        onDismiss()
                    }
                    .foregroundStyle(Color.vdInk)
                }
            }
            .sheet(item: $viewModel.parsedResult) { result in
                VoiceCaptureResultView(
                    intent: result,
                    persistence: persistence,
                    notificationService: notificationService,
                    onSave: { onDismiss() },
                    onDiscard: { viewModel.resetToIdle() }
                )
            }
            .alert(error: $viewModel.error)
            .task { await viewModel.requestPermissions() }
        }
    }

    private var recordButtonLabel: String {
        switch viewModel.state {
        case .idle, .permissionNeeded: return "Start Recording"
        case .recording: return "Stop & Save"
        case .processing: return "Processing…"
        case .refining: return "Refining with AI…"
        case .done: return "Done"
        }
    }
}

// MARK: - MicIndicator

struct MicIndicator: View {
    let state: VoiceCaptureViewModel.State

    var body: some View {
        ZStack {
            // Pulse ring — only when recording
            if state == .recording {
                Circle()
                    .stroke(Color.vdInk.opacity(0.12), lineWidth: 1)
                    .frame(width: 130, height: 130)
                    .scaleEffect(pulseScale)
                    .animation(
                        .easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                        value: pulseScale
                    )
            }

            Circle()
                .fill(state == .recording ? Color(white: 0.14) : Color.vdInk)
                .frame(width: 96, height: 96)

            Image(systemName: iconName)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(accessibilityLabel)
    }

    private var pulseScale: CGFloat { state == .recording ? 1.35 : 1.0 }

    private var iconName: String {
        switch state {
        case .idle, .permissionNeeded: return "mic"
        case .recording: return "waveform"
        case .processing: return "ellipsis"
        case .refining: return "sparkles"
        case .done: return "checkmark"
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .idle: return "Ready to record"
        case .permissionNeeded: return "Permission required"
        case .recording: return "Recording"
        case .processing: return "Processing"
        case .refining: return "Refining with AI"
        case .done: return "Done"
        }
    }
}

// MARK: - TranscriptView

struct TranscriptView: View {
    let transcript: String
    let state: VoiceCaptureViewModel.State

    var body: some View {
        VStack(spacing: 8) {
            Text(displayText)
                .font(.system(size: 16))
                .foregroundStyle(transcript.isEmpty ? Color.vdMuted : Color.vdInk)
                .multilineTextAlignment(.center)
                .animation(.easeInOut(duration: 0.2), value: transcript)

            if state == .refining {
                Text("Refining with AI…")
                    .font(.caption)
                    .foregroundStyle(Color.vdMuted)
            }
        }
        .frame(minHeight: 80)
        .frame(maxWidth: .infinity)
        .padding(18)
        .vdCard()
    }

    private var displayText: String {
        if !transcript.isEmpty { return transcript }
        switch state {
        case .idle: return "Tap Start Recording and begin speaking"
        case .permissionNeeded: return "Microphone access is needed"
        case .recording: return "Listening…"
        case .processing: return "Processing…"
        case .refining: return "Almost done…"
        case .done: return "Done!"
        }
    }
}

// MARK: - RecordButton (kept for backwards compat)

struct RecordButton: View {
    let state: VoiceCaptureViewModel.State
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(buttonLabel)
                .vdPrimaryButton()
        }
        .disabled(state == .processing || state == .refining || state == .done)
        .accessibilityLabel(buttonLabel)
    }

    private var buttonLabel: String {
        switch state {
        case .idle, .permissionNeeded: return "Start Recording"
        case .recording: return "Stop & Save"
        case .processing: return "Processing…"
        case .refining: return "Refining with AI…"
        case .done: return "Done"
        }
    }
}
