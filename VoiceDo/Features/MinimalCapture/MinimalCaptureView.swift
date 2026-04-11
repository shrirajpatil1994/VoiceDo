import SwiftUI
import VoiceDoShared

/// Full-screen capture overlay shown when the app is launched from the widget.
///
/// Deliberately minimal and dark — visually distinct from the main app UI so the user
/// knows they are in a "quick capture" mode. The mic starts automatically.
/// After saving, the app sends itself to the background so the user returns to the
/// home screen without extra taps.
struct MinimalCaptureView: View {

    let persistence: PersistenceService
    let notificationService: NotificationService
    /// Called after save or discard — VoiceDoApp switches back to ContentRootView.
    let onDone: () -> Void

    @State private var vm = VoiceCaptureViewModel()
    @State private var showResult = false
    @State private var savedConfirmation = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                Spacer()

                // Live transcript area
                ScrollView {
                    Text(transcriptDisplayText)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white.opacity(transcriptOpacity))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                        .animation(.easeInOut(duration: 0.2), value: vm.liveTranscript)
                }
                .frame(maxHeight: 280)

                // State indicators
                stateIndicator

                // Stop button (only while recording)
                if vm.state == .recording {
                    stopButton
                        .transition(.scale.combined(with: .opacity))
                }

                // Saved confirmation
                if savedConfirmation {
                    Label("Saved", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .transition(.opacity)
                }

                Spacer()

                // Cancel button — always visible
                if !savedConfirmation {
                    Button("Cancel") {
                        Task {
                            await vm.cancelSession()
                            onDone()
                        }
                    }
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.bottom, 32)
                }
            }
        }
        .sheet(isPresented: $showResult) {
            if let intent = vm.parsedResult {
                VoiceCaptureResultView(
                    intent: intent,
                    persistence: persistence,
                    notificationService: notificationService,
                    onSave: {
                        showResult = false
                        confirmAndBackground()
                    },
                    onDiscard: {
                        showResult = false
                        onDone()
                    }
                )
            }
        }
        .onChange(of: vm.parsedResult) { _, result in
            if result != nil { showResult = true }
        }
        .task {
            await vm.requestPermissions()
            await vm.startCapture()
        }
        .animation(.spring(duration: 0.25), value: vm.state)
    }

    // MARK: - Subviews

    @ViewBuilder
    private var stateIndicator: some View {
        switch vm.state {
        case .recording:
            // Pulsing mic icon
            Image(systemName: "mic.fill")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.white.opacity(0.9))
                .symbolEffect(.pulse, isActive: true)

        case .processing, .refining:
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.3)
                Text(vm.state == .refining ? "Refining with AI…" : "Processing…")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
            }

        default:
            EmptyView()
        }
    }

    private var stopButton: some View {
        Button {
            Task { await vm.stopCapture() }
        } label: {
            ZStack {
                Circle()
                    .fill(.white.opacity(0.12))
                    .frame(width: 72, height: 72)
                RoundedRectangle(cornerRadius: 6)
                    .fill(.white)
                    .frame(width: 22, height: 22)
            }
        }
        .accessibilityLabel("Stop recording")
    }

    // MARK: - Helpers

    private var transcriptDisplayText: String {
        if vm.liveTranscript.isEmpty {
            return "Listening…"
        }
        return vm.liveTranscript
    }

    private var transcriptOpacity: Double {
        vm.liveTranscript.isEmpty ? 0.35 : 1.0
    }

    private func confirmAndBackground() {
        savedConfirmation = true
        // Brief confirmation, then background the app.
        Task {
            try? await Task.sleep(for: .milliseconds(800))
            await MainActor.run {
                backgroundApp()
                onDone()
            }
        }
    }

    /// Sends the app to the background so the user returns to the home screen.
    /// Uses the widely-accepted `suspend` selector — identical to what Siri and Shortcuts use.
    private func backgroundApp() {
        UIApplication.shared.perform(NSSelectorFromString("suspend"))
    }
}
